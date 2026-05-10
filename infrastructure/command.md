# Kubernetes diagnostic commands

> Replace `20.229.55.144` with your current master IP from `terraform output -raw master_public_ip`.

---

## Full health sweep — single SSH block

Run this once after every deploy or whenever something feels off:

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
echo "════════ 1. NODES (all should be Ready) ════════"
kubectl get nodes -o wide

echo ""
echo "════════ 2. NODE RESOURCES (CPU/Mem usage per node) ════════"
kubectl top nodes 2>/dev/null || echo "(metrics-server not installed — skip)"

echo ""
echo "════════ 3. ALL PODS (look for non-Running/Completed) ════════"
kubectl get pods -A -o wide

echo ""
echo "════════ 4. PROBLEMATIC PODS ONLY (should be EMPTY) ════════"
kubectl get pods -A | grep -vE "Running|Completed|^NAMESPACE" || echo "✅ none"

echo ""
echo "════════ 5. PODS WITH RECENT RESTARTS (>0 = investigate) ════════"
kubectl get pods -A --no-headers | awk '$5+0 > 0 {print}' | head -20 || echo "✅ none"

echo ""
echo "════════ 6. CONTROL PLANE COMPONENTS (kube-system) ════════"
kubectl get pods -n kube-system

echo ""
echo "════════ 7. RECENT WARNINGS/ERRORS (last 30 events) ════════"
kubectl get events -A --sort-by='.lastTimestamp' --field-selector type!=Normal | tail -30 || echo "✅ no warnings"

echo ""
echo "════════ 8. SERVICES + ENDPOINTS ════════"
kubectl get svc -A
echo ""
kubectl get endpoints -A | grep -v "^kube-system"

echo ""
echo "════════ 9. INGRESS-NGINX HEALTH ════════"
kubectl -n ingress-nginx get pods,svc,deploy

echo ""
echo "════════ 10. DEPLOYMENTS / DAEMONSETS HEALTH ════════"
kubectl get deploy,ds -A | awk 'NR==1 || $4 != $5 || $6 != $5'
echo "(only rows where DESIRED ≠ READY are shown — empty = all healthy)"

echo ""
echo "════════ 11. PVCs (should all be Bound) ════════"
kubectl get pvc -A 2>/dev/null || echo "(no PVCs yet)"

echo ""
echo "════════ 12. NETWORKING — Calico ════════"
kubectl -n calico-system get pods,daemonset

echo ""
echo "════════ 13. CLUSTER VERSION + COMPONENTS ════════"
kubectl version --short 2>/dev/null || kubectl version
kubectl cluster-info

echo ""
echo "════════ 14. API SERVER + ETCD HEALTH ════════"
kubectl get componentstatus 2>/dev/null || echo "(componentstatus deprecated in 1.29+, OK)"

echo ""
echo "════════ 15. CERTIFICATE EXPIRY (kubeadm) ════════"
sudo kubeadm certs check-expiration | head -30
EOF
```

---

## How to read the output (red flags)

| Section | Healthy | Investigate |
|---------|---------|-------------|
| 1. Nodes | All `Ready`, K8s v1.28.2 | Any `NotReady`, `SchedulingDisabled` |
| 3. Pods | All `Running` or `Completed` | `Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, `Error` |
| 4. Problematic pods | "✅ none" | any output → drill into that pod |
| 5. Restarts | "✅ none" or low numbers | high restart count → pod is unstable |
| 6. kube-system | etcd, apiserver, scheduler, controller-mgr, coredns, kube-proxy all Running | any missing or restarting |
| 7. Events | "✅ no warnings" or stale ones | recent FailedScheduling/Unhealthy/etc. |
| 9. ingress-nginx | 3 pods Running, 1 svc | <3 pods or pods Pending |
| 10. Deploy/DS | empty (READY=DESIRED everywhere) | rows shown → that deployment is unhealthy |
| 11. PVCs | all `Bound` | `Pending` → no StorageClass yet (Phase 3.1 fixes) |
| 12. Calico | all calico-* Running, DS = 3 desired/3 current | DS less than node count → CNI broken |
| 14. componentstatus | all `Healthy` (or deprecated note) | unhealthy = control plane issue |
| 15. Certs | all `> 1y` until expiry | <30d = renew with `kubeadm certs renew all` |

---

## Drill-down commands (when something looks wrong)

```bash
# Why is a specific pod unhealthy?
kubectl describe pod -n <namespace> <pod-name> | tail -30

# Logs from the failing container
kubectl logs -n <namespace> <pod-name> --tail=50

# Logs from previous crash (if pod is CrashLoopBackOff)
kubectl logs -n <namespace> <pod-name> --previous --tail=50

# Why didn't a pod schedule?
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>

# Resource pressure on a node?
kubectl describe node <node-name> | grep -A5 "Conditions\|Allocated resources"

# Network policy / DNS issue test pod
kubectl run -it --rm netshoot --image=nicolaka/netshoot --restart=Never -- \
  sh -c "nslookup kubernetes.default; curl -sk https://kubernetes.default"
```

---

## Quickest "is it alive?" check (one-liner)

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get nodes && echo "---" && kubectl get pods -A | grep -vE "Running|Completed"'
```

If the second part shows just the header, **everything is healthy**.

---

## IP / connectivity quick checks (from your laptop, no SSH)

```bash
# DNS resolves?
nslookup asterzheku.duckdns.org

# Port 80 reachable on each node?
curl -I http://20.229.55.144
curl -I http://104.40.249.39
curl -I http://52.142.215.164
# Expect: HTTP/1.1 404 Not Found, Server: nginx

# Port 443 reachable?
curl -kI https://20.229.55.144
# Expect: HTTP/2 404 (or whatever Ingress rule applies)

# Port 22 reachable?
nc -zv 20.229.55.144 22
# Expect: succeeded!
```

---

## Common per-component drill-downs

### Calico (CNI)

```bash
# DaemonSet status
kubectl -n calico-system get daemonset

# Per-pod logs (look for FATAL or ERROR)
for POD in $(kubectl -n calico-system get pods -l k8s-app=calico-node -o name); do
  echo "=== $POD ==="
  kubectl -n calico-system logs $POD --tail=20
done

# Cross-node ping test (creates a temp pod on a worker, pings from master)
kubectl run net-test --image=busybox --restart=Never -- sleep 300
sleep 5
PODIP=$(kubectl get pod net-test -o jsonpath='{.status.podIP}')
echo "Test pod IP: $PODIP"
ping -c 3 $PODIP
kubectl delete pod net-test --force --grace-period=0
```

### NGINX Ingress

```bash
# All ingress objects in cluster
kubectl get ingress -A

# Controller logs (last 50 lines, useful for 502/504 debugging)
kubectl -n ingress-nginx logs -l app.kubernetes.io/name=ingress-nginx --tail=50

# Show the rendered nginx.conf inside a controller pod
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | head -100
```

### cert-manager

```bash
# All Certificate objects + ready status
kubectl get certificate -A

# All ClusterIssuers (READY True = working)
kubectl get clusterissuer

# Why is a cert stuck Pending?
kubectl describe certificate -n <namespace> <cert-name>

# ACME challenge status
kubectl get challenge -A
kubectl describe challenge -n <namespace> <challenge-name>

# cert-manager controller logs
kubectl -n cert-manager logs deploy/cert-manager --tail=50
```

### Jenkins (after Phase 3)

```bash
# Pod state
kubectl -n jenkins get pods,svc,ingress,pvc

# Get admin password
kubectl -n jenkins get secret jenkins-admin-credentials \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d ; echo

# Jenkins controller logs (find errors during plugin install / startup)
kubectl -n jenkins logs jenkins-0 -c jenkins --tail=80

# Init container logs (if pod is Init:CrashLoopBackOff)
kubectl -n jenkins logs jenkins-0 -c init --tail=80
```

### Storage (local-path-provisioner)

```bash
# Default StorageClass set?
kubectl get storageclass     # one row should say "(default)"

# All PVs / PVCs
kubectl get pv
kubectl get pvc -A

# Where is a specific PV stored on a node?
kubectl get pv $(kubectl get pvc <pvc-name> -n <ns> -o jsonpath='{.spec.volumeName}') \
  -o jsonpath='{.spec.local.path}{"\n"}'
```

---

## Remediation cheatsheet

| Symptom | Likely cause | Quick fix |
|---------|--------------|-----------|
| `kubectl get nodes` shows NotReady | kubelet not running on that node | `ssh worker "sudo systemctl status kubelet; sudo journalctl -u kubelet --no-pager \| tail -30"` |
| Pod CrashLoopBackOff | check logs from prev container | `kubectl logs <pod> --previous` |
| Pod ImagePullBackOff | wrong image name or registry auth | `kubectl describe pod <pod>` → look at Events |
| Pod Pending forever | no node fits resources / no PV / taint mismatch | `kubectl describe pod <pod>` → look at Events |
| 502 from ingress | backend pod crashed or not Ready | `kubectl get pods -n <ns>` |
| 404 from ingress | no Ingress rule matches the Host header | `kubectl get ingress -A; kubectl describe ingress <name>` |
| Certificate stuck Pending | webhook not ready, or HTTP-01 challenge can't reach pod | `kubectl describe certificate <name>; kubectl describe challenge -A` |
| All cross-node networking broken | Calico VXLAN MTU mismatch / kernel module missing | `lsmod \| grep vxlan` on each node |

---

## Cluster destroy (when you're done for the day)

```bash
cd /mnt/c/Users/user/Desktop/kube/k8s-devops-project/infrastructure
terraform destroy -auto-approve
```

Removes all VMs/NICs/Public IPs (~3 min). The pre-existing RG/VNet/Subnet stay (they're data sources).

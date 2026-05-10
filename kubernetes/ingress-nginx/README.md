# ingress-nginx

NGINX Ingress controller running as a `DaemonSet` with `hostNetwork=true`. Every node (master + 2 workers) listens on host ports 80/443. An **Azure Load Balancer** (provisioned by Terraform) sits in front of all 3 nodes and is the public entry point.

## Traffic flow

```
client
  ↓
DuckDNS (asterzheku.duckdns.org)
  ↓
Azure Load Balancer (52.236.143.47)   ← stable public IP, HA
  ↓ (TCP probe :80, distributes to healthy backends)
┌─────┬─────┬─────┐
↓     ↓     ↓
master worker-1 worker-2  ← NGINX on each (DaemonSet, hostNetwork)
  ↓
Ingress rule → Service → pod
```

If any node dies, the LB removes it from the pool within ~10 sec and traffic flows to the survivors. DuckDNS never has to be re-pointed.

## Why hostNetwork (and not a Service of type LoadBalancer)

kubeadm clusters on Azure don't have the Azure cloud-controller-manager, so `Service.type=LoadBalancer` stays `Pending` forever. Two ways around it:

1. **Install Azure CCM** — non-trivial (managed identity + cloud-config + extra DaemonSet)
2. **hostNetwork + external Azure LB** ← what this repo does

The LB is provisioned by the [`load-balancer` Terraform module](../../modules/resources/azure/load-balancer/), backend pool = all 3 NICs, TCP probe on port 80. Every health check hits NGINX (which always responds 404 if no Ingress matches — that's "alive" from the LB's perspective).

## Install (Helm)

This replaces the ansible-installed manifest with a Helm-managed DaemonSet — easier upgrades, cleaner ownership.

Four small steps. Run them from your laptop in order.

### Step 1 — Install Helm on master (one-time per VM)

Skip if `ssh ... 'helm version --short'` already prints a version.

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
```

### Step 2 — Add the ingress-nginx Helm repo

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo update
EOF
```

### Step 3 — Push values.yaml to master

```bash
scp -i ~/ssh_key.pem values.yaml azureuser@20.229.55.144:/tmp/ingress-values.yaml
```

### Step 4 — Migrate (delete manifest install) + helm install

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
# 1. Delete the manifest-installed version (Helm refuses to adopt it)
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml --ignore-not-found

# 2. Drop the namespace so Helm starts fresh
kubectl delete namespace ingress-nginx --ignore-not-found --timeout=60s
sleep 10

# 3. Install via Helm
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version 4.7.1 \
  -f /tmp/ingress-values.yaml \
  --wait --timeout 5m

echo ""
echo "=== Pods (one per node) ==="
kubectl get pods -n ingress-nginx -o wide
EOF
```

⚠️ Brief outage during step 4 — between deleting the old install and helm finishing the new one, ports 80/443 don't answer. ~30 seconds. The LB will mark backends unhealthy until the new pods come up. Fine for a learning cluster; in production you'd run new + old in parallel and swap DNS.

## Verify

```bash
# 1. 3 pods, one per node
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get pods -n ingress-nginx -o wide'

# 2. Hit each VM IP directly — all should serve NGINX
for IP in 20.229.55.144 104.40.249.39 52.142.215.164; do
  echo "=== $IP ==="
  curl -I http://$IP
done

# 3. Hit the LB IP — distributed across backends
curl -I http://52.236.143.47

# 4. Hit via DNS — same LB IP under the hood
curl -I http://asterzheku.duckdns.org

# All should return: HTTP/1.1 404 Not Found, Server: nginx
```

## Upgrade

Edit `values.yaml`, then:
```bash
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx -f values.yaml --wait
```

## Rollback

```bash
helm rollback ingress-nginx -n ingress-nginx
```

## Skepticism

- **DaemonSet means every node carries the load** — fine for 3 nodes, costly at 50. Switch to a Deployment with replicas if you scale beyond ~10 nodes.
- **No Network Policy in front of NGINX on the VMs themselves** — the Azure NSG allows 80/443 from `0.0.0.0/0` (intentional, for public ingress). Restrict via NSG if you need stricter control.
- **hostNetwork pods can't co-exist with anything else binding 80/443** — if you ever add MetalLB or another LB on the host, conflict.
- **LB → backend health check is TCP, not HTTP** — TCP probes pass if NGINX is listening, even if it's broken at the HTTP layer. For tighter health checks, change the probe to HTTP and configure NGINX to expose a real `/healthz` path.
- **Single LB frontend IP** — if Azure has a region-wide outage of Standard LBs, you're down. Multi-region failover is out of scope.

## What if I want to skip the LB and point DNS at a node IP directly?

You can — DuckDNS at any node's public IP also works. You lose HA (single-node failure → outage) and stable IP across rebuilds. Not recommended now that the LB is provisioned.

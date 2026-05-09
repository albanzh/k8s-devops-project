# ingress-nginx

NGINX Ingress controller running as a `DaemonSet` with `hostNetwork=true`. Every node (master + 2 workers) listens on host ports 80/443.

## Why hostNetwork (and not a LoadBalancer service)

kubeadm clusters on Azure don't have the Azure cloud-controller-manager, so `Service.type=LoadBalancer` stays `Pending` forever. Two ways around it:

1. **Install Azure CCM** — non-trivial setup with managed identity + cloud-config
2. **hostNetwork** — controller binds to ports 80/443 directly on the host (this repo)

For a learning/demo cluster, hostNetwork is simpler and free.

## Install

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<EOF
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo update
EOF

# Copy values.yaml to master
scp -i ~/ssh_key.pem values.yaml azureuser@51.136.90.206:/tmp/ingress-values.yaml

# Install
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
# 1. Delete the manifest-installed version
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml --ignore-not-found

# 2. Make sure the namespace itself is gone (Helm will recreate it)
kubectl delete namespace ingress-nginx --ignore-not-found --timeout=60s

# 3. Wait a moment for cleanup
sleep 10

# 4. Now Helm can install cleanly
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version 4.7.1 \
  -f /tmp/ingress-values.yaml \
  --wait --timeout 5m

echo ""
echo "=== Pods ==="
kubectl get pods -n ingress-nginx -o wide
EOF

```


```

Then run the install above.

## Verify

```bash
kubectl get pods -n ingress-nginx -o wide
# Expect 3 pods (one per node), Status Running

# All node IPs should serve NGINX
for IP in 51.136.90.206 20.101.64.184 52.157.100.141; do
  curl -I http://$IP
don
# Expect: HTTP/1.1 404 Not Found, Server: nginx
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

- **DaemonSet means every node carries the load** — fine for 3 nodes, costly at 50. Switch back to Deployment with replicas if you scale beyond ~10 nodes.
- **No Network Policy in front of NGINX** — anything on port 80/443 of any node IP gets through. Add an Azure NSG rule restricting source IPs if you want stricter control (we currently allow `0.0.0.0/0`).
- **hostNetwork pods can't co-exist with anything else binding 80/443** on the same node. If you ever try to install MetalLB or another LB, conflicts.

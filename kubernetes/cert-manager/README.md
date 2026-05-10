# cert-manager

Automatic TLS certificate provisioning via Let's Encrypt.

## Context

| | |
|---|---|
| **Depends on** | ingress-nginx (Phase 3) — ACME HTTP-01 challenge needs a working Ingress |
| **Installs** | cert-manager + 2 ClusterIssuers (`letsencrypt-staging`, `letsencrypt-prod`) |
| **Next phase** | Jenkins (Phase 5) |
| **Master IP / Domain** | `20.229.55.144` / `asterzheku.duckdns.org` |

## How it works

```
You annotate an Ingress with cert-manager.io/cluster-issuer: letsencrypt-staging
            ↓
cert-manager creates a Certificate resource
            ↓
ACME HTTP-01 challenge: cert-manager places a token at /.well-known/acme-challenge/<token>
            ↓
Let's Encrypt fetches it via NGINX → confirms domain ownership
            ↓
cert-manager stores the issued cert in a K8s Secret
            ↓
NGINX reads the Secret and serves HTTPS
```

Total: ~30–90 sec from Ingress creation to working HTTPS (after the issuer is ready).

## Pre-requisites

- ingress-nginx healthy (3 controller pods Running, one per node) — see [../ingress-nginx/README.md](../ingress-nginx/README.md)
- Helm installed on master — `ssh ... 'helm version --short'` works
- DuckDNS resolves `asterzheku.duckdns.org` to the LB IP

## Step 1 — Push values.yaml + cluster-issuers.yaml to master

```bash
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/cert-manager/values.yaml \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/cert-manager/cluster-issuers.yaml \
  azureuser@20.229.55.144:/tmp/
```

## Step 2 — Add Helm repo

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update
EOF
```

## Step 3 — Install cert-manager + apply ClusterIssuers

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.14.0 \
  -f /tmp/values.yaml \
  --wait --timeout 5m

# Wait for the webhook BEFORE applying ClusterIssuers — otherwise they fail with
# "failed calling webhook" until the webhook service has endpoints.
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s
until kubectl get endpoints cert-manager-webhook -n cert-manager -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -q .; do
  echo "waiting for webhook endpoints..."; sleep 5
done

kubectl apply -f /tmp/cluster-issuers.yaml

echo ""
echo "=== ClusterIssuers ==="
kubectl get clusterissuer
EOF
```

## Verify

Both ClusterIssuers must show `READY=True`:

```
NAME                  READY   STATUS                                                 AGE
letsencrypt-prod      True    The ACME account was registered with the ACME server   5s
letsencrypt-staging   True    The ACME account was registered with the ACME server   5s
```

✅ Both `True` → done. Proceed to Phase 5 (Jenkins).

## Smoke test (optional — issue a real cert end-to-end)

```bash
DOMAIN="asterzheku.duckdns.org"
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<EOF
kubectl create ns cert-test --dry-run=client -o yaml | kubectl apply -f -
kubectl -n cert-test create deployment httpbin --image=kennethreitz/httpbin --dry-run=client -o yaml | kubectl apply -f -
kubectl -n cert-test expose deployment httpbin --port=80 --dry-run=client -o yaml | kubectl apply -f -

cat <<EOI | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin
  namespace: cert-test
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
spec:
  ingressClassName: nginx
  tls: [{hosts: ["${DOMAIN}"], secretName: httpbin-tls}]
  rules:
    - host: ${DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: httpbin, port: {number: 80}}}
EOI
EOF


# Wait 1-2 min, then:
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get certificate -A'
# Expect: httpbin-tls READY=True

curl -kI https://$DOMAIN   # -k because it's a STAGING cert
```

# 1. Cleanup the smoke test (releases the namespace + Ingress)
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl delete namespace cert-test'

# 2. Confirm clean state
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'kubectl get clusterissuer && echo "---" && kubectl get certificate -A'


## When to flip an Ingress to letsencrypt-prod

After a staging cert issues successfully **at least once**. Edit the Ingress annotation:
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod   # was: letsencrypt-staging
```

Delete the staging Secret so cert-manager re-issues from prod:
```bash
kubectl -n <namespace> delete secret <whatever-tls>
```

Wait 1-2 min, then `curl -I https://...` works without `-k` (browser-trusted).

## Upgrade

```bash
helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager -f /tmp/values.yaml --version v1.14.0 --wait
```

## Rollback

```bash
helm rollback cert-manager -n cert-manager
```

## Common failures + fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ClusterIssuer READY=False` | DNS unreachable from cluster | check pods can resolve external names: `kubectl run dns-test --rm -it --image=busybox --restart=Never -- nslookup acme-staging-v02.api.letsencrypt.org` |
| `failed calling webhook ... timeout` | Webhook not reachable cross-node | usually Calico MTU or VXLAN — restart calico-node pods |
| Cert stuck Pending >5 min | ACME challenge can't reach back to cluster | `nslookup yourdomain.com` from outside; verify DuckDNS points at LB IP |
| `urn:ietf:params:acme:error:rateLimited` | Hit LE prod rate limit (5 certs/week per FQDN) | switch issuer to `letsencrypt-staging` for ~1 week to recover |
| Ingress works but no cert | Annotation typo | `kubectl describe ingress <name>` and check the annotation |

## Skepticism

- **HTTP-01 challenge requires port 80 reachable** — works because Azure NSG allows :80 from `0.0.0.0/0`. Don't lock that down without using DNS-01 challenge.
- **Staging issuer's CA isn't browser-trusted** — that's the point; lets you iterate without rate limits.
- **No DNS-01 fallback configured** — if you ever need wildcard certs (`*.example.com`), HTTP-01 won't work; you'd need DNS-01 with API access to your DNS provider.

## Next phase →

[Phase 5 — Jenkins](../jenkins/README.md)

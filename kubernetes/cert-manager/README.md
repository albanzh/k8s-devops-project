# cert-manager

Automatic TLS certificate provisioning via Let's Encrypt.

## How it works

1. You annotate an Ingress: `cert-manager.io/cluster-issuer: letsencrypt-staging`
2. cert-manager sees the annotation, creates a `Certificate` resource
3. ACME HTTP-01 challenge: cert-manager places a token at `/.well-known/acme-challenge/<token>`
4. Let's Encrypt fetches it via NGINX → confirms you own the domain
5. cert-manager stores the issued cert in a K8s Secret
6. NGINX reads the Secret, serves HTTPS

Total time: 30-90 sec from Ingress creation to working HTTPS.

## Install

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<EOF
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update
EOF

# Copy values.yaml + cluster-issuers.yaml to master
scp -i ~/ssh_key.pem values.yaml cluster-issuers.yaml \
  azureuser@51.136.90.206:/tmp/

# Install
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.14.0 \
  -f /tmp/values.yaml \
  --wait --timeout 5m

# Wait for the webhook before applying ClusterIssuers (else they fail with
# "failed calling webhook" until the webhook service has endpoints)
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s
until kubectl get endpoints cert-manager-webhook -n cert-manager -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -q .; do
  echo "waiting for webhook endpoints..."; sleep 5
done

# Apply both ClusterIssuers
kubectl apply -f /tmp/cluster-issuers.yaml
kubectl get clusterissuer
EOF
```

## Verify

```bash
kubectl get clusterissuer
# Expect: both rows show READY=True
#   NAME                  READY   STATUS
#   letsencrypt-prod      True    The ACME account was registered with the ACME server
#   letsencrypt-staging   True    The ACME account was registered with the ACME server
```

## Smoke test (issue a real cert end-to-end)

```bash
DOMAIN="aster123.duckdns.org"   # ← your real DNS name
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<EOF
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
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'kubectl get certificate -A'
# Expect: httpbin-tls READY=True

# From your laptop (use -k because it's a STAGING cert; not browser-trusted)
curl -kI https://$DOMAIN
```

Cleanup once smoke test passes:
```bash
kubectl delete namespace cert-test
```

## Upgrade

```bash
helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager -f values.yaml --version v1.14.0 --wait
```

## Rollback

```bash
helm rollback cert-manager -n cert-manager
```

## Skepticism / common failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ClusterIssuer READY=False` | DNS unreachable from cluster | check pods can resolve external names |
| `failed calling webhook ... timeout` | webhook not reachable cross-node | usually Calico MTU or VXLAN; restart calico-node pods |
| Cert stuck Pending >5 min | ACME challenge can't reach back to your cluster | `nslookup yourdomain.com` from outside; if it doesn't resolve, fix DNS first |
| `urn:ietf:params:acme:error:rateLimited` | hit LE prod rate limit | switch issuer to `letsencrypt-staging` for ~1 week to recover |
| Ingress works but no cert | annotation typo | check `kubectl describe ingress` |

## When to flip to letsencrypt-prod

After a staging cert issues successfully **at least once**. Edit your Ingress:
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod   # was: letsencrypt-staging
```
Delete the old TLS Secret so cert-manager re-issues:
```bash
kubectl -n <namespace> delete secret <whatever-tls>
```
Wait 1-2 min, then `curl -I https://...` should work without `-k`.

# Kibana

UI for browsing logs in Elasticsearch.

## Context

| | |
|---|---|
| **Depends on** | Elasticsearch ([../elasticsearch/](../elasticsearch/)) up and reachable |
| **Installs** | Kibana Deployment + Ingress + Certificate in namespace `logging` |
| **Next phase** | Filebeat ([../filebeat/](../filebeat/)) — actually ships logs into ES |
| **URL** | `https://kibana.asterzheku.duckdns.org` |

## Pre-requisites

- Elasticsearch Running (1/1) in namespace `logging`
- cert-manager ClusterIssuers READY (for Kibana TLS)
- DuckDNS resolves `kibana.asterzheku.duckdns.org` to LB IP

## Step 1 — Push values.yaml

```bash
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/kibana/values.yaml \
  azureuser@20.229.55.144:/tmp/kibana-values.yaml
```

## Step 2 — Generate basic-auth Secret

Kibana's chart has no built-in auth, so we use NGINX basic-auth on the ingress.

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
PASS=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
htpasswd -bc /tmp/htpasswd admin "$PASS"
kubectl -n logging create secret generic logging-basic-auth \
  --from-file=auth=/tmp/htpasswd \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "════════════════════════════════════════════"
echo "Kibana basic-auth (SAVE THIS):"
echo "  user: admin"
echo "  pass: $PASS"
echo "════════════════════════════════════════════"
EOF
```

## Step 3 — Install Kibana

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'helm upgrade --install kibana elastic/kibana \
     -n logging -f /tmp/kibana-values.yaml --wait --timeout 10m'
```

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'kubectl get pods,ingress,certificate -n logging'
```

Expected:
- `pod/kibana-kibana-...` Running 1/1
- `ingress.networking.k8s.io/kibana-kibana` with host `kibana.asterzheku.duckdns.org`
- `certificate.cert-manager.io/kibana-tls` `READY=True`

Browser: `https://kibana.asterzheku.duckdns.org` → enter basic-auth → Kibana home page loads.

## Find bookstore logs (after Filebeat is installed)

1. Open Kibana → **Discover** (left sidebar)
2. Create a **Data view**: name=`logs`, index pattern=`filebeat-*`, timestamp=`@timestamp`
3. Add filter: `kubernetes.namespace : "bookstore"`
4. JSON logs from the FastAPI app appear — structured fields like `book_id`, `isbn` from `log.info(... extra=...)` calls in [main.py](../../bookstore-api/app/main.py)

## Upgrade

```bash
helm upgrade kibana elastic/kibana -n logging -f /tmp/kibana-values.yaml --wait
```

## Rollback

```bash
helm rollback kibana -n logging
```

## Common failures + fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Kibana "Service unavailable" for 2-3 min after pod is Running | UI bootstrapping (slow) | wait it out |
| `Unable to connect to Elasticsearch` | ES service not reachable | `kubectl logs -n logging elasticsearch-master-0` and confirm ES is Running |
| Basic-auth prompt loops forever | `logging-basic-auth` Secret missing or wrong format | recreate via Step 2 |
| Cert stuck Pending | DNS not resolving | `nslookup kibana.asterzheku.duckdns.org` — should return LB IP |

## Skepticism

- **Kibana takes 2-3 min after pod is Running** before the UI loads — be patient.
- **No SSO** → anyone with the basic-auth password sees all logs. Add OAuth proxy if multiple users.
- **No retention or rollup policy in Kibana** — index management lives in Elasticsearch (ILM). For prod, configure ILM there.

## Next phase →

[Filebeat](../filebeat/README.md)

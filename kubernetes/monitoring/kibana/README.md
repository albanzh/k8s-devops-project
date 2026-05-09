# Kibana

UI for browsing logs in Elasticsearch.

## Install (after elasticsearch is up)

```bash
# Push values
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/kibana/values.yaml \
  azureuser@51.136.90.206:/tmp/kibana-values.yaml

ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
# Generate basic-auth (separate from prometheus' since they're in different namespaces)
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

helm upgrade --install kibana elastic/kibana \
  -n logging -f /tmp/kibana-values.yaml --wait --timeout 10m
EOF
```

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'kubectl get pods,ingress,certificate -n logging'
```

Browser: `https://kibana.aster123.duckdns.org`

First login: enter the basic-auth password from above.

## Find bookstore logs

After Filebeat is installed (next):

1. **Discover** (left sidebar)
2. Create a **Data view**: name=`logs`, index pattern=`filebeat-*`, timestamp=`@timestamp`
3. Add filter: `kubernetes.namespace : "bookstore"`
4. You'll see JSON logs from the FastAPI app — structured fields like `book_id`, `isbn` from the `log.info(... extra=...)` calls in main.py

## Skepticism

- **Kibana takes 2-3 min after pod is Running** before the UI loads. Be patient.
- **No SSO** → anyone with the basic-auth password sees all logs. Add OAuth proxy if multiple users.

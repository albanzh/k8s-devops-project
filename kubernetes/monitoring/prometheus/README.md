# Prometheus + Grafana + Alertmanager

## Install

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update
EOF

# Push values.yaml + dashboard
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/prometheus/values.yaml \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/prometheus/bookstore-dashboard.yaml \
  azureuser@51.136.90.206:/tmp/

ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
# 1. Namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 2. Generate basic-auth password (for Prometheus ingress)
PASS=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
htpasswd -bc /tmp/htpasswd admin "$PASS"
kubectl -n monitoring create secret generic monitoring-basic-auth \
  --from-file=auth=/tmp/htpasswd \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "════════════════════════════════════════════"
echo "Prometheus basic-auth (SAVE THIS):"
echo "  user: admin"
echo "  pass: $PASS"
echo "════════════════════════════════════════════"

# 3. Install kube-prometheus-stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring -f /tmp/values.yaml --wait --timeout 20m

# 4. Apply bookstore dashboard ConfigMap
kubectl apply -f /tmp/bookstore-dashboard.yaml

# 5. Print Grafana credentials
echo ""
echo "════════════════════════════════════════════"
echo "Grafana login:"
echo "  user: admin"
echo "  pass: $(kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo "════════════════════════════════════════════"
EOF
```

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'kubectl get pods,ingress,certificate -n monitoring'
```

Expected:
- ~10 pods Running (Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter ×3, prometheus-operator)
- 2 Ingresses (Prometheus + Grafana)
- 2 Certificates `READY=True`

## Browser

| URL | Login |
|-----|-------|
| `https://grafana.aster123.duckdns.org` | `admin` + grafana password |
| `https://prometheus.aster123.duckdns.org` | `admin` + basic-auth password |

In Grafana → Dashboards → look for **Bookstore API** (auto-loaded from the ConfigMap). Once your bookstore pipeline runs and the API gets traffic, the panels populate.

## Skepticism

- **First Grafana login** asks to change the password — pick a strong one and save it.
- **`serviceMonitorSelectorNilUsesHelmValues: false`** — without this, the bookstore's ServiceMonitor wouldn't be picked up. The default helm-chart selector restricts to `release: prometheus` label only.
- **PV size: 10Gi** — fills up around 7-10 days of metrics. Bump if you keep the cluster long.
- **No Alertmanager receiver** — `'null'` receiver swallows alerts. Wire Slack/email if you actually want notifications.

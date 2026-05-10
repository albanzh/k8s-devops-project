# Prometheus + Grafana + Alertmanager (kube-prometheus-stack)

## Context

| | |
|---|---|
| **Depends on** | cert-manager (Phase 4), local-path StorageClass (for Prometheus PV) |
| **Installs** | Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, prometheus-operator (1 namespace: `monitoring`) |
| **Next phase** | Elasticsearch ([../elasticsearch/](../elasticsearch/)) |
| **URLs** | `grafana.asterzheku.duckdns.org`, `prometheus.asterzheku.duckdns.org` |

## Pre-requisites

- cert-manager READY (both ClusterIssuers `READY=True`)
- Default StorageClass exists — `kubectl get storageclass` shows `local-path (default)`
- DuckDNS resolves `grafana.asterzheku.duckdns.org` and `prometheus.asterzheku.duckdns.org` to the LB IP (wildcard makes this automatic)

## Step 1 — Push values.yaml + dashboard ConfigMap

```bash
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/prometheus/values.yaml \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/prometheus/bookstore-dashboard.yaml \
  azureuser@20.229.55.144:/tmp/
```

## Step 2 — Add Helm repo

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update
EOF
```

## Step 3 — Create namespace + basic-auth Secret (for Prometheus UI)

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

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
EOF
```

⚠️ **Save the password** — printed only once.

## Step 4 — Install kube-prometheus-stack + apply bookstore dashboard

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring -f /tmp/values.yaml --wait --timeout 20m

kubectl apply -f /tmp/bookstore-dashboard.yaml

echo ""
echo "════════════════════════════════════════════"
echo "Grafana login:"
echo "  user: admin"
echo "  pass: $(kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo "════════════════════════════════════════════"
EOF
```

⚠️ **Save the Grafana password.**

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'kubectl get pods,ingress,certificate -n monitoring'
```

Expected:
- ~10 pods Running (Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter ×3, prometheus-operator, etc.)
- 2 Ingresses (`prometheus.asterzheku.duckdns.org`, `grafana.asterzheku.duckdns.org`)
- 2 Certificates `READY=True`

## Browser

| URL | Login |
|-----|-------|
| `https://grafana.asterzheku.duckdns.org` | `admin` + Grafana password (Step 4 output) |
| `https://prometheus.asterzheku.duckdns.org` | `admin` + basic-auth password (Step 3 output) |

In Grafana → **Dashboards** → look for **Bookstore API**. After your bookstore pipeline runs and the API gets traffic, the panels populate.

## Upgrade

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring -f /tmp/values.yaml --wait
```

## Rollback

```bash
helm rollback prometheus -n monitoring
```

## Common failures + fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pods stuck Pending | No default StorageClass (PVC for Prometheus, Grafana, Alertmanager) | install local-path-provisioner — see [`../../jenkins/README.md` Step 2](../../jenkins/README.md) |
| Bookstore metrics missing in Prometheus | ServiceMonitor selector mismatch | values.yaml has `serviceMonitorSelectorNilUsesHelmValues: false` to pick up all SMs; if changed, also set `release: prometheus` label on bookstore SM |
| Grafana shows "Unable to connect to data source" | Prometheus pod still booting | wait 1-2 min after install completes |
| Bookstore dashboard missing in Grafana | Dashboard ConfigMap not applied | re-run `kubectl apply -f /tmp/bookstore-dashboard.yaml` |
| Cert stuck Pending | DNS not resolving | `nslookup grafana.asterzheku.duckdns.org` should return LB IP |

## Skepticism

- **First Grafana login asks to change password** — pick a strong one and save it.
- **`serviceMonitorSelectorNilUsesHelmValues: false`** — without this, the bookstore's ServiceMonitor wouldn't be picked up. The chart's default selector restricts to `release: prometheus` label only.
- **PV size: 10 GiB** — fills up around 7-10 days of metrics. Bump if you keep the cluster long.
- **No Alertmanager receiver** — `'null'` swallows alerts. Wire Slack/email in `values.yaml` if you actually want notifications.

## Next phase →

[Elasticsearch](../elasticsearch/README.md)

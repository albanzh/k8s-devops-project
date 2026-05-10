# Monitoring (Phase 8) — Prometheus + Grafana + ELK

Collects metrics + logs from the bookstore API and the cluster itself. Each component is in its own folder with a `values.yaml` + `README.md`.

## Context

| | |
|---|---|
| **Depends on** | bookstore deployed (Phase 7) — produces metrics + logs to observe |
| **Installs** | 4 Helm releases across 2 namespaces: `monitoring` (Prom/Grafana) + `logging` (ELK) |
| **Final phase** | yes — after this, the project is end-to-end working |
| **URLs** | `grafana.`/`prometheus.`/`kibana.asterzheku.duckdns.org` |

## Install order

```
1. prometheus/      kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter)
2. elasticsearch/   single-node ES for the demo
3. kibana/          UI for ELK
4. filebeat/        DaemonSet that ships pod logs to Elasticsearch
```

Each takes 5–10 min. **Total: ~30 min.**

> ⚠️ Do **not** install in parallel. Filebeat needs Elasticsearch ready (otherwise it crash-loops on startup until ES is reachable).

## Resource warning

These four components together use **~5 GiB RAM + ~2.5 cores**. With your 3 × D4s_v3 nodes (~48 GiB total), there's headroom but don't run the bookstore at high replica count alongside.

| Component | Memory | CPU |
|-----------|--------|-----|
| Prometheus | 1–2 GiB | 0.5 |
| Grafana | 256 MiB | 0.1 |
| Alertmanager | 128 MiB | 0.05 |
| node-exporter (DS) | 50 MiB × 3 | 0.05 × 3 |
| kube-state-metrics | 100 MiB | 0.1 |
| Elasticsearch | 2 GiB | 1.0 |
| Kibana | 512 MiB | 0.2 |
| Filebeat (DS) | 100 MiB × 3 | 0.1 × 3 |

## What you'll see at the end

| URL | What | Auth |
|-----|------|------|
| `https://grafana.asterzheku.duckdns.org` | Grafana dashboards (incl. **Bookstore API** auto-loaded from ConfigMap) | `admin` + Grafana password (printed by Prometheus install) |
| `https://prometheus.asterzheku.duckdns.org` | Prometheus UI | basic-auth (printed by Prometheus install) |
| `https://kibana.asterzheku.duckdns.org` | Kibana — Discover → filter `kubernetes.namespace:bookstore` | basic-auth (printed by Kibana install) |

## Verify metrics + logs land

After all 4 installs done + bookstore traffic generated:

```bash
# Trigger some bookstore requests to generate metrics + logs
for i in 1 2 3 4 5; do
  curl -k https://bookstore.asterzheku.duckdns.org/books > /dev/null
  curl -k https://bookstore.asterzheku.duckdns.org/health > /dev/null
done
```

Then:
- **Grafana → Dashboards → Bookstore API** — request rate panel should show non-zero traffic
- **Kibana → Discover → filter `kubernetes.namespace : "bookstore"`** — recent log lines visible

## Skepticism

- **ES single-node + persistence disabled** — data lost on pod restart. Acceptable for demo. Production: 3-node cluster + persistent volumes via PVC.
- **kube-prometheus-stack default ServiceMonitor selectors are tight** — bookstore chart adds `release: prometheus` label so its ServiceMonitor IS picked up; if you rename the helm release, update the selector.
- **Filebeat collects from EVERY pod**, including kube-system. Lots of log volume in ES — fine for short-lived demo.
- **No Alertmanager receiver** — `'null'` swallows alerts. Wire Slack/email in `prometheus/values.yaml` if you actually want notifications.
- **No log retention policy** — ES will keep filling up. Add an Index Lifecycle Management (ILM) policy for prod.

## Next phase →

None — Phase 8 is the last. After this, every original spec requirement is met:

| Spec | Phase | Done |
|------|-------|------|
| 1. Terraform 3 VMs | 1 | ✅ |
| 2. Ansible kubeadm cluster | 1 | ✅ |
| 3. NGINX Ingress + cert-manager + LE + DNS | 3+4 | ✅ |
| 4. Jenkins (Helm + ephemeral agents) | 5 | ✅ |
| 5. Python FastAPI bookstore | 6 | ✅ |
| 6. Containerize | 6 | ✅ |
| 7. Jenkinsfile CI/CD pipeline | 7 | ✅ |
| 8. Prometheus/Grafana + ELK | 8 | ✅ |

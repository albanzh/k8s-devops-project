# Monitoring (Phase 8) — Prometheus + Grafana + ELK

Collects metrics + logs from the bookstore API. Each component is in its own folder with a `values.yaml` + `README.md`.

## Install order

1. **prometheus/** — kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter)
2. **elasticsearch/** — single-node ES for the demo
3. **kibana/** — UI for ELK
4. **filebeat/** — DaemonSet that ships pod logs to Elasticsearch

Each takes 5–10 min. Total: ~30 min.

## Resource warning

These four components together use **~5 Gi RAM + ~2.5 cores**. With 3 × D4s_v3 nodes (~48 Gi total), you have headroom but don't run the bookstore at high replica count alongside.

| Component | Memory | CPU |
|-----------|--------|-----|
| Prometheus | 1–2 Gi | 0.5 |
| Grafana | 256 Mi | 0.1 |
| Alertmanager | 128 Mi | 0.05 |
| node-exporter (DS) | 50 Mi × 3 | 0.05 × 3 |
| kube-state-metrics | 100 Mi | 0.1 |
| Elasticsearch | 2 Gi | 1.0 |
| Kibana | 512 Mi | 0.2 |
| Filebeat (DS) | 100 Mi × 3 | 0.1 × 3 |

## What you'll see end of Phase 8

| URL | What |
|-----|------|
| `https://grafana.aster123.duckdns.org` | Grafana dashboards (incl. **Bookstore API** dashboard auto-loaded) |
| `https://prometheus.aster123.duckdns.org` | Prometheus UI (basic auth) |
| `https://kibana.aster123.duckdns.org` | Kibana (basic auth) — Discover → filter `kubernetes.namespace:bookstore` |

## Skepticism

- **ES single-node + persistence disabled** = data lost on pod restart. Acceptable for demo. Production: 3-node cluster + persistent volumes.
- **Helm chart's default scrape selectors are tight** — ServiceMonitor needs `release: prometheus` label (already set in our bookstore chart).
- **Filebeat collects from EVERY pod**, including kube-system. Lots of log volume — acceptable for short-lived demo.

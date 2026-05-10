# Kubernetes workloads

Each subfolder = one Helm release (or a small set of related manifests). Edit `values.yaml`, run the install commands from the subfolder's README. No magic.

## Cluster context

| | |
|---|---|
| **Public entry point** | Azure Load Balancer at `52.236.143.47` (DuckDNS → here) |
| Master (SSH only) | `20.229.55.144` |
| Workers | `104.40.249.39`, `52.142.215.164` |
| Domain | `asterzheku.duckdns.org` (wildcard — `jenkins.`, `bookstore.`, etc. all resolve to LB IP) |
| K8s | 1.28.2, Calico CNI (VXLAN+1380), NGINX Ingress as DaemonSet |

## Install order (dependencies)

```
1. infrastructure/    (terraform apply)         → cluster + LB + NGINX exist
2. ingress-nginx/     (Helm)                    → replace ansible install with Helm-managed DaemonSet
3. cert-manager/      (Helm + ClusterIssuers)   → TLS automation
4. (storage)          local-path-provisioner    → default StorageClass for Jenkins/Prometheus PVCs
5. jenkins/           (Helm with JCasC)         → CI/CD with ephemeral agents
6. bookstore-api/     (built by Jenkins)        → the FastAPI app + its Helm chart
7. monitoring/        (4 Helm releases)         → Prometheus + Grafana + ELK
```

**Don't install N+1 until N is healthy.** Use [`../infrastructure/command.md`](../infrastructure/command.md) for cluster-wide diagnostics, and each component's own README for that component's checks.

## Conventions

- All `values.yaml` files are checked into git (no secrets — those go to K8s Secrets at install time)
- Each README has the same shape: **Context → Architecture → Pre-requisites → Numbered Install Steps → Verify → Upgrade → Rollback → Common failures → Skepticism**
- Helm release names match folder names: `ingress-nginx`, `cert-manager`, `jenkins`, `bookstore`, `prometheus`, `elasticsearch`, `kibana`, `filebeat`

## Quick reference

| Component | Namespace | Helm release | Chart | Phase |
|-----------|-----------|--------------|-------|-------|
| ingress-nginx | `ingress-nginx` | `ingress-nginx` | `ingress-nginx/ingress-nginx` (4.7.1) | 3 |
| cert-manager | `cert-manager` | `cert-manager` | `jetstack/cert-manager` (v1.14.0) | 4 |
| jenkins | `jenkins` | `jenkins` | `jenkins/jenkins` | 5 |
| bookstore-api | `bookstore` | `bookstore` | `./helm/bookstore` (local chart) | 6+7 |
| prometheus stack | `monitoring` | `prometheus` | `prometheus-community/kube-prometheus-stack` | 8 |
| elasticsearch | `logging` | `elasticsearch` | `elastic/elasticsearch` | 8 |
| kibana | `logging` | `kibana` | `elastic/kibana` | 8 |
| filebeat | `logging` | `filebeat` | `elastic/filebeat` | 8 |

## At a glance — endpoints after Phase 8

| URL | What | Auth |
|-----|------|------|
| `https://bookstore.asterzheku.duckdns.org/books` | Bookstore API (Phase 7) | none |
| `https://bookstore.asterzheku.duckdns.org/docs` | Swagger UI | none |
| `https://jenkins.asterzheku.duckdns.org` | Jenkins UI (Phase 5) | admin + saved password |
| `https://grafana.asterzheku.duckdns.org` | Grafana dashboards (Phase 8) | admin + Grafana password |
| `https://prometheus.asterzheku.duckdns.org` | Prometheus UI (Phase 8) | basic-auth |
| `https://kibana.asterzheku.duckdns.org` | Kibana — log search (Phase 8) | basic-auth |

# Phase 1 — Infrastructure (Terraform + Ansible)

This folder owns **Azure VMs + cluster bootstrap**. After `terraform apply`, the cluster is fully running with K8s 1.28.2 + Calico CNI + base NGINX Ingress.

For **everything that comes after** (Jenkins, the bookstore app, observability), see [../kubernetes/](../kubernetes/).

---

## Current state (replace IPs after re-applying)

| | |
|---|---|
| **LB public IP** (DuckDNS → here) | **`52.236.143.47`** ← Azure Load Balancer |
| Master (SSH only) | `20.229.55.144` |
| Worker-1 | `104.40.249.39` |
| Worker-2 | `52.142.215.164` |
| SSH key | `~/ssh_key.pem` |
| Cluster | K8s 1.28.2, Calico v3.26 (VXLAN+1380), NGINX Ingress v1.8.1 |
| Public ingress entry | Azure Standard LB → all 3 nodes (HA, TCP probe on :80) |

Get fresh values anytime:
```bash
cd /mnt/c/Users/user/Desktop/kube/k8s-devops-project/infrastructure
terraform output
```

---

## What this folder does

```
infrastructure/
├── main.tf                  ← VMs, NSG, Public IPs, NICs, Load Balancer, Ansible trigger
├── providers.tf             ← terraform 1.0+, azurerm 3.x, tls, local, null
├── variables.tf             ← subscription_id, username, letsencrypt_email, admin_source_cidr
├── outputs.tf               ← lb_public_ip, master_public_ip, ssh_command_master, summary
├── terraform.tfvars         ← YOUR values (gitignored)
├── command.md               ← cluster diagnostic commands (run these anytime)
└── ansible/
    ├── site.yml             ← 4 plays: common → master → worker → ingress
    ├── inventory.tpl        ← rendered to inventory.ini at apply time
    └── roles/               ← common, containerd, kubernetes, k8s_master,
                                k8s_worker, nginx_ingress
```

Module dependencies in [`../modules/resources/azure/`](../modules/resources/azure/):
`ssh-key`, `data-resource-group`, `data-subnet`, `public-ip`, `nsg`, `network-interface`, `linux-server`, `load-balancer`.

---

## Deploy / re-deploy

```bash
cd /mnt/c/Users/user/Desktop/kube/k8s-devops-project/infrastructure
terraform init
terraform plan -out tf.plan
terraform apply tf.plan
```

Takes 8–12 min. Outputs print the master IP + ready-to-paste SSH command.

## Destroy

```bash
terraform destroy -auto-approve
```

Removes all VMs/NICs/Public IPs (~3 min). The pre-existing RG/VNet/Subnet stay.

## Verify cluster health
 Verify cluster health (1 min)                                                                      ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get nodes -o wide && echo "---" && kubectl get pods -A'


```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get nodes && kubectl get pods -A | grep -vE "Running|Completed"'
```

For a deeper sweep, see [command.md](command.md).

---

# Next steps — proceed in this order

Each phase has its own README with exact install commands, verification steps, and skepticism. Don't skip ahead until the previous one verifies.

| # | Phase | Where the instructions live | What it does |
|---|-------|----------------------------|--------------|
| 1 | **Infrastructure** (this folder) | you're here | Azure infra + K8s + base ingress |
| 2 | **DNS (DuckDNS)** | manual — see below | Free hostname → master IP |
| 3 | **Ingress (Helm)** | [../kubernetes/ingress-nginx/](../kubernetes/ingress-nginx/) | Replace ansible-installed manifest with Helm-managed DaemonSet (3 nodes serve ingress) |
| 4 | **TLS (cert-manager)** | [../kubernetes/cert-manager/](../kubernetes/cert-manager/) | Auto-issue Let's Encrypt certs |
| 5 | **Jenkins** | [../kubernetes/jenkins/](../kubernetes/jenkins/) | CI/CD with JCasC + ephemeral K8s agents |
| 6 | **Bookstore API** | [../kubernetes/bookstore-api/](../kubernetes/bookstore-api/) | FastAPI app + Dockerfile + Helm chart |
| 7 | **CI/CD pipeline** | [../kubernetes/bookstore-api/Jenkinsfile](../kubernetes/bookstore-api/Jenkinsfile) | Test → Kaniko build → Trivy scan → Helm deploy → Verify |
| 8 | **Observability** | [../kubernetes/monitoring/](../kubernetes/monitoring/) | Prometheus + Grafana + ELK + bookstore dashboard |

> ⚠️ Phase 3 first-time install requires deleting the ansible-installed manifest before `helm install` (Helm refuses to adopt resources without ownership labels). Both steps are in the [ingress-nginx README](../kubernetes/ingress-nginx/README.md) under "Migrating from the bare-metal manifest install".

## Spec mapping

The original 8-step spec maps to these 8 phases as follows:

| Spec | Phase | What's done |
|------|-------|-------------|
| 1. Terraform 3 VMs | Phase 1 | ✅ this folder |
| 2. Ansible kubeadm cluster | Phase 1 (via terraform's local-exec) | ✅ this folder's `ansible/` |
| 3. NGINX Ingress + cert-manager + LE + DNS | Phases 2+3+4 | ✅ kubernetes/{ingress-nginx,cert-manager}/, DuckDNS manual |
| 4. Jenkins via Helm + ephemeral agents | Phase 5 | ✅ kubernetes/jenkins/ — JCasC config + 2 pod templates |
| 5. Python FastAPI bookstore (4 endpoints) | Phase 6 | ✅ kubernetes/bookstore-api/app/main.py |
| 6. Containerize | Phase 6 | ✅ kubernetes/bookstore-api/app/Dockerfile |
| 7. Jenkinsfile CI/CD pipeline | Phase 7 | ✅ kubernetes/bookstore-api/Jenkinsfile + helm/bookstore/ |
| 8. Prometheus/Grafana + ELK | Phase 8 | ✅ kubernetes/monitoring/{prometheus,elasticsearch,kibana,filebeat}/ |

---

## Phase 2 — DNS (the only purely-manual step)

DuckDNS gives you a free `*.duckdns.org` subdomain pointing wherever you want.

1. https://www.duckdns.org → log in (GitHub/Google)
2. Add a subdomain — e.g. `asterzheku`
3. Set **current ip** to the **LB public IP** from `terraform output -raw lb_public_ip` → click **update ip**

> ⚠️ **Point at the LB IP, NOT the master IP.** The LB has a stable public IP and gives you HA — any healthy node serves traffic. Master IP works too but you lose HA + the master IP rotates on every redeploy.

Verify from WSL:
```bash
DOMAIN="asterzheku.duckdns.org"
nslookup $DOMAIN              # should return the LB IP (52.236.143.47)
curl -I http://$DOMAIN        # should return: HTTP/1.1 404 Not Found, Server: nginx
```

DuckDNS gives you the **wildcard** for free: `jenkins.asterzheku.duckdns.org`, `bookstore.asterzheku.duckdns.org`, `grafana.asterzheku.duckdns.org`, etc. all resolve to the LB IP automatically. No extra config needed for sub-hosts.

After step 3, you have a stable hostname. Proceed to Phase 3.

---

## Phases 3-8 — install order

```bash
# ─── Phase 3: ingress-nginx (Helm) ──────────────────────────────────
cd ../kubernetes/ingress-nginx/
# Follow README.md — includes the manifest cleanup step

# ─── Phase 4: cert-manager + LE issuers ─────────────────────────────
cd ../cert-manager/
# Follow README.md — includes a smoke test (issue a real cert)

# ─── Phase 5: Jenkins (depends on 3 + 4) ────────────────────────────
cd ../jenkins/
# 1. Edit values.yaml — set ingress hostName + tls.hosts to your DuckDNS subdomain
# 2. Follow README.md — admin password printed at end of install
# 3. In Jenkins UI, add `dockerhub-creds` credential (for Phase 7 build)

# ─── Phases 6+7: Bookstore code + CI/CD pipeline ────────────────────
cd ../bookstore-api/
# Phase 6 — what's already in this folder:
#   app/main.py + Dockerfile + tests   (Phases 5+6 of the spec: code + container)
#   helm/bookstore/                    (Phase 7.1 of the spec: deploy via Helm)
#   Jenkinsfile                        (Phase 7 of the spec: CI/CD pipeline)
#
# To run Phase 7 (CI/CD):
#   1. Edit helm/bookstore/values.yaml line 9 — set image.repository to YOUR Docker Hub username
#   2. Edit Jenkinsfile line 16 — same DEFAULT (or override at build time)
#   3. git push the project to GitHub
#   4. Jenkins UI → New Item → Pipeline → Pipeline script from SCM:
#        Repo: <your-github-url>
#        Script Path: kubernetes/bookstore-api/Jenkinsfile
#   5. Build with Parameters:
#        IMAGE_REPO     = docker.io/<your_user>/bookstore
#        APP_HOST       = bookstore.asterzheku.duckdns.org
#        NAMESPACE      = bookstore
#        CLUSTER_ISSUER = letsencrypt-staging  (flip to prod after first success)
#   6. Verify: curl -k https://bookstore.asterzheku.duckdns.org/books

# ─── Phase 8: Observability (Prometheus/Grafana + ELK) ──────────────
cd ../monitoring/
# Install in this order (each ~5-10 min):
cd prometheus/      # → READ + run README.md
cd ../elasticsearch/  # → READ + run README.md
cd ../kibana/         # → READ + run README.md
cd ../filebeat/       # → READ + run README.md
# After all 4 are up:
#   • https://grafana.asterzheku.duckdns.org → Bookstore API dashboard
#   • https://kibana.asterzheku.duckdns.org  → Discover → filter kubernetes.namespace:bookstore
```

Each subfolder has its own:
- **values.yaml** — the source of truth, edit before installing
- **README.md** — install / verify / upgrade / rollback / skepticism

---

## Common diagnostics (any phase)

See [command.md](command.md) — full health-sweep SSH block + per-component drill-downs.

Quick "is it alive?" one-liner:
```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get nodes && echo "---" && kubectl get pods -A | grep -vE "Running|Completed"'
```

If the second part returns just the header, **everything is healthy**.

---

## When IPs change (after destroy + apply)

Four IPs can change across `terraform destroy` + `terraform apply`:
- **LB public IP** — `52.236.143.47` (rotates on full destroy; otherwise stable)
- Master public IP — `20.229.55.144`
- Worker-1 — `104.40.249.39`
- Worker-2 — `52.142.215.164`

Get new values:
```bash
cd /mnt/c/Users/user/Desktop/kube/k8s-devops-project/infrastructure
terraform output
```

Then:
1. **Update DuckDNS** to point at the new `lb_public_ip` (browser, ~10 sec)
2. **Find/replace IPs** across `.md`, `.yaml`, `Jenkinsfile`:
```bash
cd /mnt/c/Users/user/Desktop/kube/k8s-devops-project
find . -type f \( -name "*.md" -o -name "*.yaml" -o -name "Jenkinsfile" \) -exec sed -i \
  -e 's/52\.236\.137\.184/<NEW_LB_IP>/g' \
  -e 's/51\.124\.110\.230/<NEW_MASTER_IP>/g' \
  -e 's/20\.93\.153\.178/<NEW_WORKER1_IP>/g' \
  -e 's/20\.71\.107\.113/<NEW_WORKER2_IP>/g' \
  {} \;
```
3. **Push the updates to GitHub** so Jenkins picks them up:
```bash
git commit -am "Update IPs after redeploy"
git push
```

# Jenkins (with JCasC + ephemeral K8s agents)

Jenkins controller installed via Helm. Pipeline agents are ephemeral pods that spin up on demand and are deleted after each job.

## Architecture

```
Jenkins controller (StatefulSet, 1 replica, persistent volume 10 Gi)
    │
    │ K8s plugin (configured via JCasC)
    │
    ▼
Pod templates:
  • jenkins-agent  — lightweight default (jnlp only)
  • build          — full CI toolchain (jnlp + kaniko + trivy + helm + kubectl + python)
```

When a `Pipeline` runs `agent { label 'build' }`, Jenkins creates a Pod with all 6 containers, runs the stages inside the matching containers, then **deletes the pod** (`podRetention: Never`).

---

## Order of operations (do these in sequence)

| # | Step | Why it must come first |
|---|------|------------------------|
| 0 | (Optional) Clean up any stuck Helm release | If a previous install errored, Helm leaves a `pending-install` lock |
| 1 | Install **cert-manager** + ClusterIssuers | Jenkins ingress requests a TLS cert; needs a working issuer |
| 2 | Install **local-path-provisioner** (default StorageClass) | Jenkins needs a 10 Gi PVC; PVC stays Pending without a default class |
| 3 | Create namespace + **admin credentials Secret** | values.yaml uses `existingSecret`; chart fails to start if missing |
| 4 | Push values.yaml to master | Helm reads it from `/tmp/jenkins-values.yaml` |
| 5 | `helm install jenkins` | The actual install |
| 6 | Verify (pods, ingress, cert) | Make sure cert provisioned and pod is Ready |
| 7 | Add `dockerhub-creds` in Jenkins UI | Needed for Phase 7 (bookstore CI/CD) |

---

## Step 0 — Clean up if a previous install got stuck

Skip if you've never tried installing Jenkins. If you saw `Error: UPGRADE FAILED: another operation in progress`, run this first:

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
echo "=== Current state ==="
helm history jenkins -n jenkins 2>/dev/null
kubectl get all -n jenkins 2>/dev/null

echo ""
echo "=== Cleaning up ==="
helm uninstall jenkins -n jenkins 2>/dev/null || true
kubectl delete namespace jenkins --ignore-not-found --timeout=60s
sleep 5

echo "=== After cleanup ==="
helm list -A
EOF
```

`helm list -A` should NOT show a `jenkins` row.

---

## Step 1 — Install cert-manager + ClusterIssuers

```bash
# Push values + cluster-issuers from your laptop
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/cert-manager/values.yaml \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/cert-manager/cluster-issuers.yaml \
  azureuser@20.229.55.144:/tmp/

# Install on master
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.14.0 \
  -f /tmp/values.yaml \
  --wait --timeout 5m

kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s
until kubectl get endpoints cert-manager-webhook -n cert-manager -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -q .; do
  echo "waiting for webhook endpoints..."; sleep 5
done

kubectl apply -f /tmp/cluster-issuers.yaml

echo ""
echo "=== ClusterIssuers (both should be READY=True) ==="
kubectl get clusterissuer
EOF
```

✅ **Don't proceed until both issuers say `READY=True`.**

---

## Step 2 — Install local-path-provisioner (default StorageClass)

> **What is local-path-provisioner?** A simple K8s storage driver that creates persistent volumes from local directories on the host node:
> ```
> PVC request
>    ↓
> local-path provisioner
>    ↓
> creates a directory on the node where the consuming pod schedules
>    ↓
> PVC becomes Bound
> ```
> Limitation: a PV is tied to the node where it was created. If that node dies, the data is gone. Fine for a learning cluster; production = use a CSI driver backed by Azure Managed Disks.

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl -n local-path-storage rollout status deployment/local-path-provisioner --timeout=120s

echo ""
echo "=== StorageClasses (local-path should say (default)) ==="
kubectl get storageclass
EOF
```

✅ Expected: row showing `local-path (default) ... rancher.io/local-path`.

Already installed on a previous run? `kubectl get storageclass` already shows the row → skip this step.

---

## Step 3 — Create the Jenkins namespace + admin credentials Secret

The chart's values.yaml has `controller.admin.existingSecret: jenkins-admin-credentials`. Create that Secret BEFORE installing — otherwise Jenkins startup fails.

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)
kubectl -n jenkins create secret generic jenkins-admin-credentials \
  --from-literal=jenkins-admin-user=admin \
  --from-literal=jenkins-admin-password="$PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "════════════════════════════════════════════"
echo "Jenkins admin password (SAVE THIS NOW):"
echo "$PASS"
echo "════════════════════════════════════════════"
EOF
```

⚠️ **Copy the password.** You can also retrieve it later via:
```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  "kubectl -n jenkins get secret jenkins-admin-credentials -o jsonpath='{.data.jenkins-admin-password}' | base64 -d ; echo"
```

---

## Step 4 — Push values.yaml to master

Before pushing, confirm `controller.ingress.hostName` and `controller.ingress.tls[0].hosts[0]` in `values.yaml` match your DuckDNS:

```yaml
controller:
  ingress:
    hostName: "jenkins.asterzheku.duckdns.org"
    tls:
      - secretName: jenkins-tls
        hosts: ["jenkins.asterzheku.duckdns.org"]
```

Push it:
```bash
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/jenkins/values.yaml \
  azureuser@20.229.55.144:/tmp/jenkins-values.yaml
```

---

## Step 5 — Install Jenkins via Helm

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm repo add jenkins https://charts.jenkins.io --force-update
helm repo update

helm upgrade --install jenkins jenkins/jenkins \
  -n jenkins \
  -f /tmp/jenkins-values.yaml \
  --wait --timeout 15m
EOF
```

Takes 5–10 min on first run (pulls controller image + resolves ~80 plugins).

---

## Step 6 — Verify

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
echo "=== Pods ==="
kubectl get pods -n jenkins

echo ""
echo "=== Ingress + cert ==="
kubectl get ingress,certificate -n jenkins
EOF
```

Expected:
```
=== Pods ===
NAME        READY   STATUS    RESTARTS   AGE
jenkins-0   2/2     Running   0          5m

=== Ingress + cert ===
NAME                                CLASS   HOSTS                          ADDRESS
ingress.networking.k8s.io/jenkins   nginx   jenkins.asterzheku.duckdns.org ...

NAME                                       READY   SECRET        AGE
certificate.cert-manager.io/jenkins-tls    True    jenkins-tls   5m
```

Browser: `https://jenkins.asterzheku.duckdns.org` — accept the staging-cert warning, log in with `admin` + the saved password.

In the Jenkins UI: **Manage Jenkins → Clouds** — confirm there's one cloud named `kubernetes` (auto-configured by JCasC).

---

## Step 7 — Add Docker Hub credential (for the bookstore pipeline later)

This stays manual — secrets shouldn't be in values.yaml.

1. Create a Docker Hub access token at https://hub.docker.com → Account Settings → Personal access tokens → **Read & Write**
2. Jenkins → **Manage Jenkins → Credentials → System → Global → + Add Credentials**:
   - Kind: `Username with password`
   - Username: your Docker Hub username
   - Password: the access token (NOT your account password)
   - **ID**: `dockerhub-creds` ← exact string, the Jenkinsfile expects this

---

## Test the ephemeral agent (quick sanity check)

In Jenkins → **+ New Item** → Pipeline → name `agent-test`. Pipeline script:

```groovy
pipeline {
  agent { label 'build' }
  stages {
    stage('show containers') {
      steps {
        container('python')   { sh 'python --version' }
        container('helm')     { sh 'helm version --short' }
        container('kubectl')  { sh 'kubectl version --client | head -1' }
        container('trivy')    { sh 'trivy --version | head -1' }
        container('kaniko')   { sh '/kaniko/executor version || true' }
      }
    }
  }
}
```

Save → **Build Now**. In another shell:
```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get pods -n jenkins -w'
# A build-agent-* pod appears, runs ~30 sec, then disappears.
```

The build console should print all 5 tool versions and finish SUCCESS.

---

## Upgrade

Edit `values.yaml`, push it again, then:
```bash
helm upgrade jenkins jenkins/jenkins -n jenkins -f /tmp/jenkins-values.yaml --wait
```

## Rollback

```bash
helm rollback jenkins -n jenkins
```

## Common failures + fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Error: UPGRADE FAILED: another operation in progress` | Stuck `pending-install` from a previous attempt | run Step 0 (cleanup), then retry from Step 5 |
| Pod `Init:CrashLoopBackOff` with plugin compatibility error | Plugin requires newer Jenkins than the pinned controller image | values.yaml uses `tag: lts-jdk17` (rolling) — `helm upgrade` pulls latest |
| Pod stuck `Pending` | No default StorageClass | run Step 2 (local-path-provisioner) |
| Ingress works but `certificate jenkins-tls` stays Pending | DNS doesn't resolve `jenkins.<your>.duckdns.org` | `nslookup jenkins.asterzheku.duckdns.org` — should return the LB IP |
| `helm install` 504 timeout | Controller image download slow on first run | bump `--timeout 20m`; usually completes second time |
| `agent { label 'build' }` waits forever | `kubernetes` cloud not configured | `kubectl -n jenkins get cm jenkins-jenkins-jcasc-config -o yaml` — check JCasC config |
| Kaniko fails with "401 unauthorized" | `dockerhub-creds` missing or wrong ID | recreate the credential with ID `dockerhub-creds` exactly |

## Why ephemeral agents matter

| | Permanent agents | Ephemeral pods (this) |
|--|------------------|------------------------|
| Idle cost | Constant CPU/memory | Zero |
| Build isolation | Shared FS, package contamination | Fresh pod per build |
| Scale | Pre-provisioned | Auto-spawns up to `containerCapStr: 10` |
| Caching | Easy (persistent) | Harder (each pod fresh) |

For most projects, ephemeral wins on cost + isolation. Caching pain is solved with image-layer caching (Kaniko `--cache=true`) and Docker registry-side caching.

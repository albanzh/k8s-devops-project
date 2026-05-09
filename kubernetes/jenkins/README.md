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

## Pre-requisites

1. Cluster running, ingress healthy, cert-manager installed (Phases 1+2 done).
2. **Default StorageClass** must exist — Jenkins persistent volume needs it.

   ```bash
   ssh -i ~/ssh_key.pem azureuser@51.136.90.206 'kubectl get storageclass'
   # Expect: local-path (default) ...
   ```

   If empty, install local-path-provisioner first:
   ```bash
   ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
   kubectl patch storageclass local-path \
     -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   EOF
   ```

3. **DuckDNS** subdomain pointing at master IP (so `jenkins.<your>.duckdns.org` resolves).

## Install

### 1. Edit values.yaml — replace the hostname

```yaml
controller:
  ingress:
    hostName: "aster123.duckdns.org"   # ← your domain
    tls:
      - secretName: jenkins-tls
        hosts: ["aster123.duckdns.org"]   # ← same domain
```

### 2. Push values.yaml to master

```bash
scp -i ~/ssh_key.pem values.yaml azureuser@51.136.90.206:/tmp/jenkins-values.yaml
```

### 3. Create namespace + admin credentials Secret

The chart references `jenkins-admin-credentials` via `existingSecret`. Create it first so the Helm install can find it.

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)
kubectl -n jenkins create secret generic jenkins-admin-credentials \
  --from-literal=jenkins-admin-user=admin \
  --from-literal=jenkins-admin-password="$PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== Jenkins admin password (save this!) ==="
echo "$PASS"
EOF
```

### 4. Install via Helm

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
helm repo add jenkins https://charts.jenkins.io --force-update
helm repo update

helm upgrade --install jenkins jenkins/jenkins \
  -n jenkins \
  -f /tmp/jenkins-values.yaml \
  --wait --timeout 15m
EOF
```

Takes 5–10 min the first time (downloads controller image + resolves plugins).

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
echo "=== Pods ==="
kubectl get pods -n jenkins

echo ""
echo "=== Ingress + cert ==="
kubectl get ingress,certificate -n jenkins

echo ""
echo "=== Get admin password ==="
kubectl -n jenkins get secret jenkins-admin-credentials \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d ; echo
EOF
```

Open `https://jenkins.<your>.duckdns.org` in browser. Accept staging-cert warning. Log in with `admin` + the printed password.

You should see the Jenkins home page. Go to **Manage Jenkins** → **Clouds** → there should be a `kubernetes` cloud listed (configured via JCasC).

## Add Docker Hub credential (for the bookstore pipeline later)

This stays manual — secrets shouldn't be in values.yaml.

1. Create a Docker Hub access token at https://hub.docker.com → Account Settings → Security
2. In Jenkins: **Manage Jenkins** → **Credentials** → **(global)** → **Add Credentials**
   - Kind: `Username with password`
   - Username: your Docker Hub username
   - Password: the access token
   - **ID**: `dockerhub-creds`  ← exact string, the Jenkinsfile expects this

## Test the ephemeral agent

In Jenkins → New Item → Pipeline → name `agent-test`. Pipeline script:

```groovy
pipeline {
  agent { label 'build' }
  stages {
    stage('show containers') {
      steps {
        container('python')   { sh 'python --version' }
        container('helm')     { sh 'helm version --short' }
        container('kubectl')  { sh 'kubectl version --client --short' }
        container('trivy')    { sh 'trivy --version' }
        container('kaniko')   { sh '/kaniko/executor version || true' }
      }
    }
  }
}
```

Hit **Build Now**. In the K8s cluster:
```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 'kubectl get pods -n jenkins -w'
# You'll see a build-agent-* pod appear, run, then disappear.
```

Logs in the Jenkins UI should show all five tool versions, then the pod terminates.

## Upgrade

Edit `values.yaml`, then:
```bash
helm upgrade jenkins jenkins/jenkins -n jenkins -f /tmp/jenkins-values.yaml --wait
```

## Rollback

```bash
helm rollback jenkins -n jenkins
```

## Skepticism / common failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod `Init:CrashLoopBackOff` | plugin dependency conflict | use `installLatestPlugins: true` (already set) |
| Pod stuck `Pending` | no default StorageClass | install local-path-provisioner (see Pre-requisites) |
| Ingress works but cert stays Pending | DNS not yet pointing at the master | `nslookup jenkins.<your>.duckdns.org` |
| `helm install` 504 timeout | controller image download slow | bump `--timeout 20m`; usually completes after image cache warm |
| `agent { label 'build' }` waits forever | `kubernetes` cloud not configured | check JCasC config: `kubectl -n jenkins get cm jenkins-jenkins-jcasc-config -o yaml` |
| Kaniko fails with "401 unauthorized" | dockerhub-creds missing or wrong ID | re-create the credential with ID `dockerhub-creds` exactly |

## Why ephemeral agents matter

| | Permanent agents | Ephemeral pods (this) |
|--|------------------|------------------------|
| Idle cost | Constant CPU/memory | Zero |
| Build isolation | Shared FS, package contamination | Fresh pod per build |
| Scale | Pre-provisioned | Auto-spawns up to `containerCapStr: 10` |
| Caching | Easy (persistent) | Harder (each pod fresh) |

For most projects, ephemeral wins on cost + isolation. Caching pain is solved with image-layer caching (Kaniko `--cache=true`) and Docker registry-side caching.

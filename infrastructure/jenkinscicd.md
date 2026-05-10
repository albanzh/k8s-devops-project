Pre-check (1 min)
Confirm what's already done:


# 1. Cluster healthy?
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get nodes && kubectl get pods -A | grep -vE "Running|Completed"'
# Expect: 3 nodes Ready, no problematic pods listed

# 2. Jenkins reachable?
curl -kI https://jenkins.asterzheku.duckdns.org
# Expect: HTTP/2 403 (Jenkins login page — works)

# 3. cert-manager ready?
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get clusterissuer'
# Expect: letsencrypt-staging + letsencrypt-prod, both READY=True
If any check fails, fix it before proceeding.

Step 1 — Set your Docker Hub username in values + Jenkinsfile (1 min)
Looking at your earlier file diffs, your username is aster2022. If different, change DOCKER_USER below.


cd /mnt/c/Users/user/Desktop/kube/k8s-devops-project

DOCKER_USER="aster2022"

# Replace placeholder in both files
sed -i "s|YOUR_DOCKERHUB_USER|$DOCKER_USER|g" \
  kubernetes/bookstore-api/helm/bookstore/values.yaml \
  kubernetes/bookstore-api/Jenkinsfile

# Verify
grep -n "$DOCKER_USER" \
  kubernetes/bookstore-api/helm/bookstore/values.yaml \
  kubernetes/bookstore-api/Jenkinsfile
Should print 2 lines (one from each file).

Step 2 — Generate Docker Hub access token (2 min)
Go to https://hub.docker.com → login as aster2022
Top right avatar → Account Settings → Personal access tokens → Generate new token
Description: jenkins-ci
Expiration: 90 days
Access permissions: ✅ Read & Write
Generate → copy the token immediately (starts with dckr_pat_...)
Paste into a notepad — needed in Step 4
Step 3 — Push project to GitHub (3 min)
3a. Create a Personal Access Token for git push
(Your earlier push failed because GitHub deprecated password auth.)

https://github.com/settings/tokens → Generate new token (classic)
Note: wsl-laptop
Expiration: 90 days
Scopes: ✅ repo
Generate → copy the token (starts with ghp_...)
3b. Push

cd /mnt/c/Users/user/Desktop/kube/k8s-devops-project

# Confirm sensitive files are gitignored
cat .gitignore | grep -E "tfvars|tfstate|pem" || echo "⚠️ MISSING — add them"

# Cache token for 24h (no need to retype every push)
git config --global credential.helper "cache --timeout=86400"

# Confirm remote
git remote -v

# Stage + commit + push
git add .
git commit -m "Phase 7: Helm chart + Jenkinsfile + Docker Hub username"
git push -u origin main
# When prompted:
#   Username: albanzh   (your GitHub username)
#   Password: <paste the ghp_... token>
Expected end:


Branch 'main' set up to track 'origin/main'.
Verify in browser: https://github.com/albanzh/k8s-devops-project should show the files.

Step 4 — Add dockerhub-creds in Jenkins UI (2 min)
Open https://jenkins.asterzheku.duckdns.org → login (admin / lwiASobQGShnn5JVSO17ijf or whatever your current password is)
Manage Jenkins (left sidebar) → Credentials
Under Stores scoped to Jenkins → click System
Click Global credentials (unrestricted)
Top right → + Add Credentials
Fill in:
Field	Value
Kind	Username with password
Scope	Global
Username	aster2022
Password	the dckr_pat_... Docker Hub token from Step 2
ID	dockerhub-creds ← EXACT lowercase, with hyphen
Description	Docker Hub push token
Click Create
Verify: row showing dockerhub-creds with type Username with password.

Step 5 — Create the bookstore pipeline (1 min)
Jenkins home → + New Item
Name: bookstore → Pipeline → OK
Scroll down to Pipeline section:
Definition: Pipeline script from SCM
SCM: Git
Repository URL: https://github.com/albanzh/k8s-devops-project.git
(No credentials needed for public repo. If private: add another username/password credential and select it here.)
Branch Specifier: */main
Script Path: kubernetes/bookstore-api/Jenkinsfile
Scroll to bottom → Save
You'll land on the bookstore job page. Don't click Build Now — the params haven't been registered yet (this is normal for Pipeline-from-SCM jobs on first save). Trigger one build to register them, then a second build with proper params.

Step 6 — First build (registers parameters)
Click Build Now (without parameters — Jenkins reads the Jenkinsfile to learn what params exist)
Wait ~30 sec — it'll likely fail with "no IMAGE_REPO" or similar. That's expected.
Refresh the page — you'll now see Build with Parameters in the left sidebar.
Step 7 — Real first build with parameters (~7-10 min)
Build with Parameters (left sidebar)
Override:
Parameter	Value
IMAGE_REPO	docker.io/aster2022/bookstore
APP_HOST	bookstore.asterzheku.duckdns.org
NAMESPACE	bookstore
CLUSTER_ISSUER	letsencrypt-staging ← FIRST TIME ALWAYS STAGING
FAIL_ON_HIGH_CVE	true
Click Build
Click into the running build → Console Output
In a separate WSL terminal, watch what's happening:


ssh -i ~/ssh_key.pem azureuser@20.229.55.144 'kubectl get pods --all-namespaces -w'
You'll see:

build-agent-xxxxx pod spawn in jenkins namespace (~10 sec)
It runs through 7 stages: Checkout → Test → Build → Scan → Resolve → Deploy → Verify
During Deploy stage: a bookstore-bookstore-xxxxx pod appears in bookstore namespace
Build agent terminates after success
Step 8 — Verify the bookstore is live (1 min)

# K8s state
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'kubectl get pods,svc,ingress,certificate,hpa,pdb -n bookstore'

# From your laptop
curl -k https://bookstore.asterzheku.duckdns.org/books
curl -k https://bookstore.asterzheku.duckdns.org/health

# Browser
# https://bookstore.asterzheku.duckdns.org/docs   ← Swagger UI
Expected: JSON list of 3 seed books, {"status":"ok"}, and an interactive Swagger page.

Step 9 — (optional) Flip to letsencrypt-prod
After staging works, re-run Build with Parameters → set CLUSTER_ISSUER = letsencrypt-prod. Browser padlock turns green (real CA).

Where it'll likely fail (and the one-line fix)
Stage	Symptom	Fix
Test	pytest: command not found	wrong dir — should be kubernetes/bookstore-api/app (already set in Jenkinsfile line 59)
Build (Kaniko)	denied: requested access to the resource is denied	wrong creds — verify dockerhub-creds ID + token has Write
Scan (Trivy)	Fails with HIGH CVE list	re-run with FAIL_ON_HIGH_CVE=false
Deploy	Error: ... already exists	kubectl delete ns bookstore then re-run
Verify	Cert stuck Pending	wait 1-2 min more; if still stuck: kubectl describe certificate -n bookstore bookstore-tls
When something fails
Paste me:

The Stage name
The last 30 lines of Console Output
I'll give you the fix. Do NOT proceed past a failed stage — fix that first.

Start with Step 1. Tell me when you reach Step 7 (first build with parameters) — that's where surprises happen.
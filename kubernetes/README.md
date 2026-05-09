# Kubernetes workloads

Each subfolder = one Helm release (or a small set of related manifests). Edit `values.yaml`, run the install command from the subfolder's README. No magic.

## Install order (dependencies)

```
1. infrastructure/      (terraform apply)         → cluster exists
2. ingress-nginx/       (Helm)                    → port 80/443 routing
3. cert-manager/        (Helm + ClusterIssuers)   → TLS automation
4. jenkins/             (Helm with JCasC)         → CI/CD
5. bookstore-api/       (built by Jenkins later)  → the app
```

Don't install N+1 until N is healthy. Use [../infrastructure/command.md](../infrastructure/command.md) to verify.

## Conventions

- All values files are checked into git (no secrets — those go to K8s Secrets at install time)
- Each README has: **Install / Upgrade / Verify / Rollback / Skepticism** sections
- Helm release names match folder names: `ingress-nginx`, `cert-manager`, `jenkins`, `bookstore`

## Quick reference

| Component | Namespace | Helm release | Chart |
|-----------|-----------|--------------|-------|
| ingress-nginx | `ingress-nginx` | `ingress-nginx` | `ingress-nginx/ingress-nginx` |
| cert-manager | `cert-manager` | `cert-manager` | `jetstack/cert-manager` |
| jenkins | `jenkins` | `jenkins` | `jenkins/jenkins` |
| bookstore-api | `bookstore` | `bookstore` | `./helm/bookstore` (local chart, Phase 6) |

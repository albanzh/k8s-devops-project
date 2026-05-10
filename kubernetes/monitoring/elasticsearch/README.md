# Elasticsearch

Single-node ES for the demo. Holds logs that Filebeat ships in.

## Context

| | |
|---|---|
| **Depends on** | none (starts the ELK chain) |
| **Installs** | Elasticsearch StatefulSet (1 replica) in namespace `logging` |
| **Next phase** | Kibana ([../kibana/](../kibana/)) |
| **No public URL** | ES is cluster-internal — Filebeat + Kibana talk to it |

## Pre-requisites

- Cluster Ready (3 nodes)
- Helm installed on master

## Step 1 — Push values.yaml

```bash
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/elasticsearch/values.yaml \
  azureuser@20.229.55.144:/tmp/es-values.yaml
```

## Step 2 — Add Helm repo + create namespace

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
helm repo add elastic https://helm.elastic.co --force-update
helm repo update
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
EOF
```

## Step 3 — Install Elasticsearch

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'helm upgrade --install elasticsearch elastic/elasticsearch \
     -n logging -f /tmp/es-values.yaml --wait --timeout 10m'
```

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'kubectl get pods,svc -n logging'
```

Expected:
- `pod/elasticsearch-master-0` Running 1/1
- `service/elasticsearch-master` ClusterIP

Test from inside the cluster:
```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'kubectl run -n logging --rm -i --restart=Never curl --image=curlimages/curl \
   -- curl -s http://elasticsearch-master:9200'
```

Should return JSON containing `"cluster_name": "elasticsearch"`. Cluster status will be `yellow` (single-node — that's expected, not an error).

## Upgrade

```bash
helm upgrade elasticsearch elastic/elasticsearch \
  -n logging -f /tmp/es-values.yaml --wait
```

## Rollback

```bash
helm rollback elasticsearch -n logging
```

## Common failures + fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod stuck Pending | Resource pressure (ES asks 2 GiB) or no PVC class | `kubectl describe pod -n logging elasticsearch-master-0` |
| Pod CrashLoopBackOff with `vm.max_map_count` error | Kernel parameter not set | values.yaml has `sysctlInitContainer.enabled: true` to fix this; verify it's not disabled |
| `curl elasticsearch-master:9200` fails | pod not ready or service routing issue | `kubectl logs -n logging elasticsearch-master-0` |

## Skepticism

- **No persistence** → data lost on every pod restart (including `helm upgrade`). Fine for "did logs arrive" testing, useless for retention.
- **No x-pack security** → anyone in the cluster can hit ES on port 9200. Fine inside an isolated cluster, NOT for production.
- **Single replica** → not HA. ES yellow status is OK for single-node.

## Next phase →

[Kibana](../kibana/README.md)

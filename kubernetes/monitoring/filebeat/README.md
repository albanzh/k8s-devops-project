# Filebeat

DaemonSet on every node — collects logs from `/var/log/containers/*.log`, parses them, ships to Elasticsearch.

## Context

| | |
|---|---|
| **Depends on** | Elasticsearch reachable at `elasticsearch-master.logging:9200` |
| **Installs** | Filebeat DaemonSet in namespace `logging` (1 pod per node) |
| **Next phase** | none — Filebeat is the last component of Phase 8 |
| **No public URL** | Reads logs locally on each node, ships them to ES |

## Pre-requisites

- Elasticsearch Running ([../elasticsearch/](../elasticsearch/) verified)
- Kibana Running ([../kibana/](../kibana/) — needed to view the logs Filebeat ships)

## Step 1 — Push values.yaml

```bash
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/filebeat/values.yaml \
  azureuser@20.229.55.144:/tmp/filebeat-values.yaml
```

## Step 2 — Install Filebeat

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'helm upgrade --install filebeat elastic/filebeat \
     -n logging -f /tmp/filebeat-values.yaml --wait --timeout 5m'
```

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 \
  'kubectl get daemonset,pods -n logging -l app=filebeat-filebeat'
```

Expected: `daemonset.apps/filebeat-filebeat` with `DESIRED=3 / READY=3` (one pod per node).

Confirm logs are flowing into ES:
```bash
ssh -i ~/ssh_key.pem azureuser@20.229.55.144 bash <<'EOF'
kubectl run -n logging --rm -i --restart=Never curl --image=curlimages/curl \
  -- curl -s 'http://elasticsearch-master:9200/_cat/indices?v'
EOF
```

You should see at least one `filebeat-*` index with `health: yellow` and a non-zero `docs.count`.

## See bookstore logs in Kibana

Open `https://kibana.asterzheku.duckdns.org` → **Discover**:
1. Create a **Data view**: name=`logs`, index pattern=`filebeat-*`, timestamp=`@timestamp`
2. Filter: `kubernetes.namespace : "bookstore"`
3. The bookstore's `log.info("book added", extra={...})` lines arrive as structured JSON — fields like `book_id`, `isbn`, `old`, `new` are searchable.

To generate some test traffic:
```bash
for i in 1 2 3 4 5; do
  curl -k https://bookstore.asterzheku.duckdns.org/books > /dev/null
done
```

## Upgrade

```bash
helm upgrade filebeat elastic/filebeat -n logging -f /tmp/filebeat-values.yaml --wait
```

## Rollback

```bash
helm rollback filebeat -n logging
```

## Common failures + fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Filebeat pods CrashLoopBackOff | ES not reachable | `kubectl logs -n logging filebeat-filebeat-xxxxx` — usually shows connection error |
| `_cat/indices` shows no `filebeat-*` index | Filebeat hasn't shipped any logs yet | wait 60 sec; if still empty, check Filebeat pod logs for permission errors on `/var/log/containers` |
| Kibana Discover shows nothing despite indices existing | Wrong Data view / wrong time range | confirm time range is "last 15 min" and `kubernetes.namespace` filter is correct |
| One pod per node missing | Taint not tolerated | values.yaml has `tolerations:` for control-plane and other taints; verify it's not been edited away |

## Skepticism

- **Tolerates all taints** — runs on master too. CPU usage on master is small (~50 mCPU per pod) but not zero.
- **No log forwarding back-pressure handling** — if ES gets slow, Filebeat buffers in memory; on OOM the pod restarts and you may lose buffered logs.
- **No log retention policy** — ES will keep filling up. Add an ILM policy (`PUT /_ilm/policy/...`) for prod.
- **Collects EVERY namespace** — kube-system pod logs included. Lots of volume; fine for demo, costly long-term.

## Next phase →

None — Phase 8 (and the project) is complete. See [`../README.md`](../README.md) for the full spec checklist.

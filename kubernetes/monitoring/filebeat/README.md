# Filebeat

DaemonSet on every node — collects logs from `/var/log/containers/*.log`, parses them, ships to Elasticsearch.

## Install

```bash
scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/filebeat/values.yaml \
  azureuser@51.136.90.206:/tmp/filebeat-values.yaml

ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'helm upgrade --install filebeat elastic/filebeat \
     -n logging -f /tmp/filebeat-values.yaml --wait --timeout 5m'
```

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'kubectl get daemonset,pods -n logging -l app=filebeat-filebeat'
```

Expected: `daemonset.apps/filebeat-filebeat` with `DESIRED=3 / READY=3` (one pod per node).

Confirm logs are flowing:
```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
kubectl run -n logging --rm -i --restart=Never curl --image=curlimages/curl \
  -- curl -s 'http://elasticsearch-master:9200/_cat/indices?v'
EOF
```

You should see `filebeat-*` indices appearing.

## See bookstore logs in Kibana

`https://kibana.aster123.duckdns.org` →
1. Discover → create Data view: `filebeat-*`, timestamp = `@timestamp`
2. Filter: `kubernetes.namespace : "bookstore"`
3. The bookstore's `log.info("book added", extra={...})` lines arrive as structured JSON — fields like `book_id`, `isbn`, `old`, `new` are searchable.

## Skepticism

- **Tolerates all taints** — runs on master too. CPU usage on master is small (~50 mCPU per pod) but not zero.
- **No log forwarding back-pressure handling** — if ES gets slow, Filebeat buffers in memory; on OOM the pod restarts and you may lose buffered logs.
- **No log retention policy** — ES will keep filling up. Add an ILM policy (`/_ilm/policy/...`) for prod.

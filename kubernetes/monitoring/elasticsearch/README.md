# Elasticsearch

Single-node ES for the demo. Holds logs that Filebeat ships in.

## Install

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 bash <<'EOF'
helm repo add elastic https://helm.elastic.co --force-update
helm repo update
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
EOF

scp -i ~/ssh_key.pem \
  /mnt/c/Users/user/Desktop/kube/k8s-devops-project/kubernetes/monitoring/elasticsearch/values.yaml \
  azureuser@51.136.90.206:/tmp/es-values.yaml

ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'helm upgrade --install elasticsearch elastic/elasticsearch \
     -n logging -f /tmp/es-values.yaml --wait --timeout 10m'
```

## Verify

```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'kubectl get pods,svc -n logging'
```

Expected:
- `pod/elasticsearch-master-0` Running 1/1
- `service/elasticsearch-master` ClusterIP

Test from inside the cluster:
```bash
ssh -i ~/ssh_key.pem azureuser@51.136.90.206 \
  'kubectl run -n logging --rm -i --restart=Never curl --image=curlimages/curl \
   -- curl -s http://elasticsearch-master:9200'
```
Should return JSON with `"cluster_name": "elasticsearch"`.

## Skepticism

- **No persistence** → data lost on every pod restart (including `helm upgrade`). Fine for "did logs arrive" testing, useless for retention.
- **No x-pack security** → anyone in the cluster can hit ES on port 9200. Fine inside an isolated cluster, NOT for prod.
- **Single replica** → not HA. ES yellow status is OK for single-node.

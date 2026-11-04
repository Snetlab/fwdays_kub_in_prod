#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "Usage: bash $0 ADMIN_KUBECONFIG CONTEXT" >&2
  exit 2
fi

lab=(kubectl --kubeconfig "$1" --context "$2")
pod=''
cleanup() {
  if [[ -n $pod ]]; then
    "${lab[@]}" -n student01 delete pod "$pod" --ignore-not-found --wait=false
  fi
}
trap cleanup EXIT

service_url() {
  local ip
  ip=$("${lab[@]}" -n monitoring get service "$1" -o 'jsonpath={.spec.clusterIP}')
  printf 'http://%s:%s' "$ip" "$2"
}
loki=$(service_url course-loki 3100)
prom=$(service_url course-monitoring-kube-pro-prometheus 9090)
alerts=$(service_url course-monitoring-kube-pro-alertmanager 9093)
grafana=$(service_url course-monitoring-grafana 80)

"${lab[@]}" -n monitoring get secret course-monitoring-grafana -o json |
  python3 -c '
import base64
import json
import sys
import urllib.request

grafana = sys.argv[1]
data = json.load(sys.stdin)["data"]
auth = base64.b64encode(base64.b64decode(data["admin-user"]) + b":" +
                        base64.b64decode(data["admin-password"])).decode()
for uid in ("course-student-node-load", "course-kyverno-rootfs-audit"):
    req = urllib.request.Request(f"{grafana}/api/dashboards/uid/{uid}",
                                 headers={"Authorization": f"Basic {auth}"})
    with urllib.request.urlopen(req, timeout=10) as response:
        assert json.load(response)["dashboard"]["uid"] == uid
    print(f"Grafana provisioned {uid}")
' "$grafana"

pod=$("${lab[@]}" create -f - -o 'jsonpath={.metadata.name}' <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  generateName: module05-audit-test-
  namespace: student01
spec:
  automountServiceAccountToken: false
  containers:
    - name: load
      image: busybox:1.37
      command: [sh, -c, "while :; do :; done"]
      resources:
        limits:
          cpu: 100m
          memory: 32Mi
      securityContext:
        readOnlyRootFilesystem: false
EOF
)
"${lab[@]}" -n student01 wait --for=condition=Ready "pod/$pod" --timeout=120s

wait_for() {
  local name=$1
  shift
  for (( attempt=1; attempt<=24; attempt++ )); do
    if "$@"; then
      printf 'Verified %s\n' "$name"
      return 0
    fi
    sleep 5
  done
  printf 'Timed out waiting for %s\n' "$name" >&2
  return 1
}

has_log() {
  curl -fsSG --max-time 10 "$loki/loki/api/v1/query_range" \
    --data-urlencode "query={job=\"kyverno-pod-audit\",workload_namespace=\"student01\"} |= \"$pod\" |= \"readOnlyRootFilesystem\"" |
    python3 -c 'import json,sys; sys.exit(not json.load(sys.stdin)["data"]["result"])'
}
has_alert() {
  curl -fsS --max-time 10 "$alerts/api/v2/alerts" |
    python3 -c 'import json,sys; sys.exit(not any(
      a["labels"].get("alertname") == "KyvernoReadOnlyRootFilesystemAuditFailed"
      and a["labels"].get("workload_namespace") == "student01"
      and a["status"]["state"] == "active" for a in json.load(sys.stdin)))'
}
has_metric() {
  curl -fsSG --max-time 10 "$prom/api/v1/query" --data-urlencode "query=$1" |
    python3 -c 'import json,sys; sys.exit(not any(
      s["metric"].get("node") and s["metric"].get("namespace") == "student01"
      and float(s["value"][1]) > 0 for s in json.load(sys.stdin)["data"]["result"]))'
}

wait_for "Kyverno failure log for $pod in Loki" has_log
wait_for "active root-filesystem audit alert in Alertmanager" has_alert
wait_for "student CPU by node" has_metric 'sum by (node, namespace) (rate(container_cpu_usage_seconds_total{namespace="student01",container!="",container!="POD",image!=""}[5m]))'
wait_for "student memory by node" has_metric 'sum by (node, namespace) (container_memory_working_set_bytes{namespace="student01",container!="",container!="POD",image!=""})'

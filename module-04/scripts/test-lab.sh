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

pod_manifest() {
  local namespace=$1 labels=$2
  cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  generateName: module04-mesh-test-
  namespace: $namespace
  labels: $labels
spec:
  automountServiceAccountToken: false
  containers:
  - name: app
    image: busybox:1.37
    command: ["sleep", "300"]
    securityContext:
      readOnlyRootFilesystem: true
EOF
}

assert_pod() {
  python3 -c '
import json
import sys

expected_person, expected_proxy = sys.argv[1:]
pod = json.load(sys.stdin)
metadata = pod["metadata"]
spec = pod["spec"]
proxy = (
    any(c["name"] == "istio-proxy" for c in spec["containers"])
    or any(c["name"] == "istio-proxy" and c.get("restartPolicy") == "Always"
           for c in spec.get("initContainers", []))
)
assert metadata.get("labels", {}).get("person") == (expected_person or None), metadata
assert proxy == (expected_proxy == "true"), spec
assert bool(metadata.get("annotations", {}).get("sidecar.istio.io/status")) == proxy, metadata
print(metadata["namespace"] + ": person=" + (expected_person or "absent") + ", proxy=" + str(proxy))
' "$1" "$2"
}

for namespace in student01 student02 student03; do
  pod_manifest "$namespace" '{}' |
    "${lab[@]}" create --dry-run=server -f - -o json | assert_pod student true
done
pod_manifest mentor '{}' |
  "${lab[@]}" create --dry-run=server -f - -o json | assert_pod mentor false
pod_manifest default '{"person":"student"}' |
  "${lab[@]}" create --dry-run=server -f - -o json | assert_pod '' false

if denial=$(pod_manifest student01 '{"sidecar.istio.io/inject":"false"}' |
    "${lab[@]}" create --dry-run=server -f - 2>&1); then
  echo "A student Pod opted out of Istio injection." >&2
  exit 1
fi
if ! grep -Fq 'Student Pods must have an injected Istio sidecar' <<< "$denial"; then
  printf '%s\n' "$denial" >&2
  exit 1
fi
echo 'Kyverno denied the student Pod with injection disabled.'

pod=$(pod_manifest student01 '{"person":"student"}' |
  "${lab[@]}" create -f - -o 'jsonpath={.metadata.name}')
"${lab[@]}" -n student01 wait --for=condition=Ready "pod/$pod" --timeout=180s
"${lab[@]}" -n student01 get pod "$pod" -o json | assert_pod student true

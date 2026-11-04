#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: bash $0 ADMIN_KUBECONFIG CONTEXT" >&2
  exit 2
fi

admin=(kubectl "--kubeconfig=$1" "--context=$2")
config_dir="$(dirname -- "${BASH_SOURCE[0]}")/../kubeconfigs"

assert_access() {
  local verb=$1 resource=$2 namespace=$3 expected=$4 answer status=0
  local args=(auth can-i "$verb" "$resource")
  if [[ -n $namespace ]]; then args+=(-n "$namespace"); fi
  answer=$("${client[@]}" "${args[@]}") || status=$?
  if [[ $answer != "$expected" ]] ||
     [[ $expected == yes && $status != 0 ]] ||
     [[ $expected == no && $status != 1 ]]; then
    printf '%s %s %s in %s: expected %s, got %s (exit %s)\n' \
      "$identity" "$verb" "$resource" "${namespace:-cluster}" "$expected" "$answer" "$status" >&2
    return 1
  fi
}

for identity in mentor student01 student02 student03; do
  client=(kubectl "--kubeconfig=$config_dir/$identity.kubeconfig")
  who=$("${client[@]}" auth whoami -o 'jsonpath={.status.userInfo.username}')
  if [[ $who != "system:serviceaccount:module02-identities:$identity" ]]; then
    echo "Unexpected authenticated identity for $identity." >&2
    exit 1
  fi
  for namespace in mentor student01 student02 student03 default kube-system; do
    read_access=no
    write_access=no
    case "$identity:$namespace" in
      mentor:student0[123]|student01:student01|student03:student03)
        read_access=yes
        write_access=yes
        ;;
      student02:student01|student02:default) read_access=yes ;;
    esac
    for resource in pods deployments.apps; do
      assert_access list "$resource" "$namespace" "$read_access"
      for verb in create patch delete; do
        assert_access "$verb" "$resource" "$namespace" "$write_access"
      done
    done
    assert_access create rolebindings "$namespace" no
  done
  assert_access list nodes '' no
  assert_access create clusterrolebindings '' no
  assert_access '*' '*' '' no
  printf 'RBAC passed for %s\n' "$identity"
done

warnings=$(mktemp)
trap 'rm -f -- "$warnings"' EXIT

assert_admission() {
  local namespace=$1 expected=$2 read_only=$3 init_read_only=$4 labels=$5
  local result warned=false expected_warning=false
  if ! result=$("${admin[@]}" create --dry-run=server -f - -o json 2>"$warnings" <<EOF
apiVersion: v1
kind: Pod
metadata:
  generateName: module02-test-
  namespace: $namespace
  labels: $labels
spec:
  automountServiceAccountToken: false
  containers:
  - name: app
    image: busybox:1.37
    securityContext:
      readOnlyRootFilesystem: $read_only
  initContainers:
  - name: init
    image: busybox:1.37
    securityContext:
      readOnlyRootFilesystem: $init_read_only
EOF
  ); then
    cat "$warnings" >&2
    return 1
  fi
  python3 -c '
import json
import sys

expected, original = sys.argv[1:]
pod = json.load(sys.stdin)
labels = pod["metadata"].get("labels", {})
if (labels.get("person") != (expected or None)
        or labels.get("keep") != json.loads(original).get("keep")):
    sys.exit("Unexpected labels in " + pod["metadata"]["namespace"])
' "$expected" "$labels" <<< "$result"
  if grep -Fq 'Every container must set securityContext' "$warnings"; then warned=true; fi
  if [[ $read_only != true || $init_read_only != true ]]; then expected_warning=true; fi
  if [[ $warned != "$expected_warning" ]]; then
    echo "Unexpected audit result in $namespace." >&2
    return 1
  fi
}

assert_admission mentor mentor true true '{"keep":"yes"}'
assert_admission student01 student false true '{"person":"mentor","keep":"yes"}'
assert_admission student02 student true false '{"person":"","keep":"yes"}'
assert_admission student03 student true true '{"keep":"yes"}'
assert_admission default '' true true '{"person":"","keep":"yes"}'
assert_admission default '' true true '{}'
for namespace in kube-system kube-public kube-node-lease kyverno; do
  assert_admission "$namespace" '' true true '{"person":"unexpected","keep":"yes"}'
done
echo 'Kyverno admission passed'

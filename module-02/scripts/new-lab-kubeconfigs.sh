#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# != 2 ]]; then
  echo "Usage: bash $0 ADMIN_KUBECONFIG CONTEXT" >&2
  exit 2
fi

admin=(kubectl "--kubeconfig=$1" "--context=$2")
output="$(dirname -- "${BASH_SOURCE[0]}")/../kubeconfigs"
cluster=$("${admin[@]}" config view --minify --flatten --raw -o 'jsonpath={.clusters[0].cluster}')

python3 - "$cluster" <<'PY'
import json
import sys

cluster = json.loads(sys.argv[1])
if (not cluster["server"].startswith("https://")
        or not cluster.get("certificate-authority-data")
        or cluster.get("insecure-skip-tls-verify")):
    sys.exit("The test API endpoint must use HTTPS with a trusted cluster CA.")
PY

mkdir -p -- "$output"
temporary=$(mktemp -- "$output/.kubeconfig.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
for identity in mentor student01 student02 student03; do
  "${admin[@]}" -n module02-identities create token "$identity" --duration=1h |
    python3 -c '
import json
import sys

identity, cluster = sys.argv[1:]
token = sys.stdin.read().strip()
if not token:
    sys.exit("Token request returned an empty token.")
json.dump({
    "apiVersion": "v1",
    "kind": "Config",
    "clusters": [{"name": "module02-lab", "cluster": json.loads(cluster)}],
    "contexts": [{"name": identity, "context": {
        "cluster": "module02-lab", "user": identity, "namespace": identity
    }}],
    "current-context": identity,
    "users": [{"name": identity, "user": {"token": token}}],
}, sys.stdout, indent=2)
print()
' "$identity" "$cluster" > "$temporary"
  mv -f -- "$temporary" "$output/$identity.kubeconfig"
  printf 'Created %s.kubeconfig\n' "$identity"
  temporary=$(mktemp -- "$output/.kubeconfig.XXXXXX")
done

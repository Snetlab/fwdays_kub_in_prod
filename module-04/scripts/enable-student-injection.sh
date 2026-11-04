#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "Usage: bash $0 ADMIN_KUBECONFIG CONTEXT" >&2
  exit 2
fi

kubectl --kubeconfig "$1" --context "$2" label namespace student01 student02 student03 \
  istio-injection=enabled --overwrite

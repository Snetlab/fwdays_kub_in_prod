#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "Usage: bash $0 ADMIN_KUBECONFIG CONTEXT" >&2
  exit 2
fi

target=(--kubeconfig "$1" --kube-context "$2")
repo=https://blob.istio.io/istio-release/charts
version=1.31.3

helm upgrade --install istio-base base --repo "$repo" --version "$version" \
  --namespace istio-system --create-namespace --set defaultRevision=default \
  "${target[@]}" --wait --timeout 5m
helm upgrade --install istiod istiod --repo "$repo" --version "$version" \
  --namespace istio-system "${target[@]}" --wait --timeout 5m

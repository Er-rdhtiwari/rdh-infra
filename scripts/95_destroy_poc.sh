#!/usr/bin/env bash
set -euo pipefail
source .env
: "${POC_ID:?set POC_ID}"

NS="${POC_NAMESPACE_PREFIX}-${POC_ID}"
helm uninstall "${POC_ID}" -n "$NS" || true
kubectl delete namespace "$NS" --ignore-not-found

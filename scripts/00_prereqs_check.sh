#!/usr/bin/env bash
set -euo pipefail

required=(aws terraform kubectl helm jq envsubst)
echo "[check] verifying required CLIs..."
for c in "${required[@]}"; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing $c"; exit 1; }
done

echo "[check] aws identity:"
aws sts get-caller-identity

echo "[check] kubectl version:"
kubectl version --client --short

echo "[ok] prerequisites present."

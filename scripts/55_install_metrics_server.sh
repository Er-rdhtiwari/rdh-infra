#!/usr/bin/env bash
set -euo pipefail

# Installs metrics-server and runs a couple of quick checks.
# Usage: ./scripts/55_install_metrics_server.sh

echo "[info] Applying metrics-server components..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "[info] Waiting 90 seconds for metrics-server to start..."
sleep 90

echo "[info] kubectl top nodes:"
kubectl top nodes || echo "[warn] metrics not available yet; wait a bit more and retry 'kubectl top nodes'"

echo "[info] kubectl top pods -A:"
kubectl top pods -A || echo "[warn] metrics not available yet; wait a bit more and retry 'kubectl top pods -A'"

echo "[ok] metrics-server install attempted."

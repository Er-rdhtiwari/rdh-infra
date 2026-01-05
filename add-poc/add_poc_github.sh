#!/usr/bin/env bash
set -euo pipefail

# add_poc_github.sh
# Runs scripts/60_add_poc.sh with env vars for the "github" PoC.
# You can override any value by exporting it before running this script.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$REPO_ROOT/scripts/60_add_poc.sh" ]]; then
  echo "ERROR: $REPO_ROOT/scripts/60_add_poc.sh not found."
  echo "Place this script in the repo root (same level as scripts/) or adjust REPO_ROOT."
  exit 1
fi

export POC_ID="${POC_ID:-github}"
export POC_HELM_REPO="${POC_HELM_REPO:-https://stefanprodan.github.io/podinfo}"
export POC_HELM_REPO_NAME="${POC_HELM_REPO_NAME:-podinfo}"
export POC_HELM_CHART="${POC_HELM_CHART:-podinfo}"
export POC_HELM_VERSION="${POC_HELM_VERSION:-6.4.0}"
export POC_HELM_EXTRA_ARGS="${POC_HELM_EXTRA_ARGS:---set ui.message='GitHub: <a href=\"https://github.com/Er-rdhtiwari\" target=\"_blank\">Er-rdhtiwari</a>' --set ui.color=teal}"

echo "==> Adding PoC: $POC_ID"
echo "==> Chart: $POC_HELM_REPO_NAME/$POC_HELM_CHART ($POC_HELM_VERSION)"

bash "$REPO_ROOT/scripts/60_add_poc.sh"

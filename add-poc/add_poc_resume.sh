#!/usr/bin/env bash
set -euo pipefail

# add_poc_resume.sh
# Runs scripts/60_add_poc.sh with the env vars you listed.
# You can override any value by exporting it before running this script.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$REPO_ROOT/scripts/60_add_poc.sh" ]]; then
  echo "ERROR: $REPO_ROOT/scripts/60_add_poc.sh not found."
  echo "Run this script from the repo root, or place it in the repo root."
  exit 1
fi

export POC_ID="${POC_ID:-resume}"
export POC_HELM_REPO="${POC_HELM_REPO:-https://stefanprodan.github.io/podinfo}"
export POC_HELM_REPO_NAME="${POC_HELM_REPO_NAME:-podinfo}"
export POC_HELM_CHART="${POC_HELM_CHART:-podinfo}"
export POC_HELM_VERSION="${POC_HELM_VERSION:-6.4.0}"
export POC_HELM_EXTRA_ARGS="${POC_HELM_EXTRA_ARGS:---set replicaCount=1 --set ui.message='Resume: <a href=\"https://docs.google.com/document/d/1SXkMZZASwy2cdoBDVELRP8x80uGiPAxN/edit?usp=sharing&ouid=101849102496826439629&rtpof=true&sd=true\" target=\"_blank\">Open</a>' --set ui.color=indigo}"

echo "==> Adding PoC: $POC_ID"
echo "==> Chart: $POC_HELM_REPO_NAME/$POC_HELM_CHART ($POC_HELM_VERSION)"

bash "$REPO_ROOT/scripts/60_add_poc.sh"

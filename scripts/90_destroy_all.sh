#!/usr/bin/env bash
set -euo pipefail
source .env

echo "[destroy] Jenkins"
helm uninstall jenkins -n ci || true
kubectl delete ns ci --ignore-not-found

echo "[destroy] addons"
helm uninstall aws-load-balancer-controller -n kube-system || true
helm uninstall external-dns -n kube-system || true
helm uninstall aws-ebs-csi-driver -n kube-system || true

echo "[destroy] platform terraform"
cd platform
terraform destroy -auto-approve || true
cd ..

echo "[destroy] bootstrap terraform"
cd bootstrap
terraform destroy -auto-approve || true

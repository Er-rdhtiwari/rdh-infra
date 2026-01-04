#!/usr/bin/env bash
set -euo pipefail
source .env

echo "[verify] nodes"
kubectl get nodes -o wide

echo "[verify] addons"
kubectl get pods -n kube-system -l "app.kubernetes.io/name in (aws-load-balancer-controller,external-dns,aws-ebs-csi-driver)" --show-labels || true

echo "[verify] jenkins"
kubectl get ingress -n ci || true
kubectl get pods -n ci -o wide || true

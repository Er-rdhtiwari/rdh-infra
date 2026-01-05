#!/usr/bin/env bash
set -euo pipefail
source .env

required=(VPC_ID ALB_CONTROLLER_IAM_ROLE_ARN EXTERNALDNS_IAM_ROLE_ARN EBS_CSI_IAM_ROLE_ARN AWS_REGION NAME_PREFIX ENVIRONMENT ROOT_DOMAIN EXTERNALDNS_TXT_OWNER_ID)
for v in "${required[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "[error] Missing required env var: $v (set it in .env from platform outputs)"
    exit 1
  fi
done

kubectl get nodes >/dev/null

render() {
  local src="$1"
  local tmp
  tmp=$(mktemp "/tmp/$(basename "${src%.yaml}")-XXXXXX.yaml")
  envsubst < "$src" > "$tmp"
  echo "$tmp"
}

ALB_VALUES=$(render helm/aws-load-balancer-controller/values.yaml)
EXTERNALDNS_VALUES=$(render helm/external-dns/values.yaml)
EBS_VALUES=$(render helm/ebs-csi-driver/values.yaml)

helm repo add eks https://aws.github.io/eks-charts
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

kubectl create ns kube-system --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system -f "$ALB_VALUES" --version 1.8.2

helm upgrade --install external-dns external-dns/external-dns \
  -n kube-system -f "$EXTERNALDNS_VALUES" --version 1.16.1

helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  -n kube-system -f "$EBS_VALUES" --version 2.30.0

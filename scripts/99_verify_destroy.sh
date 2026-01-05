#!/usr/bin/env bash
set -euo pipefail

# Verifies that major resources are deleted (cluster, VPC, tf state bucket/table, hosted zone).
# Usage: ./scripts/99_verify_destroy.sh

set -a
source .env
set +a

REQUIRED_VARS=(AWS_REGION NAME_PREFIX ENVIRONMENT ROOT_DOMAIN TF_STATE_BUCKET TF_STATE_DYNAMO_TABLE)
for v in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "[error] Missing $v in .env" >&2
    exit 1
  fi
done

CLUSTER="${NAME_PREFIX}-${ENVIRONMENT}-eks"
HZ_NAME="poc.${ROOT_DOMAIN}"

echo "[check] EKS cluster ${CLUSTER} in ${AWS_REGION}"
aws eks describe-cluster --name "${CLUSTER}" --region "${AWS_REGION}" >/dev/null 2>&1 && echo "  -> STILL PRESENT" || echo "  -> Not found"

echo "[check] Nodegroups for ${CLUSTER}"
aws eks list-nodegroups --cluster-name "${CLUSTER}" --region "${AWS_REGION}" --query 'nodegroups' --output text 2>/dev/null || echo "  -> None"

echo "[check] VPCs tagged Name=${NAME_PREFIX}-${ENVIRONMENT}"
aws ec2 describe-vpcs --region "${AWS_REGION}" \
  --filters "Name=tag:Name,Values=${NAME_PREFIX}-${ENVIRONMENT}*" \
  --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "  -> None"

echo "[check] S3 tf state bucket ${TF_STATE_BUCKET}"
aws s3api head-bucket --bucket "${TF_STATE_BUCKET}" >/dev/null 2>&1 && echo "  -> STILL PRESENT" || echo "  -> Not found"

echo "[check] DynamoDB tf lock table ${TF_STATE_DYNAMO_TABLE}"
aws dynamodb describe-table --table-name "${TF_STATE_DYNAMO_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1 && echo "  -> STILL PRESENT" || echo "  -> Not found"

echo "[check] Hosted zone ${HZ_NAME}"
aws route53 list-hosted-zones-by-name --dns-name "${HZ_NAME}" --query 'HostedZones[].Id' --output text 2>/dev/null || echo "  -> None"

echo "[check] ALBs with poc domain"
aws elbv2 describe-load-balancers --region "${AWS_REGION}" \
  --query "LoadBalancers[?contains(DNSName, 'poc.${ROOT_DOMAIN}')][].DNSName" --output text 2>/dev/null || echo "  -> None"

echo "[done] Verification complete."

#!/usr/bin/env bash
set -euo pipefail
source .env

cat > platform/backend.hcl <<EOF2
bucket         = "${TF_STATE_BUCKET}"
key            = "${TF_STATE_KEY_PLATFORM}"
region         = "${AWS_REGION}"
dynamodb_table = "${TF_STATE_DYNAMO_TABLE}"
encrypt        = true
EOF2

cd platform
terraform init -backend-config=backend.hcl
terraform apply -auto-approve \
  -var="aws_region=${AWS_REGION}" \
  -var="name_prefix=${NAME_PREFIX}" \
  -var="environment=${ENVIRONMENT}" \
  -var="root_domain=${ROOT_DOMAIN}" \
  -var="vpc_cidr=${VPC_CIDR}" \
  -var="public_subnet_cidrs=${PUBLIC_SUBNET_CIDRS}" \
  -var="private_subnet_cidrs=${PRIVATE_SUBNET_CIDRS}" \
  -var="kubernetes_version=${K8S_VERSION}" \
  -var="node_instance_types=${NODE_INSTANCE_TYPES}" \
  -var="node_min_size=${NODE_MIN_SIZE}" \
  -var="node_max_size=${NODE_MAX_SIZE}" \
  -var="node_desired_size=${NODE_DESIRED_SIZE}" \
  -var="externaldns_txt_owner_id=${EXTERNALDNS_TXT_OWNER_ID}"

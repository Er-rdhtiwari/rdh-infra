#!/usr/bin/env bash
set -euo pipefail
source .env

cd bootstrap
terraform init
terraform apply -auto-approve \
  -var="aws_region=${AWS_REGION}" \
  -var="name_prefix=${NAME_PREFIX}" \
  -var="environment=${ENVIRONMENT}" \
  -var="root_domain=${ROOT_DOMAIN}" \
  -var="create_subdomain_zone=${CREATE_SUBDOMAIN_ZONE}"

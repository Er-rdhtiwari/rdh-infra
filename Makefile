SHELL := /bin/bash
.ONESHELL:
ENV ?= .env
include $(ENV)
export $(shell sed 's/=.*//' $(ENV))

tf-bootstrap=cd bootstrap
tf-platform=cd platform

BOOTSTRAP_VARS = \
	-var="aws_region=$(AWS_REGION)" \
	-var="name_prefix=$(NAME_PREFIX)" \
	-var="environment=$(ENVIRONMENT)" \
	-var="root_domain=$(ROOT_DOMAIN)" \
	-var="create_subdomain_zone=$(CREATE_SUBDOMAIN_ZONE)"

PLATFORM_VARS = \
	-var="aws_region=$(AWS_REGION)" \
	-var="name_prefix=$(NAME_PREFIX)" \
	-var="environment=$(ENVIRONMENT)" \
	-var="root_domain=$(ROOT_DOMAIN)" \
	-var="vpc_cidr=$(VPC_CIDR)" \
	-var="public_subnet_cidrs=$(PUBLIC_SUBNET_CIDRS)" \
	-var="private_subnet_cidrs=$(PRIVATE_SUBNET_CIDRS)" \
	-var="kubernetes_version=$(K8S_VERSION)" \
	-var="node_instance_types=$(NODE_INSTANCE_TYPES)" \
	-var="node_min_size=$(NODE_MIN_SIZE)" \
	-var="node_max_size=$(NODE_MAX_SIZE)" \
	-var="node_desired_size=$(NODE_DESIRED_SIZE)" \
	-var="externaldns_txt_owner_id=$(EXTERNALDNS_TXT_OWNER_ID)"

platform-backend:
	cat > platform/backend.hcl <<EOF
bucket         = "$(TF_STATE_BUCKET)"
key            = "$(TF_STATE_KEY_PLATFORM)"
region         = "$(AWS_REGION)"
dynamodb_table = "$(TF_STATE_DYNAMO_TABLE)"
encrypt        = true
EOF

init-bootstrap:
	$(tf-bootstrap); terraform init

apply-bootstrap:
	$(tf-bootstrap); terraform apply -auto-approve $(BOOTSTRAP_VARS)

destroy-bootstrap:
	$(tf-bootstrap); terraform destroy -auto-approve $(BOOTSTRAP_VARS)

init-platform: platform-backend
	$(tf-platform); terraform init -backend-config=backend.hcl

plan-platform: platform-backend
	$(tf-platform); terraform plan $(PLATFORM_VARS)

apply-platform: platform-backend
	$(tf-platform); terraform apply -auto-approve $(PLATFORM_VARS)

destroy-platform: platform-backend
	$(tf-platform); terraform destroy -auto-approve $(PLATFORM_VARS)

addons:
	scripts/30_addons_install.sh

jenkins:
	scripts/40_jenkins_install.sh

verify:
	scripts/50_verify_platform.sh

add-poc:
	scripts/60_add_poc.sh

.PHONY: init-bootstrap apply-bootstrap destroy-bootstrap init-platform plan-platform apply-platform destroy-platform addons jenkins verify add-poc platform-backend

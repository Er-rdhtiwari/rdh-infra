# Deployment Guide

Practical steps to stand up the platform (AWS EKS + addons + Jenkins) with checks along the way.

## Prerequisites
- Tools: `aws` v2, `terraform` >=1.6 (<2.0), `kubectl` >=1.27, `helm` >=3.13, `jq`, `envsubst`.
- AWS: credentials for `ap-south-1` with permission to manage S3, DynamoDB, Route53, ACM, VPC/EKS/EC2/ELB/IAM.
- DNS: root domain (e.g., `rdhcloudlab.com`). Subdomain `poc.<ROOT_DOMAIN>` will host PoCs and Jenkins.

## Prepare environment
1) Copy and fill env:  
   ```bash
   cp .env.example .env
   # edit values (region, names, CIDRs, node sizes, ROOT_DOMAIN, etc.)
   ```
2) Bootstrap values will output the state bucket/table; set `TF_STATE_BUCKET` and `TF_STATE_DYNAMO_TABLE` in `.env` to match outputs (`${NAME_PREFIX}-${ENVIRONMENT}-tf-state` and `${NAME_PREFIX}-${ENVIRONMENT}-tf-lock`).
3) Ensure `.env` is not committed (covered in `.gitignore`).

## Deployment steps (scripts)
1) Check tools: `scripts/00_prereqs_check.sh`
2) Bootstrap backend + optional subdomain: `scripts/10_bootstrap_apply.sh`
3) Apply platform (VPC, EKS, IRSA roles, ACM): `scripts/20_platform_apply.sh`  
   - After apply, copy outputs into `.env`: `VPC_ID`, `ALB_CONTROLLER_IAM_ROLE_ARN`, `EXTERNALDNS_IAM_ROLE_ARN`, `EBS_CSI_IAM_ROLE_ARN`, `ACM_CERT_ARN`.
4) Install addons (ALB controller, ExternalDNS, EBS CSI): `scripts/30_addons_install.sh`
5) Install Jenkins: `scripts/40_jenkins_install.sh`
6) Verify: `scripts/50_verify_platform.sh`
7) Add a PoC (example):  
   ```bash
   POC_ID=demo1 \
   POC_HELM_REPO=https://example.com/charts \
   POC_HELM_REPO_NAME=demo \
   POC_HELM_CHART=demo/app \
   POC_HELM_VERSION=1.2.3 \
   scripts/60_add_poc.sh
   ```

## Deployment steps (Make targets)
- Bootstrap: `make apply-bootstrap`
- Platform: `make apply-platform`
- Plan: `make plan-platform`
- Addons / Jenkins / Verify / PoC: `make addons`, `make jenkins`, `make verify`, `make add-poc`
- Destroy: `make destroy-platform`, `make destroy-bootstrap`

## Checkpoints & quick debug
1) Tools present  
   - Success: prereq script passes. Debug: `which terraform`, `aws sts get-caller-identity`, `terraform version`.
2) Bootstrap state  
   - Success: `terraform output` in `bootstrap` shows bucket/table. Debug: `aws s3 ls`, `aws dynamodb list-tables`.
3) Subdomain zone delegated  
   - Success: `dig poc.<ROOT_DOMAIN> NS` returns records. Debug: `aws route53 list-hosted-zones-by-name --dns-name poc.<ROOT_DOMAIN>`.
4) Platform apply  
   - Success: Terraform completes with outputs. Debug: `terraform plan`, `aws eks describe-cluster --name <cluster>`.
5) kubeconfig  
   - Success: `kubectl get nodes` shows Ready. Debug: `aws eks update-kubeconfig --name <cluster> --region ap-south-1`.
6) Addons  
   - Success: ALB controller, ExternalDNS, EBS CSI pods Ready. Debug: `kubectl logs -n kube-system deploy/aws-load-balancer-controller`, `.../external-dns`.
7) ACM cert  
   - Success: `aws acm describe-certificate --certificate-arn <arn> | jq '.Certificate.Status'` -> `"ISSUED"`. Debug: check validation CNAMEs in Route53.
8) Jenkins ingress  
   - Success: `kubectl get ingress -n ci` shows ADDRESS; HTTPS responds. Debug: `kubectl describe ingress -n ci`.
9) DNS records  
   - Success: `dig jenkins.poc.<ROOT_DOMAIN>` resolves ALB CNAME. Debug: ExternalDNS logs; confirm txtOwnerId.
10) Jenkins storage  
   - Success: `kubectl get pvc -n ci` Bound. Debug: `kubectl describe pvc -n ci`, EBS CSI node/controller logs.

## Cleanup
- Single PoC: `POC_ID=<id> scripts/95_destroy_poc.sh`
- Full teardown: `scripts/90_destroy_all.sh` (removes Jenkins/addons, destroys platform then bootstrap)

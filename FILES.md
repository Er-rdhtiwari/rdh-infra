# Repo File Guide

Quick reference for what lives where, why it matters, and how to use it.

## Directory map (purpose)
- `README.md` – primary runbook and flow overview.
- `FILES.md` – this file; per-file guide.
- `.env.example` – template for required environment variables. Copy to `.env` and fill. Do not commit `.env`.
- `.gitignore` – ignores Terraform state, tfvars, local backend file, and `.env`.
- `Makefile` – wrappers around scripts/terraform with vars pulled from `.env`.
- `bootstrap/` – Terraform for S3 state bucket, DynamoDB lock, optional `poc.<ROOT_DOMAIN>` Route53 zone.
  - `main.tf` – bucket, lock table, optional hosted zone.
  - `variables.tf` – required inputs.
  - `outputs.tf` – bucket/table names, zone details; feed back into `.env`.
  - `versions.tf` – Terraform >=1.6 constraint + AWS provider pin.
  - `.terraform.lock.hcl` – provider version lock; commit it.
- `platform/` – Terraform for VPC, EKS, IAM for IRSA, ACM/DNS.
  - `backend.tf` – S3 backend stub (config generated into `backend.hcl` by scripts/Makefile).
  - `versions.tf` – Terraform >=1.6 constraint + AWS provider pin.
  - `providers.tf` – AWS provider (Kubernetes/Helm providers are handled by Helm CLI, not Terraform).
  - `variables.tf` – cluster/network/IRSA inputs (from `.env`).
  - `vpc.tf` – VPC + subnet tags (public/private + cluster tags for ALB controller).
  - `eks.tf` – EKS cluster, managed node group, ALB SG rule for pod access.
  - `iam.tf` – IRSA roles/policies for ALB controller, ExternalDNS, EBS CSI.
  - `dns_acm.tf` – public hosted zone lookup and wildcard ACM cert + DNS validation.
  - `outputs.tf` – VPC ID, cluster info, IAM role ARNs, ACM cert ARN, zone info (copy into `.env` for Helm).
  - `policies/*.json` – IAM policy docs for addons.
  - `.terraform.lock.hcl` – provider lock; commit it.
- `helm/` – Helm values templates rendered via `envsubst` in scripts.
  - `aws-load-balancer-controller/values.yaml` – IRSA annotation + cluster/VPC IDs.
  - `external-dns/values.yaml` – domain filter, IRSA annotation, txtOwnerId.
  - `ebs-csi-driver/values.yaml` – IRSA annotation, default gp3 StorageClass.
  - `jenkins/values.yaml` – ingress/ALB annotations, admin secret refs, storage size.
- `scripts/` – workflow automation (all source `.env`).
  - `00_prereqs_check.sh` – asserts CLI tools and shows AWS identity/kubectl client version.
  - `10_bootstrap_apply.sh` – runs bootstrap Terraform with `.env` vars.
  - `20_platform_apply.sh` – writes `platform/backend.hcl` then applies platform Terraform with `.env` vars.
  - `30_addons_install.sh` – renders Helm values, adds repos (eks + aws-ebs-csi-driver), installs ALB controller, ExternalDNS, EBS CSI.
  - `40_jenkins_install.sh` – creates `ci` namespace + `jenkins-admin` secret, installs Jenkins chart.
  - `50_verify_platform.sh` – quick sanity checks for nodes/addons/Jenkins objects.
  - `60_add_poc.sh` – creates PoC namespace, quota/limits, installs user-provided Helm chart with ALB ingress host `<id>.poc.<ROOT_DOMAIN>`.
  - `90_destroy_all.sh` – uninstall Jenkins/addons, destroy platform then bootstrap Terraform.
  - `95_destroy_poc.sh` – uninstall a PoC release and delete its namespace.

## Important usage notes
- Terraform version: >= 1.6.0, < 2.0.0 (pinned in `versions.tf`), AWS provider ~> 5.46 (locked).
- Backend config: `platform/backend.hcl` is generated; it is ignored by Git. Ensure `.env` has the bootstrap outputs (`TF_STATE_BUCKET`, `TF_STATE_DYNAMO_TABLE`).
- Helm rendering: scripts use `envsubst` to fill `${...}` placeholders; keep `.env` synced with platform outputs (VPC_ID, IAM role ARNs, ACM_CERT_ARN, ROOT_DOMAIN).
- Subnet tagging: `platform/vpc.tf` tags public/private subnets for ALB (`kubernetes.io/role/*`) and associates with the cluster name; required for ALB controller.
- Security groups: `platform/eks.tf` allows ALB SG to reach nodes/pods (all ports) for IP target mode.
- Provider locks: commit `.terraform.lock.hcl` files so team uses the same provider versions.
- Secrets: only sample creds live in `.env.example`; real `.env` should not be committed.

## Quick command references
- Apply: `scripts/10_bootstrap_apply.sh` → copy outputs into `.env` → `scripts/20_platform_apply.sh` → `scripts/30_addons_install.sh` → `scripts/40_jenkins_install.sh`.
- Makefile shortcuts: `make apply-bootstrap`, `make apply-platform`, `make plan-platform`, `make addons`, `make jenkins`, `make verify`, `make add-poc`, `make destroy-*`.
- Validation: `terraform validate` inside `bootstrap/` and `platform/` (init with `-backend=false` for offline checks).
- Destroy: `POC_ID=<id> scripts/95_destroy_poc.sh` (single PoC) or `scripts/90_destroy_all.sh` (full teardown).

# Platform Infrastructure Repo (AWS EKS, Jenkins, PoC-ready)

## Why
- Separate platform infra from PoC repos to avoid blast radius.
- Scripts + pinned versions reduce drift and onboarding time.
- IRSA, private nodes, quotas, and HTTPS-first keep PoCs contained.

## Prerequisites
- CLI tools: `aws` (v2), `terraform` (>=1.6), `kubectl` (>=1.27), `helm` (>=3.13), `jq`, `envsubst`.
- AWS IAM: ability to create S3, DynamoDB, Route53 hosted zones/records, ACM certs, VPC/EKS/EC2/ELB/IAM.
- Logged in with credentials for `ap-south-1`.
- Domain: have ROOT_DOMAIN (e.g., `rdhcloudlab.com`). Subdomain `poc.<ROOT_DOMAIN>` will host PoCs and Jenkins.

## One-time domain setup
1) If ROOT_DOMAIN in Route53: ensure zone exists.  
2) Bootstrap (next section) can create `poc.<ROOT_DOMAIN>` hosted zone; copy its NS into ROOT_DOMAIN zone as delegation.

## Flow overview
1) Bootstrap Terraform backend + (optional) subdomain hosted zone.  
2) Platform Terraform: VPC, EKS, OIDC/IRSA roles, ACM wildcard cert.  
3) Helm addons: ALB controller, ExternalDNS, EBS CSI driver.  
4) Jenkins install in `ci` namespace behind ALB HTTPS.  
5) PoC onboarding via namespace, quota, Helm chart, ingress host `<id>.poc.<ROOT_DOMAIN>`.

## Environment
Copy `.env.example` to `.env` and adjust. If a bucket/table already exist or you want custom names, set `TF_STATE_BUCKET` / `TF_STATE_DYNAMO_TABLE` before bootstrapping; otherwise leave them blank to let bootstrap create `${NAME_PREFIX}-${ENVIRONMENT}-tf-state` and `${NAME_PREFIX}-${ENVIRONMENT}-tf-lock`. After `scripts/10_bootstrap_apply.sh`, update `TF_STATE_BUCKET` / `TF_STATE_DYNAMO_TABLE` to match the outputs. After `scripts/20_platform_apply.sh`, copy Terraform outputs (VPC ID, IAM role ARNs, ACM cert ARN) back into `.env` so Helm value rendering works.

## Step-by-step
### 1) Bootstrap state + subdomain
```
scripts/00_prereqs_check.sh
scripts/10_bootstrap_apply.sh
```
- Output: S3 bucket, DynamoDB table, optional hosted zone + NS.

### 2) Deploy platform
```
scripts/20_platform_apply.sh
```
- Creates VPC, EKS, nodegroup, OIDC, IRSA roles, ACM cert.

### 3) Install addons (ALB, ExternalDNS, EBS CSI)
```
scripts/30_addons_install.sh
```

### 4) Install Jenkins
```
scripts/40_jenkins_install.sh
# If error then run below one and rerun above one
helm uninstall jenkins -n ci
```
- Admin creds stored in `jenkins-admin` secret; hostname `jenkins.poc.<ROOT_DOMAIN>` with HTTPS (ALB + ACM).

### 5) Verify
```
scripts/50_verify_platform.sh
```
- Nodes: `aws eks update-kubeconfig --name ${NAME_PREFIX}-${ENVIRONMENT}-eks --region ${AWS_REGION} && kubectl get nodes -o wide`
- Addons: `kubectl get pods -n kube-system -l 'app.kubernetes.io/name in (aws-load-balancer-controller,external-dns,aws-ebs-csi-driver)'`
- Jenkins: `kubectl get pods,svc,ingress,pvc -n ci`
- DNS/ALB: `kubectl describe ingress jenkins -n ci`, `dig +short jenkins.poc.${ROOT_DOMAIN}`, `curl -kI https://jenkins.poc.${ROOT_DOMAIN}`
- Cert: `aws acm describe-certificate --certificate-arn $ACM_CERT_ARN | jq .Certificate.Status` (expect ISSUED)

- Install metrics-server (for `kubectl top`):
```
scripts/55_install_metrics_server.sh
kubectl top nodes
kubectl top pods -A
```

- To “destroy” what you applied from that URL, delete the same manifest.

```bash
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Then verify it’s gone:

```bash
kubectl get pods -n kube-system | grep metrics-server || true
kubectl api-resources | grep metrics.k8s.io || true
```

If it doesn’t delete cleanly, force-remove the namespace objects (rare):

```bash
kubectl delete deployment metrics-server -n kube-system --ignore-not-found
kubectl delete service metrics-server -n kube-system --ignore-not-found
kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found
```

### 6) Add a PoC
Example (Helm chart from repo):
```
POC_ID=demo1 POC_HELM_REPO=https://example.com/charts \
POC_HELM_REPO_NAME=demo POC_HELM_CHART=demo/app POC_HELM_VERSION=1.2.3 \
scripts/60_add_poc.sh
```
- Namespace `poc-demo1`, quota/limits applied, ingress host `demo1.poc.<ROOT_DOMAIN>` (ExternalDNS + ALB).
- Optional knobs for PoCs:
  - `POC_HELM_EXTRA_ARGS`: extra flags passed to `helm upgrade` (e.g., `--set ui.message='Hello'`).
  - `POC_HELM_VALUES_FILES`: comma-separated list of values files to `-f` into the release.

Sample POCs (no code changes needed, just set env vars and run `scripts/60_add_poc.sh`):
- **Resume link** (podinfo with CTA):  
  ```
  export POC_ID=resume
  export POC_HELM_REPO=https://stefanprodan.github.io/podinfo
  export POC_HELM_REPO_NAME=podinfo
  export POC_HELM_CHART=podinfo
  export POC_HELM_VERSION=6.4.0
  export POC_HELM_EXTRA_ARGS="--set replicaCount=1 --set ui.message='Resume: <a href=\"https://docs.google.com/document/d/1SXkMZZASwy2cdoBDVELRP8x80uGiPAxN/edit?usp=sharing&ouid=101849102496826439629&rtpof=true&sd=true\" target=\"_blank\">Open</a>' --set ui.color=indigo"
  scripts/60_add_poc.sh
  ```
- **GitHub profile link** (podinfo message to your GitHub README):  
  ```
  export POC_ID=github
  export POC_HELM_REPO=https://stefanprodan.github.io/podinfo
  export POC_HELM_REPO_NAME=podinfo
  export POC_HELM_CHART=podinfo
  export POC_HELM_VERSION=6.4.0
  export POC_HELM_EXTRA_ARGS="--set ui.message='GitHub: <a href=\"https://github.com/Er-rdhtiwari\" target=\"_blank\">Er-rdhtiwari</a>' --set ui.color=teal"
  scripts/60_add_poc.sh
  ```
- **Minimal todo PoC** (public sample chart):
  ```
  export POC_ID=todo
  export POC_HELM_REPO=https://dapr.github.io/helm-charts
  export POC_HELM_REPO_NAME=dapr
  export POC_HELM_CHART=sample
  export POC_HELM_VERSION=1.10.0
  export POC_HELM_EXTRA_ARGS="--set service.type=ClusterIP --set ingress.enabled=true --set ingress.className=alb --set ingress.hosts[0]=todo.poc.${ROOT_DOMAIN}"
  scripts/60_add_poc.sh
  ```
  (Replace with your own chart if you have a preferred todo app image; use `POC_HELM_VALUES_FILES` to supply custom values.)
- **Habitify app** (build + deploy from repo `Er-rdhtiwari/habitify` using its Helm chart):
  - Requires `.env` with `ROOT_DOMAIN`, docker CLI, and an image registry you can push to.
  - From repo root:
  ```
  ./add-poc/add_poc_habitify.sh IMAGE_REPO=<registry>/habitify IMAGE_TAG=latest \
    POC_ID=habitify POC_NAMESPACE_PREFIX=poc \
    HABITIFY_BUILD_IMAGE=true HABITIFY_PUSH_IMAGE=true
  ```
  - Defaults: clones to `/tmp/habitify`, builds/pushes image, deploys chart with ALB ingress at `habitify.poc.<ROOT_DOMAIN>`.
  - Use `-h` for help and more overrides (e.g., clone dir, git URL, build/push toggles).

### 7) Destroy
- Single PoC: `POC_ID=demo1 scripts/95_destroy_poc.sh`
- Find PoC IDs (release name == POC_ID):
  ```
  helm list -A
  kubectl get ns | grep '^poc-'
  kubectl get ingress -A
  ```
- Destroy a PoC: `POC_ID=<id> scripts/95_destroy_poc.sh`
- Everything: `scripts/90_destroy_all.sh` (uninstalls Jenkins/addons, terraform destroy platform then bootstrap).
- If Terraform prompts for vars during destroy, supply the same values as in your `.env`.
- Alternative manual destroys (from repo root):
  ```
  # Platform destroy
  cd platform
  terraform destroy -auto-approve \
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
  cd ..

  # Bootstrap destroy
  cd bootstrap
  terraform destroy -auto-approve \
    -var="aws_region=${AWS_REGION}" \
    -var="name_prefix=${NAME_PREFIX}" \
    -var="environment=${ENVIRONMENT}" \
    -var="root_domain=${ROOT_DOMAIN}" \
    -var="create_subdomain_zone=${CREATE_SUBDOMAIN_ZONE}" \
    -var="tf_state_bucket=${TF_STATE_BUCKET}" \
    -var="tf_lock_table=${TF_STATE_DYNAMO_TABLE}"
  cd ..
  ```

## Cost control
- Nodegroup is single ASG with min=1; adjust to 0 for idle via Terraform var `node_min_size`.
- Delete idle PoC namespaces via destroy script.
- Shut down ALBs by removing ingresses if unused.
- Use `scripts/90_destroy_all.sh` for full teardown.

## Debug checklist highlights
- Identity: `aws sts get-caller-identity`; context: `kubectl config current-context`.
- State issues: `terraform state pull`; check S3/Dynamo exist.
- Cluster access: `aws eks update-kubeconfig --name <cluster> --region <region>`; `kubectl get nodes`.
- Events: `kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 30`.
- ALB/DNS: `kubectl get ingress -A`; `kubectl describe ingress <name> -n <ns>`; ExternalDNS logs `kubectl logs -n kube-system deploy/external-dns --tail=50`; ALB controller logs `kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=50`; DNS `dig +short <host>`.
- Cert: `aws acm describe-certificate --certificate-arn $ACM_CERT_ARN | jq .Certificate.Status`.
- PVC: `kubectl get pvc -A`; if Pending, `kubectl describe pvc <name> -n <ns>` and ensure a node exists in the PV’s AZ.

## Versions
- Terraform: >=1.6
- AWS provider: ~> 5.46
- Helm charts: ALB controller 1.8.2, ExternalDNS 1.16.1, EBS CSI driver 2.30.0, Jenkins 5.6.1
- EKS Kubernetes version default: 1.28 (override via var)

## Architecture (short)
- VPC with public subnets for ALB, private subnets for nodes; single NAT for egress.
- EKS with IRSA enabled; managed nodegroup in private subnets.
- IAM roles per addon (ALB controller, ExternalDNS, EBS CSI) via IRSA.
- Route53 hosted zone `poc.<ROOT_DOMAIN>` + wildcard ACM cert `*.poc.<ROOT_DOMAIN>`.
- Addons via Helm; Jenkins in `ci` namespace with EBS-backed PVC and ALB ingress.
- PoCs isolated per namespace `poc-<id>` with ResourceQuota + LimitRange, ALB ingress + DNS.

ASCII
```
[Admins/laptop]
   | awscli/terraform/helm/kubectl
   v
[S3 tfstate + DynamoDB lock]  <-- bootstrap
   |
   v
[VPC (3AZ) + Public subnets (ALB) + Private subnets (nodes)]
   |
   v
[EKS cluster platform-dev-eks + OIDC]
   |           |             |
   |           |             +-- IRSA: EBS CSI driver -> EBS
   |           +-- IRSA: ALB Controller -> ALB
   +-- IRSA: ExternalDNS -> Route53 (poc.<ROOT_DOMAIN>)
   |
Namespaces: ci (Jenkins PVC via EBS, ingress jenkins.poc.<ROOT_DOMAIN>)
            poc-<id> (quota+limits, ingress <id>.poc.<ROOT_DOMAIN>)
```

## Repo tree
```
.
├─ README.md
├─ .env.example
├─ Makefile
├─ scripts/
│  ├─ 00_prereqs_check.sh
│  ├─ 10_bootstrap_apply.sh
│  ├─ 20_platform_apply.sh
│  ├─ 30_addons_install.sh
│  ├─ 40_jenkins_install.sh
│  ├─ 50_verify_platform.sh
│  ├─ 60_add_poc.sh
│  ├─ 90_destroy_all.sh
│  └─ 95_destroy_poc.sh
├─ bootstrap/
├─ platform/
│  └─ policies/
└─ helm/
```

## Runbook (commands in order)
- `cp .env.example .env` and edit values.
- `scripts/00_prereqs_check.sh`
- `scripts/10_bootstrap_apply.sh`
- `scripts/20_platform_apply.sh` (then set VPC_ID, IAM role ARNs, ACM_CERT_ARN in `.env` from outputs)
- `scripts/30_addons_install.sh`
- `scripts/40_jenkins_install.sh`
- `scripts/50_verify_platform.sh`
- Add PoC: set env vars (POC_ID, POC_HELM_REPO, POC_HELM_REPO_NAME, POC_HELM_CHART, POC_HELM_VERSION) then `scripts/60_add_poc.sh`
- Destroy PoC: `POC_ID=<id> scripts/95_destroy_poc.sh`
- Destroy all: `scripts/90_destroy_all.sh`

## Makefile shortcuts
- `make apply-bootstrap` / `make destroy-bootstrap` run bootstrap with vars from `.env`.
- `make apply-platform` / `make destroy-platform` create `platform/backend.hcl` from `.env` and run Terraform.
- `make addons`, `make jenkins`, `make verify`, `make add-poc` wrap the corresponding scripts.
- `make plan-platform` runs `terraform plan` with all required vars set from `.env`.

## Checkpoints (success, failures, first debug commands)
1) Tools present  
   - Success: `scripts/00_prereqs_check.sh` completes.  
   - Fail: Missing CLI.  
   - Debug: `which terraform`; `aws sts get-caller-identity`; `terraform version`.
2) Bootstrap state  
   - Success: `terraform output` in `bootstrap` shows bucket/table.  
   - Fail: S3/Dynamo AccessDenied.  
   - Debug: `aws s3 ls`; `aws dynamodb list-tables`; `terraform state list`.
3) Subdomain zone delegated  
   - Success: `dig poc.<ROOT_DOMAIN> NS` returns delegation.  
   - Fail: ExternalDNS later says “no hosted zone”.  
   - Debug: `aws route53 list-hosted-zones-by-name --dns-name poc.<ROOT_DOMAIN>`; check NS records in root zone.
4) Platform apply  
   - Success: `terraform apply` completes; outputs ARNs.  
   - Fail: VPC/EKS errors.  
   - Debug: `terraform plan`; `aws eks describe-cluster --name platform-dev-eks`; `aws ec2 describe-vpcs`.
5) kubeconfig  
   - Success: `kubectl get nodes` shows Ready.  
   - Fail: Unauthorized/timeout.  
   - Debug: `aws eks update-kubeconfig --name platform-dev-eks --region ap-south-1`; `kubectl config get-contexts`; `kubectl get events -A`.
6) Addons installed  
   - Success: `kubectl get pods -n kube-system` shows alb-controller, external-dns, ebs-csi ready.  
   - Fail: CrashLoop.  
   - Debug: `kubectl logs -n kube-system deploy/aws-load-balancer-controller`; `kubectl logs -n kube-system deploy/external-dns`; `kubectl describe pod <pod> -n kube-system`.
7) ACM issued  
   - Success: `aws acm describe-certificate --certificate-arn <arn> | jq '.Certificate.Status'` -> ISSUED.  
   - Fail: Pending validation.  
   - Debug: `aws route53 list-resource-record-sets --hosted-zone-id <poc_zone_id>`; `dig -t CNAME _<...>.poc.<ROOT_DOMAIN>`.
8) Jenkins ALB  
   - Success: `kubectl get ingress -n ci` shows ADDRESS; `curl -k https://jenkins.poc.<ROOT_DOMAIN>` returns 403/redirect.  
   - Fail: ADDRESS empty.  
   - Debug: `kubectl describe ingress -n ci`; `kubectl get events -n ci`; `kubectl logs -n kube-system deploy/aws-load-balancer-controller`.
9) DNS records  
   - Success: `dig jenkins.poc.<ROOT_DOMAIN>` resolves ALB CNAME.  
   - Fail: NXDOMAIN.  
   - Debug: `kubectl logs -n kube-system deploy/external-dns`; `aws route53 list-resource-record-sets --hosted-zone-id <poc_zone_id>`; check txtOwnerId matches.
10) Jenkins PVC  
   - Success: `kubectl get pvc -n ci` Bound.  
   - Fail: Pending.  
   - Debug: `kubectl describe pvc -n ci`; `kubectl logs -n kube-system ds/ebs-csi-node`; `aws ec2 describe-volumes --filters Name=tag:kubernetes.io/created-for/pvc/name,Values=jenkins`.

## Troubleshooting playbook
- Terraform backend/state: S3 access denied → verify IAM + bucket names; `terraform init -reconfigure`; Dynamo lock stuck → `terraform force-unlock <id>` only after confirming no active run.
- EKS access/kubeconfig: rerun `aws eks update-kubeconfig --name platform-dev-eks --region ap-south-1`; confirm `aws sts get-caller-identity`.
- ALB Controller: ALB missing → controller logs for IAM/SG/subnet tag errors; ensure IRSA annotation uses output ARN; subnets tagged for elb/internal.
- ExternalDNS: Records missing → logs show “no hosted zone” or AccessDenied; ensure `domainFilters` matches `poc.<ROOT_DOMAIN>` and NS delegation is correct; txtOwnerId consistent.
- ACM/cert: Pending → validate DNS CNAME exists in zone; wait a few minutes.
- Ingress/ALB health: Target group unhealthy → check service ports and readiness; ensure `alb.ingress.kubernetes.io/target-type=ip` and pods in private subnets.
- Jenkins PVC: Pending → confirm StorageClass gp3 exists; EBS CSI controller/node pods ready; IAM role annotation correct.
- IRSA: Pods failing AWS API access → `kubectl describe sa <name> -n kube-system` to verify annotation; ensure OIDC provider present and trust policy subject matches service account.

This runbook is a practical, command-first guide to operate an AWS EKS “platform cluster” that hosts Jenkins (via Helm) and common Kubernetes add-ons (AWS Load Balancer Controller, ExternalDNS, EBS CSI, Metrics Server).
It covers setup validation, troubleshooting, DNS/Ingress verification, PoC lifecycle operations (install/destroy), and full platform teardown, with commands organized by intent (config → verify → debug → cleanup).
All sensitive values are replaced with placeholders so the document can be safely stored in a public repository.

## 1) AWS Account + CLI sanity checks (config)

### 1.1 Confirm AWS identity (permissions sanity)

```bash
aws sts get-caller-identity
```

**Expected output (example)**: JSON with `Account`, `Arn`.

### 1.2 Set default region (avoid repeating `--region`)

```bash
aws configure set region <AWS_REGION>
```

**Expected output**: no output on success.

### 1.3 Quick S3 permission / account sanity check

```bash
aws s3api list-buckets
```

**Expected output (example)**: JSON with `Buckets` and `Owner`.

---

## 2) Route53 DNS verification (config + debug)

### 2.1 Verify hosted zone exists for root domain

```bash
aws route53 list-hosted-zones-by-name --dns-name <ROOT_DOMAIN> --max-items 1
```

**Expected output (example)**: JSON showing the hosted zone id and name.

### 2.2 Confirm subdomain delegation exists in root hosted zone

Example: check the `NS` delegation record for `poc.<ROOT_DOMAIN>.` inside `<ROOT_DOMAIN>` hosted zone.

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "<HZ_ROOT>" \
  --query "ResourceRecordSets[?Name=='poc.<ROOT_DOMAIN>.']"
```

**Expected output (example)**: JSON list with `Type: NS` and `ResourceRecords` containing `ns-...` values.

✅ **Why this matters:** If `Ingress/ExternalDNS` later “works” but DNS doesn’t resolve, this is one of the first checks.

---

## 3) EKS access & kubeconfig (config + debug)

### 3.1 Update kubeconfig for the cluster

```bash
aws eks update-kubeconfig --name <CLUSTER_NAME> --region <AWS_REGION>
```

**Expected output (example)**: context added/updated in `~/.kube/config`.

### 3.2 Confirm available contexts + current context

```bash
kubectl config get-contexts
```

**Expected output**: list of contexts (current one has `*`).

### 3.3 Switch to the correct context (if needed)

```bash
kubectl config use-context arn:aws:eks:<AWS_REGION>:<AWS_ACCOUNT_ID>:cluster/<CLUSTER_NAME>
```

**Expected output**: “Switched to context …”

### 3.4 Validate access to worker nodes

```bash
kubectl get nodes
```

**Expected output (example)**: nodes in `Ready` status.

---

## 4) Fix/ensure EKS API access for an IAM principal (when kubectl auth fails)

Use this if `kubectl` fails with authorization errors.

### 4.1 Create access entry

```bash
aws eks create-access-entry \
  --cluster-name <CLUSTER_NAME> \
  --principal-arn <AWS_IAM_PRINCIPAL_ARN> \
  --type STANDARD \
  --region <AWS_REGION>
```

**Expected output (example)**: JSON containing an `accessEntry`.

### 4.2 Associate cluster admin policy (cluster-scope)

```bash
aws eks associate-access-policy \
  --cluster-name <CLUSTER_NAME> \
  --principal-arn <AWS_IAM_PRINCIPAL_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region <AWS_REGION>
```

✅ **After this:** run `aws eks update-kubeconfig ...` again and retry `kubectl get nodes`.

---

## 5) Cluster add-ons health checks (debug / verification)

### 5.1 EBS CSI driver (storage provisioning)

```bash
kubectl get pod -n kube-system -l "app.kubernetes.io/name=aws-ebs-csi-driver,app.kubernetes.io/instance=aws-ebs-csi-driver"
```

**Expected output (example)**: `ebs-csi-controller` `Running` (often `5/5` ready), `ebs-csi-node` `Running`.

### 5.2 AWS Load Balancer Controller + ExternalDNS (basic check)

```bash
kubectl get pods -n kube-system -l 'app.kubernetes.io/name in (aws-load-balancer-controller,external-dns)'
```

### 5.3 AWS Load Balancer Controller + ExternalDNS + EBS CSI (single combined check)

```bash
kubectl get pods -n kube-system -l 'app.kubernetes.io/name in (aws-load-balancer-controller,external-dns,aws-ebs-csi-driver)'
```

✅ **Debug signals**

* If ALB isn’t created for ingress → check `aws-load-balancer-controller` pods first.
* If DNS records aren’t created/updated → check `external-dns` pods.

---

## 6) Jenkins access (Helm-installed) (config)

### 6.1 Fetch Jenkins admin password (from chart secret mount)

```bash
kubectl exec --namespace ci -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo
```

**Expected output**: prints the password (do **not** paste it into public repo).

### 6.2 Port-forward Jenkins service locally

```bash
kubectl --namespace ci port-forward svc/jenkins 8080:8080
```

**Expected output (example)**

* `Forwarding from 127.0.0.1:8080 -> 8080`

### 6.3 URL reference

```bash
echo http://127.0.0.1:8080
```

### 6.4 Watch Jenkins pod come up (quick readiness check)

```bash
kubectl -n ci get pods -w
```

**Expected output**: `jenkins-0` becomes `Running`, `READY 2/2`.

### 6.5 Inspect Jenkins resources quickly

```bash
kubectl get pods,svc,ingress,pvc -n ci
```

**Expected output**: pod running, service present (typically on `8080`), PVC `Bound`.

---

## 7) Ingress / ALB / DNS validation (config + debug)

### 7.1 List ingresses (all namespaces)

```bash
kubectl get ingress -A
```

**Expected output (example)**: shows ingress with `CLASS alb`, `HOSTS jenkins.poc.<ROOT_DOMAIN>`, `ADDRESS <...>.elb.amazonaws.com`.

### 7.2 Deep inspect Jenkins ingress (most useful command here)

```bash
kubectl describe ingress jenkins -n ci
```

**Expected high-signal fields**

* Ingress Class, Address, Host
* ALB annotations (listen ports, scheme, target-type)
* Events like `SuccessfullyReconciled`

### 7.3 Check TargetGroupBinding objects (only if your setup creates them)

```bash
kubectl get targetgroupbinding -n ci
```

**Expected output**: list OR `No resources found in ci namespace.`

---

## 8) Metrics & resource usage (observability / debug)

### 8.1 Install/refresh Metrics Server (enables `kubectl top`)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Expected output (example)**: `deployment.apps/metrics-server configured` (or created)

### 8.2 Node and pod resource usage

```bash
kubectl top nodes
kubectl top pods -A
```

### 8.3 Remove Metrics Server (destroy/cleanup)

```bash
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 8.4 Verify Metrics Server is gone (optional)

```bash
kubectl get pods -n kube-system | grep metrics-server || true
kubectl api-resources | grep metrics.k8s.io || true
```

**Expected output**: empty (no results)

---

## 9) PoC discovery & lifecycle (ops)

### 9.1 Discover what PoCs exist (your convention)

```bash
helm list -A
kubectl get ns | grep '^poc-'
kubectl get ingress -A
```

### 9.2 Destroy a single PoC by ID (repo script)

```bash
POC_ID=<POC_ID> scripts/95_destroy_poc.sh
```

**Expected output (example)**

* If release exists: uninstall succeeds, namespace deleted
* If release does NOT exist: you may see `release: not found`, but namespace deletion may still succeed

---

## 10) Jenkins troubleshooting (explicit debug section)

Use these when Jenkins is stuck (Init), CrashLoopBackOff, or PVC/volume issues.

### 10.1 Pod status + node placement

```bash
kubectl get pods -n ci -o wide
```

### 10.2 Previous logs (when container restarted)

```bash
kubectl logs jenkins-0 -n ci -c jenkins --previous
```

**Expected output (common)**:

* `previous terminated container "jenkins" ... not found` (means it hasn’t restarted yet)

### 10.3 Previous logs for all containers

```bash
kubectl logs jenkins-0 -n ci --all-containers=true --previous
```

### 10.4 The single most important debug command (events + init + volume attach/mount)

```bash
kubectl describe pod jenkins-0 -n ci
```

### 10.5 Verify Jenkins PVC is bound

```bash
kubectl get pvc -n ci
```

**Expected output (example)**: `jenkins` PVC is `Bound`.

---

## 11) Jenkins cleanup / reinstall prep (operational)

### 11.1 Uninstall Jenkins release (safe cleanup)

```bash
helm uninstall jenkins -n ci || true
```

**Expected output (example)**:

* `release "jenkins" uninstalled` (or no hard failure due to `|| true`)

---

## 12) Destroy everything (platform teardown) — repo-level operations

### 12.1 Full teardown (Jenkins + add-ons + Terraform platform)

```bash
scripts/90_destroy_all.sh
```

**Expected output (example)**

* Jenkins uninstalled + `ci` namespace deleted
* Add-ons uninstalled (ALB controller, external-dns, EBS CSI)
* Terraform destroy begins (may prompt for `var.*` if not loaded via tfvars/env)

✅ **If you see repeated prompts:** Terraform variables aren’t being loaded from `.tfvars` / `-var-file` / env vars.

---

## 13) Cleanup leftover Terraform state bucket objects (debugging)

### 13.1 Remove all current objects (non-versioned cleanup)

```bash
aws s3 rm s3://$BUCKET --recursive
```

### 13.2 Delete versioned objects (Versions) and delete markers

```bash
BUCKET=<TF_STATE_BUCKET>

aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"

aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
```

**Expected output (common)**

* If you get `Invalid type for parameter Delete.Objects, value: None` → typically means **no versions** or **no delete markers** existed.

---

## 14) Cleanup Route53 hosted zone records (bulk delete non-NS/SOA)

⚠️ This deletes all records except `NS` and `SOA` in the given hosted zone. Double-check `<HZ_POC>` before running.

### 14.1 Build delete change batch

```bash
HZ=<HZ_POC>

aws route53 list-resource-record-sets --hosted-zone-id "$HZ" \
  --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']" --output json \
| jq '{Changes: map({Action:"DELETE", ResourceRecordSet:.})}' > /tmp/rr-delete.json
```

### 14.2 Apply deletion batch

```bash
aws route53 change-resource-record-sets --hosted-zone-id "$HZ" --change-batch file:///tmp/rr-delete.json
```

**Expected output (example)**: `ChangeInfo` JSON with `Status: PENDING` then eventually `INSYNC`.

---

## Quick “most useful” commands (config + debug)

* **Cluster access:** `aws eks update-kubeconfig ...` + `kubectl config use-context ...`
* **Jenkins admin password:** `kubectl exec ... cat /run/secrets/.../chart-admin-password`
* **Ingress truth source:** `kubectl describe ingress jenkins -n ci`
* **Add-ons health:** `kubectl get pods -n kube-system -l 'app.kubernetes.io/name in (...)'`
* **Resource pressure:** `kubectl top nodes` + `kubectl top pods -A` (needs metrics-server)
* **Best single Jenkins debug:** `kubectl describe pod jenkins-0 -n ci`

# Additional Debug Command Reference

## 1) Cluster & API health (first 2 minutes)

```bash
kubectl cluster-info
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
```

```bash
aws eks describe-cluster --name <CLUSTER_NAME> --region <AWS_REGION> \
  --query "cluster.{status:status,version:version,endpoint:endpoint,oidc:identity.oidc.issuer}"
```

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
```

---

## 2) Node + scheduling issues (why pods are Pending)

```bash
kubectl get nodes -o wide
kubectl describe node <NODE_NAME>
kubectl get pods -A --field-selector=status.phase=Pending
```

```bash
kubectl -n ci describe pod jenkins-0 | sed -n '/Events:/,$p'
```

---

## 3) Helm debugging (what exactly got deployed)

```bash
helm -n ci status jenkins
helm -n ci history jenkins
helm -n ci get values jenkins -a
helm -n ci get manifest jenkins > /tmp/jenkins-manifest.yaml
```

If uninstall/reinstall behaves weird:

```bash
helm -n ci list
kubectl get secret -n ci | grep sh.helm.release || true
```

---

## 4) Service routing (Ingress looks fine but app not reachable)

```bash
kubectl -n ci get svc jenkins -o wide
kubectl -n ci describe svc jenkins
kubectl -n ci get endpoints jenkins -o yaml
kubectl -n ci get endpointslice -l kubernetes.io/service-name=jenkins
```

Quick in-cluster test (DNS + HTTP):

```bash
kubectl -n ci run tmp-shell --rm -it --image=busybox:1.36 -- sh
# inside:
# nslookup jenkins
# wget -S -O- http://jenkins:8080 2>&1 | head
```

---

## 5) Ingress / ALB Controller deeper debugging

You already do `kubectl describe ingress`. Add these:

```bash
kubectl get ingressclass
kubectl -n kube-system get deploy aws-load-balancer-controller -o wide
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=200
kubectl -n kube-system get events --sort-by=.lastTimestamp | tail -n 50
```

See what it created in AWS (ALB + target groups):

```bash
aws elbv2 describe-load-balancers --region <AWS_REGION>
aws elbv2 describe-target-groups --region <AWS_REGION>
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN> --region <AWS_REGION>
```

---

## 6) ExternalDNS debugging (DNS not getting created/updated)

```bash
kubectl -n kube-system get deploy external-dns -o wide
kubectl -n kube-system describe deploy external-dns | sed -n '/Args:/,/Environment:/p'
kubectl -n kube-system logs deploy/external-dns --tail=200
```

Check Route53 changes are actually happening:

```bash
aws route53 list-resource-record-sets --hosted-zone-id <HZ_POC> --max-items 50
```

---

## 7) CoreDNS / cluster DNS issues (super common)

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=200
kubectl -n kube-system describe configmap coredns
```

---

## 8) Storage (PVC stuck Pending / volume mount errors)

```bash
kubectl get storageclass
kubectl -n ci get pvc -o wide
kubectl -n ci describe pvc <PVC_NAME>
kubectl get pv
```

EBS CSI specifics:

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver -o wide
kubectl -n kube-system logs -l app.kubernetes.io/component=csi-controller --tail=200
kubectl get csidrivers
```

---

## 9) IRSA / permissions (ALB controller / ExternalDNS / CSI failing silently)

Check service accounts + annotations:

```bash
kubectl -n kube-system get sa aws-load-balancer-controller -o yaml | sed -n '/annotations:/,/secrets:/p'
kubectl -n kube-system get sa external-dns -o yaml | sed -n '/annotations:/,/secrets:/p'
```

Confirm OIDC provider exists in AWS:

```bash
aws iam list-open-id-connect-providers
```

---

## 10) “What is running where” quick snapshots (great for screenshots + audits)

```bash
kubectl get ns
kubectl get pods -A -o wide
kubectl get svc -A
kubectl get ingress -A
kubectl get sa -A | head
```

---

## 11) Terraform “why destroy didn’t delete something”

```bash
terraform state list
terraform state show <RESOURCE_ADDRESS>
terraform output
terraform plan -refresh-only
```

---

## Refrence:
* `<AWS_REGION>` (example: `ap-south-1`)
* `<CLUSTER_NAME>` (example: `platform-dev-eks`)
* `<ROOT_DOMAIN>` (example: `rdhcloudlab.com`)
* `<HZ_ROOT>` = hosted zone id for `<ROOT_DOMAIN>` (example: `Z0XXXXXXXXXXXXX`)
* `<HZ_POC>` = hosted zone id for `poc.<ROOT_DOMAIN>` (example: `Z0YYYYYYYYYYYYY`)
* `<AWS_IAM_PRINCIPAL_ARN>` (example: `arn:aws:iam::<AWS_ACCOUNT_ID>:user/<USER>`)
* `<TF_STATE_BUCKET>` (example: `rdhlab-platform-tf-state-dev`)
* `<POC_ID>` (example: `github`)

> ✅ Tip: Keep a `.env.example` in repo (never commit real `.env`).
---

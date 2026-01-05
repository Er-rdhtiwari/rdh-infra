#!/usr/bin/env bash
set -euo pipefail

# Preserve any user-provided PoC vars so .env (which may have blank defaults) does not clobber them.
USER_POC_ID="${POC_ID-}"
USER_POC_HELM_REPO="${POC_HELM_REPO-}"
USER_POC_HELM_REPO_NAME="${POC_HELM_REPO_NAME-}"
USER_POC_HELM_CHART="${POC_HELM_CHART-}"
USER_POC_HELM_VERSION="${POC_HELM_VERSION-}"
USER_POC_HELM_EXTRA_ARGS="${POC_HELM_EXTRA_ARGS-}"
USER_POC_HELM_VALUES_FILES="${POC_HELM_VALUES_FILES-}"
USER_POC_NAMESPACE_PREFIX="${POC_NAMESPACE_PREFIX-}"

set -a
source .env
set +a

# Reapply user-provided PoC vars if set
[ -n "${USER_POC_ID}" ] && POC_ID="$USER_POC_ID"
[ -n "${USER_POC_HELM_REPO}" ] && POC_HELM_REPO="$USER_POC_HELM_REPO"
[ -n "${USER_POC_HELM_REPO_NAME}" ] && POC_HELM_REPO_NAME="$USER_POC_HELM_REPO_NAME"
[ -n "${USER_POC_HELM_CHART}" ] && POC_HELM_CHART="$USER_POC_HELM_CHART"
[ -n "${USER_POC_HELM_VERSION}" ] && POC_HELM_VERSION="$USER_POC_HELM_VERSION"
[ -n "${USER_POC_HELM_EXTRA_ARGS}" ] && POC_HELM_EXTRA_ARGS="$USER_POC_HELM_EXTRA_ARGS"
[ -n "${USER_POC_HELM_VALUES_FILES}" ] && POC_HELM_VALUES_FILES="$USER_POC_HELM_VALUES_FILES"
[ -n "${USER_POC_NAMESPACE_PREFIX}" ] && POC_NAMESPACE_PREFIX="$USER_POC_NAMESPACE_PREFIX"

: "${POC_ID:?set POC_ID}"
: "${POC_HELM_REPO:?set POC_HELM_REPO}"
: "${POC_HELM_REPO_NAME:?set POC_HELM_REPO_NAME}"
: "${POC_HELM_CHART:?set POC_HELM_CHART}"
: "${POC_HELM_VERSION:?set POC_HELM_VERSION}"
: "${POC_NAMESPACE_PREFIX:=poc}"

EXTRA_ARGS="${POC_HELM_EXTRA_ARGS:-}"
VALUES_FILES="${POC_HELM_VALUES_FILES:-}"

NS="${POC_NAMESPACE_PREFIX}-${POC_ID}"
HOST="${POC_ID}.poc.${ROOT_DOMAIN}"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF2 | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata: {name: ${NS}-quota, namespace: ${NS}}
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "20"
    persistentvolumeclaims: "5"
---
apiVersion: v1
kind: LimitRange
metadata: {name: ${NS}-limits, namespace: ${NS}}
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "200m"
      memory: "256Mi"
    type: Container
EOF2

helm repo add "$POC_HELM_REPO_NAME" "$POC_HELM_REPO"
helm repo update

cmd=(helm upgrade --install "${POC_ID}" "${POC_HELM_CHART}"
  --namespace "$NS" --create-namespace=false
  --version "${POC_HELM_VERSION}"
)

if [ -n "$VALUES_FILES" ]; then
  IFS=',' read -r -a files <<< "$VALUES_FILES"
  for f in "${files[@]}"; do
    cmd+=(-f "$f")
  done
fi

cmd+=(
  --set ingress.enabled=true
  --set ingress.className=alb
  --set ingress.hosts[0].host="${HOST}"
  --set ingress.hosts[0].paths[0].path="/"
  --set ingress.hosts[0].paths[0].pathType=Prefix
  --set ingress.annotations."alb\\.ingress\\.kubernetes\\.io/scheme"=internet-facing
  --set ingress.annotations."alb\\.ingress\\.kubernetes\\.io/target-type"=ip
)

if [ -n "$EXTRA_ARGS" ]; then
  # shellcheck disable=SC2206
  extra_split=($EXTRA_ARGS)
  cmd+=("${extra_split[@]}")
fi

"${cmd[@]}"

cat <<EOF
[ok] PoC deployed.
- POC_ID: ${POC_ID}
- Namespace: ${NS}
- Host: https://${HOST}
- Helm release: ${POC_ID} (repo ${POC_HELM_REPO_NAME}, chart ${POC_HELM_CHART}, version ${POC_HELM_VERSION})
- Extra args: ${EXTRA_ARGS:-<none>}

Quick checks:
  kubectl get pods -n ${NS}
  kubectl get ingress -n ${NS}
  kubectl describe ingress ${POC_ID} -n ${NS}
  kubectl get targetgroupbinding -n ${NS}
  dig +short ${HOST}
  curl -kI https://${HOST}

If ingress ADDRESS is empty, wait a minute and check ALB controller logs:
  kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=50
EOF

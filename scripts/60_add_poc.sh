#!/usr/bin/env bash
set -euo pipefail
source .env

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

VALUES_FLAGS=()
if [ -n "$VALUES_FILES" ]; then
  IFS=',' read -r -a files <<< "$VALUES_FILES"
  for f in "${files[@]}"; do
    VALUES_FLAGS+=(-f "$f")
  done
fi

helm upgrade --install "${POC_ID}" "${POC_HELM_CHART}" \
  --namespace "$NS" --create-namespace=false \
  --version "${POC_HELM_VERSION}" \
  "${VALUES_FLAGS[@]}" \
  --set ingress.enabled=true \
  --set ingress.className=alb \
  --set ingress.hosts[0].host="${HOST}" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --set ingress.annotations."alb\\.ingress\\.kubernetes\\.io/scheme"=internet-facing \
  --set ingress.annotations."alb\\.ingress\\.kubernetes\\.io/target-type"=ip \
  ${EXTRA_ARGS}

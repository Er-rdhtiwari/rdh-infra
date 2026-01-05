#!/usr/bin/env bash
set -euo pipefail

# Deploys the habitify repo (https://github.com/Er-rdhtiwari/habitify) using its Helm chart.
# Requirements:
# - IMAGE_REPO and IMAGE_TAG must point to a built/pushed habitify image (see repo README for docker build/push).
# - .env in repo root with ROOT_DOMAIN set.
# Optional overrides: POC_ID (default: habitify), POC_NAMESPACE_PREFIX (default: poc), HABITIFY_CHART_REPO (default: git clone).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Help/usage
usage() {
  cat <<'EOF'
Usage:
  ./add-poc/add_poc_habitify.sh IMAGE_REPO=<registry>/habitify IMAGE_TAG=<tag> [POC_ID=habitify] [POC_NAMESPACE_PREFIX=poc] [HABITIFY_CLONE_DIR=/tmp/habitify] [HABITIFY_GIT_URL=...] [HABITIFY_BUILD_IMAGE=true] [HABITIFY_PUSH_IMAGE=true]

Flags:
  -h, --help   Show this help and exit.

Notes:
  - Requires .env in repo root with ROOT_DOMAIN set.
  - Builds/pushes the image by default; disable with HABITIFY_BUILD_IMAGE=false or HABITIFY_PUSH_IMAGE=false.
EOF
}

# Parse CLI key=value overrides and help flag
USER_IMAGE_REPO=""; USER_IMAGE_TAG=""; USER_POC_ID=""; USER_POC_NS_PREFIX=""
USER_CLONE_DIR=""; USER_GIT_URL=""; USER_BUILD_IMAGE=""; USER_PUSH_IMAGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *=*)
      key="${1%%=*}"; val="${1#*=}"
      case "$key" in
        IMAGE_REPO) USER_IMAGE_REPO="$val" ;;
        IMAGE_TAG) USER_IMAGE_TAG="$val" ;;
        POC_ID) USER_POC_ID="$val" ;;
        POC_NAMESPACE_PREFIX) USER_POC_NS_PREFIX="$val" ;;
        HABITIFY_CLONE_DIR) USER_CLONE_DIR="$val" ;;
        HABITIFY_GIT_URL) USER_GIT_URL="$val" ;;
        HABITIFY_BUILD_IMAGE) USER_BUILD_IMAGE="$val" ;;
        HABITIFY_PUSH_IMAGE) USER_PUSH_IMAGE="$val" ;;
        *) echo "[warn] Ignoring unknown arg: $1" >&2 ;;
      esac
      shift ;;
    *) echo "[warn] Ignoring arg: $1" >&2; shift ;;
  esac
done

if [ ! -f .env ]; then
  cat >&2 <<'EOF'
[error] .env not found in repo root. Copy .env.example -> .env and set ROOT_DOMAIN.
To run:
  export IMAGE_REPO=<your-registry>/habitify
  export IMAGE_TAG=latest
  # optional: POC_ID=habitify POC_NAMESPACE_PREFIX=poc HABITIFY_CLONE_DIR=/tmp/habitify HABITIFY_GIT_URL=...
  ./add-poc/add_poc_habitify.sh
EOF
  exit 1
fi

# Load .env and export for envsubst if needed
set -a
source .env
set +a

# Reapply CLI overrides after sourcing .env
[ -n "$USER_IMAGE_REPO" ] && IMAGE_REPO="$USER_IMAGE_REPO"
[ -n "$USER_IMAGE_TAG" ] && IMAGE_TAG="$USER_IMAGE_TAG"
[ -n "$USER_POC_ID" ] && POC_ID="$USER_POC_ID"
[ -n "$USER_POC_NS_PREFIX" ] && POC_NAMESPACE_PREFIX="$USER_POC_NS_PREFIX"
[ -n "$USER_CLONE_DIR" ] && HABITIFY_CLONE_DIR="$USER_CLONE_DIR"
[ -n "$USER_GIT_URL" ] && HABITIFY_GIT_URL="$USER_GIT_URL"
[ -n "$USER_BUILD_IMAGE" ] && HABITIFY_BUILD_IMAGE="$USER_BUILD_IMAGE"
[ -n "$USER_PUSH_IMAGE" ] && HABITIFY_PUSH_IMAGE="$USER_PUSH_IMAGE"

if [ -z "${IMAGE_REPO:-}" ] || [ -z "${IMAGE_TAG:-}" ]; then
  cat >&2 <<'EOF'
[error] IMAGE_REPO and IMAGE_TAG are required.
Example:
  export IMAGE_REPO=<your-registry>/habitify
  export IMAGE_TAG=latest
  # optional: POC_ID=habitify POC_NAMESPACE_PREFIX=poc HABITIFY_CLONE_DIR=/tmp/habitify HABITIFY_GIT_URL=...
  ./add-poc/add_poc_habitify.sh
EOF
  exit 1
fi

: "${ROOT_DOMAIN:?set ROOT_DOMAIN in .env}"

POC_ID="${POC_ID:-habitify}"
POC_NAMESPACE_PREFIX="${POC_NAMESPACE_PREFIX:-poc}"
CLONE_DIR="${HABITIFY_CLONE_DIR:-/tmp/habitify}"
GIT_URL="${HABITIFY_GIT_URL:-https://github.com/Er-rdhtiwari/habitify.git}"
BUILD_IMAGE="${HABITIFY_BUILD_IMAGE:-true}"
PUSH_IMAGE="${HABITIFY_PUSH_IMAGE:-true}"

NS="${POC_NAMESPACE_PREFIX}-${POC_ID}"
HOST="${POC_ID}.poc.${ROOT_DOMAIN}"

echo "[info] Using POC_ID=${POC_ID}, namespace=${NS}, host=${HOST}"
echo "[info] Image: ${IMAGE_REPO}:${IMAGE_TAG}"

if [ -d "$CLONE_DIR/.git" ]; then
  echo "[info] Updating existing clone at $CLONE_DIR"
  git -C "$CLONE_DIR" pull --ff-only
else
  echo "[info] Cloning $GIT_URL to $CLONE_DIR"
  git clone --depth 1 "$GIT_URL" "$CLONE_DIR"
fi

CHART_PATH="${CLONE_DIR}/chart/habitify"
if [ ! -f "${CHART_PATH}/Chart.yaml" ]; then
  echo "[error] Chart.yaml not found at ${CHART_PATH}" >&2
  exit 1
fi

if [ "${BUILD_IMAGE}" = "true" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "[error] docker CLI not found; set HABITIFY_BUILD_IMAGE=false to skip build." >&2
    exit 1
  fi
  echo "[info] Building image ${IMAGE_REPO}:${IMAGE_TAG} from ${CLONE_DIR}/Dockerfile"
  docker build -t "${IMAGE_REPO}:${IMAGE_TAG}" "${CLONE_DIR}"
  if [ "${PUSH_IMAGE}" = "true" ]; then
    echo "[info] Pushing image ${IMAGE_REPO}:${IMAGE_TAG}"
    docker push "${IMAGE_REPO}:${IMAGE_TAG}"
  else
    echo "[info] Skipping push (HABITIFY_PUSH_IMAGE=${PUSH_IMAGE})"
  fi
else
  echo "[info] Skipping image build (HABITIFY_BUILD_IMAGE=${BUILD_IMAGE})"
fi

echo "[info] Ensuring namespace ${NS}"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "[info] Applying quota/limits in ${NS}"
cat <<EOF | kubectl apply -f -
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
EOF

helm_cmd="helm upgrade --install ${POC_ID} ${CHART_PATH} --namespace ${NS} --create-namespace=false"
helm_cmd+=" --set image.repository=${IMAGE_REPO}"
helm_cmd+=" --set image.tag=${IMAGE_TAG}"
helm_cmd+=" --set ingress.enabled=true"
helm_cmd+=" --set ingress.className=alb"
helm_cmd+=" --set ingress.hosts[0].host=${HOST}"
helm_cmd+=" --set ingress.hosts[0].paths[0].path=/"
helm_cmd+=" --set ingress.hosts[0].paths[0].pathType=Prefix"
helm_cmd+=" --set ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme=internet-facing"
helm_cmd+=" --set ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type=ip"

echo "[info] Running helm command:"
echo " $helm_cmd"
eval "$helm_cmd"

cat <<EOF
[ok] Habitify PoC deployed.
- POC_ID: ${POC_ID}
- Namespace: ${NS}
- Host: https://${HOST}
- Helm chart: ${CHART_PATH}
- Image: ${IMAGE_REPO}:${IMAGE_TAG}

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

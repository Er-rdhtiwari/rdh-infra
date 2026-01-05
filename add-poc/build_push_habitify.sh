#!/usr/bin/env bash
set -euo pipefail

# Builds and pushes the habitify image from https://github.com/Er-rdhtiwari/habitify.
# Usage:
#   ./add-poc/build_push_habitify.sh IMAGE_REPO=<registry>/habitify IMAGE_TAG=<tag> [HABITIFY_CLONE_DIR=/tmp/habitify] [HABITIFY_GIT_URL=...]
# Flags:
#   -h, --help   Show this help and exit.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  cat <<'EOF'
Build & push habitify image
Usage:
  ./add-poc/build_push_habitify.sh IMAGE_REPO=<registry>/habitify IMAGE_TAG=<tag> [HABITIFY_CLONE_DIR=/tmp/habitify] [HABITIFY_GIT_URL=https://github.com/Er-rdhtiwari/habitify.git]

Examples:
  ./add-poc/build_push_habitify.sh IMAGE_REPO=123456789012.dkr.ecr.ap-south-1.amazonaws.com/habitify IMAGE_TAG=latest

Requires:
  - docker CLI installed and logged in to the target registry
EOF
}

# Parse key=value args and help
IMAGE_REPO="${IMAGE_REPO:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
HABITIFY_CLONE_DIR="${HABITIFY_CLONE_DIR:-/tmp/habitify}"
HABITIFY_GIT_URL="${HABITIFY_GIT_URL:-https://github.com/Er-rdhtiwari/habitify.git}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *=*)
      key="${1%%=*}"; val="${1#*=}"
      case "$key" in
        IMAGE_REPO) IMAGE_REPO="$val" ;;
        IMAGE_TAG) IMAGE_TAG="$val" ;;
        HABITIFY_CLONE_DIR) HABITIFY_CLONE_DIR="$val" ;;
        HABITIFY_GIT_URL) HABITIFY_GIT_URL="$val" ;;
        *) echo "[warn] Ignoring unknown arg: $1" >&2 ;;
      esac
      shift ;;
    *) echo "[warn] Ignoring arg: $1" >&2; shift ;;
  esac
done

if [ -z "$IMAGE_REPO" ] || [ -z "$IMAGE_TAG" ]; then
  echo "[error] IMAGE_REPO and IMAGE_TAG are required."
  usage
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[error] docker CLI not found; install docker and login to your registry." >&2
  exit 1
fi

echo "[info] IMAGE_REPO=${IMAGE_REPO}"
echo "[info] IMAGE_TAG=${IMAGE_TAG}"
echo "[info] CLONE_DIR=${HABITIFY_CLONE_DIR}"
echo "[info] GIT_URL=${HABITIFY_GIT_URL}"

if [ -d "$HABITIFY_CLONE_DIR/.git" ]; then
  echo "[info] Updating existing clone at $HABITIFY_CLONE_DIR"
  git -C "$HABITIFY_CLONE_DIR" pull --ff-only
else
  echo "[info] Cloning $HABITIFY_GIT_URL to $HABITIFY_CLONE_DIR"
  git clone --depth 1 "$HABITIFY_GIT_URL" "$HABITIFY_CLONE_DIR"
fi

if [ ! -f "$HABITIFY_CLONE_DIR/Dockerfile" ]; then
  echo "[error] Dockerfile not found in $HABITIFY_CLONE_DIR" >&2
  exit 1
fi

echo "[info] Building image ${IMAGE_REPO}:${IMAGE_TAG}"
docker build -t "${IMAGE_REPO}:${IMAGE_TAG}" "$HABITIFY_CLONE_DIR"

echo "[info] Pushing image ${IMAGE_REPO}:${IMAGE_TAG}"
docker push "${IMAGE_REPO}:${IMAGE_TAG}"

cat <<EOF
[ok] Habitify image built and pushed.
- Image: ${IMAGE_REPO}:${IMAGE_TAG}
- Source: ${HABITIFY_GIT_URL} (cloned at ${HABITIFY_CLONE_DIR})

Next deploy:
  ./add-poc/add_poc_habitify.sh IMAGE_REPO=${IMAGE_REPO} IMAGE_TAG=${IMAGE_TAG}
EOF

#!/usr/bin/env bash
# Build the image, load it into a local kind cluster, deploy, and verify.
#   ./scripts/k8s_deploy.sh [tag]          deploy (creates the cluster if needed)
#   ./scripts/k8s_deploy.sh --rollback     undo the last rollout
set -Eeuo pipefail
cd "$(dirname "$0")/.."
CLUSTER=payflow; NS=payflow; DEPLOY=payflow-api
for c in kind kubectl docker; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done

if [[ "${1:-}" == "--rollback" ]]; then
  kubectl -n "$NS" rollout undo deploy/"$DEPLOY"
  kubectl -n "$NS" rollout status deploy/"$DEPLOY" --timeout=120s
  exit 0
fi

TAG="${1:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"
IMAGE="payflow-api:$TAG"

kind get clusters | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --config k8s/kind-config.yaml

echo ">> build $IMAGE"
docker build --build-arg APP_VERSION="$TAG" -t "$IMAGE" .
echo ">> load image into kind nodes"
kind load docker-image "$IMAGE" --name "$CLUSTER"

echo ">> apply manifests"
kubectl apply -k k8s/
kubectl -n "$NS" set image deploy/"$DEPLOY" api="$IMAGE"
kubectl -n "$NS" annotate deploy/"$DEPLOY" kubernetes.io/change-cause="deploy $IMAGE" --overwrite
kubectl -n "$NS" rollout status deploy/"$DEPLOY" --timeout=180s

echo ">> verify"
kubectl -n "$NS" get pods -o wide
./scripts/healthcheck.sh http://localhost:30080 15 2
./scripts/smoke_test.sh http://localhost:30080
version=$(curl -fsS localhost:30080/health | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
[[ "$version" == "$TAG" ]] || { echo "expected version $TAG, got $version" >&2; exit 1; }
echo ">> $IMAGE is live"
kubectl -n "$NS" rollout history deploy/"$DEPLOY"

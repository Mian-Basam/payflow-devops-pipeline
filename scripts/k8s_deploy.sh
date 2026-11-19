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
# Render the manifests with the real image and apply once, so each deploy is exactly one
# rollout revision (apply + "set image" made two, and "rollout undo" went back to the
# placeholder image payflow-api:local, which does not exist).
kubectl kustomize k8s/ | sed "s#image: payflow-api:local#image: $IMAGE#" | kubectl apply -f -
kubectl -n "$NS" annotate deploy/"$DEPLOY" kubernetes.io/change-cause="deploy $IMAGE" --overwrite
kubectl -n "$NS" rollout status deploy/"$DEPLOY" --timeout=180s

echo ">> verify"
kubectl -n "$NS" get pods -o wide
./scripts/healthcheck.sh http://localhost:30080 15 2
./scripts/smoke_test.sh http://localhost:30080
# Old pods keep answering for a few seconds while they terminate (preStop) and kube-proxy
# updates its rules, so give the Service up to 30s to report the new version.
for _ in $(seq 30); do
  version=$(curl -fsS localhost:30080/health | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
  [[ "$version" == "$TAG" ]] && break
  sleep 1
done
[[ "$version" == "$TAG" ]] || { echo "expected version $TAG, got $version" >&2; exit 1; }
echo ">> $IMAGE is live"
kubectl -n "$NS" rollout history deploy/"$DEPLOY"

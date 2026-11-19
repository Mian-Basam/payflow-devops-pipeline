#!/usr/bin/env bash
# Zero-surprise deploy of the PayFlow container on a single Linux host.
#
#   ./scripts/deploy.sh <image:tag>
#
# 1. pulls/uses the new image
# 2. starts it on a staging port next to the running one
# 3. health-checks it
# 4. swaps it onto the live port; if the swap fails health checks,
#    the previous image is restored automatically (rollback)
set -Eeuo pipefail

IMAGE="${1:?usage: deploy.sh <image:tag>}"
NAME="${APP_NAME:-payflow-api}"
LIVE_PORT="${LIVE_PORT:-8000}"
STAGE_PORT="${STAGE_PORT:-8001}"
STATE_DIR="${STATE_DIR:-/var/lib/payflow}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '%s [deploy] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

mkdir -p "$STATE_DIR"
PREV_IMAGE="$(cat "$STATE_DIR/current_image" 2>/dev/null || true)"

run_container() {  # name image port
  docker rm -f "$1" >/dev/null 2>&1 || true
  docker run -d --name "$1" --restart unless-stopped \
    -p "$3:8000" -e APP_VERSION="${2##*:}" "$2" >/dev/null
}

rollback() {
  [[ -n "$PREV_IMAGE" ]] || die "no previous image recorded, cannot roll back"
  log "rolling back to $PREV_IMAGE"
  run_container "$NAME" "$PREV_IMAGE" "$LIVE_PORT"
  "$SCRIPT_DIR/healthcheck.sh" "http://localhost:$LIVE_PORT" \
    || die "rollback also unhealthy - escalate to on-call"
  log "rollback complete"
}

log "deploying $IMAGE (previous: ${PREV_IMAGE:-none})"
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"

log "starting canary on :$STAGE_PORT"
run_container "$NAME-canary" "$IMAGE" "$STAGE_PORT"
if ! "$SCRIPT_DIR/healthcheck.sh" "http://localhost:$STAGE_PORT"; then
  docker logs --tail 50 "$NAME-canary" || true
  docker rm -f "$NAME-canary" >/dev/null
  die "canary failed health checks; live version untouched"
fi
docker rm -f "$NAME-canary" >/dev/null

log "promoting to live port :$LIVE_PORT"
run_container "$NAME" "$IMAGE" "$LIVE_PORT"
if ! "$SCRIPT_DIR/healthcheck.sh" "http://localhost:$LIVE_PORT"; then
  log "live container unhealthy after swap"
  rollback
  exit 1
fi

echo "$IMAGE" > "$STATE_DIR/current_image"
echo "$(date -u +%FT%TZ) $IMAGE" >> "$STATE_DIR/deploy_history.log"
log "deploy OK: $IMAGE"

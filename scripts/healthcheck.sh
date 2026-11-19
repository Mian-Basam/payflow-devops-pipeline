#!/usr/bin/env bash
# Poll /health and /ready until both pass or we give up.
#   ./scripts/healthcheck.sh http://localhost:8000 [retries] [delay_s]
set -uo pipefail

BASE_URL="${1:?usage: healthcheck.sh <base_url> [retries] [delay]}"
RETRIES="${2:-10}"
DELAY="${3:-3}"

for ((i = 1; i <= RETRIES; i++)); do
  if curl -fsS --max-time 3 "$BASE_URL/health" >/dev/null \
     && curl -fsS --max-time 3 "$BASE_URL/ready" >/dev/null; then
    echo "[healthcheck] $BASE_URL healthy (attempt $i/$RETRIES)"
    exit 0
  fi
  echo "[healthcheck] $BASE_URL not ready (attempt $i/$RETRIES), retrying in ${DELAY}s"
  sleep "$DELAY"
done

echo "[healthcheck] $BASE_URL FAILED after $RETRIES attempts" >&2
exit 1

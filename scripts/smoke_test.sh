#!/usr/bin/env bash
# End-to-end check after a deploy: create, read and settle a transaction.
#   ./scripts/smoke_test.sh http://localhost:8080
set -Eeuo pipefail
BASE="${1:-http://localhost:8080}"

id=$(curl -fsS -X POST "$BASE/api/v1/transactions" \
  -H 'Content-Type: application/json' -d '{"amount": 1500, "currency": "PKR"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
echo "created transaction $id"

curl -fsS -X PATCH "$BASE/api/v1/transactions/$id" \
  -H 'Content-Type: application/json' -d '{"status": "settled"}' >/dev/null

status=$(curl -fsS "$BASE/api/v1/transactions/$id" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
[[ "$status" == "settled" ]] || { echo "expected settled, got $status" >&2; exit 1; }
echo "smoke test passed"

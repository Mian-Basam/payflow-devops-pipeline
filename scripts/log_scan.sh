#!/usr/bin/env bash
# Summarise errors in the app's JSON logs (from a file or `docker logs`).
#   ./scripts/log_scan.sh app.log
#   docker logs payflow-api 2>&1 | ./scripts/log_scan.sh -
set -Eeuo pipefail
SRC="${1:--}"

python3 - "$SRC" <<'PY'
import collections, json, sys
src = sys.argv[1]
fh = sys.stdin if src == "-" else open(src)
levels, status, errors, bad = collections.Counter(), collections.Counter(), [], 0
for line in fh:
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        rec = json.loads(line)
    except json.JSONDecodeError:
        bad += 1
        continue
    levels[rec.get("level", "?")] += 1
    if "status" in rec:
        status[str(rec["status"])[0] + "xx"] += 1
    if rec.get("level") == "ERROR":
        errors.append(rec)
print("log levels :", dict(levels))
print("http status:", dict(status))
print("unparsable :", bad)
for e in errors[-5:]:
    print("  ERROR", e.get("ts"), e.get("method"), e.get("path"), e.get("status"))
sys.exit(1 if errors else 0)
PY

#!/usr/bin/env bash
# Quick Linux server triage: the first things to check when a box misbehaves.
#   ./scripts/server_health.sh [disk_warn_pct] [dns_name]
set -uo pipefail

DISK_WARN="${1:-85}"
DNS_NAME="${2:-github.com}"
status=0

section() { printf '\n== %s ==\n' "$1"; }

section "Host"
echo "hostname: $(hostname)  kernel: $(uname -r)  uptime: $(uptime -p 2>/dev/null || uptime)"

section "Load / CPU"
read -r l1 l5 l15 _ < /proc/loadavg
cores=$(nproc)
echo "load avg: $l1 $l5 $l15 (cores: $cores)"
if awk -v l="$l5" -v c="$cores" 'BEGIN{exit !(l > c)}'; then
  echo "WARN: 5-min load is above core count"; status=1
fi

section "Memory"
free -h | sed -n '1,2p'

section "Disk"
while read -r fs use mnt; do
  pct=${use%\%}
  flag=""
  if (( pct >= DISK_WARN )); then flag="  <-- WARN"; status=1; fi
  printf '%-30s %4s  %s%s\n' "$fs" "$use" "$mnt" "$flag"
done < <(df -P -x tmpfs -x devtmpfs -x overlay 2>/dev/null | awk 'NR>1 {print $1, $5, $6}')

section "Listening TCP ports"
if command -v ss >/dev/null; then
  ss -ltnH 2>/dev/null | awk '{print $4}' | sort -u
else
  echo "(ss not installed)"
fi

section "Network / DNS"
echo "default route: $(ip route show default 2>/dev/null | head -1 || echo n/a)"
if getent hosts "$DNS_NAME" >/dev/null; then
  echo "DNS OK: $DNS_NAME -> $(getent hosts "$DNS_NAME" | awk '{print $1}' | head -1)"
else
  echo "WARN: cannot resolve $DNS_NAME (check /etc/resolv.conf)"; status=1
fi

section "Containers"
if command -v docker >/dev/null; then
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || echo "(docker not reachable)"
else
  echo "(docker not installed)"
fi

echo
(( status == 0 )) && echo "RESULT: healthy" || echo "RESULT: warnings found"
exit "$status"

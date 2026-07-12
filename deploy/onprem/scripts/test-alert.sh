#!/usr/bin/env bash
# Fires a canonical test alert through the runner's /ingest and reports the
# verdict (created / duplicate / suppressed). Safe: it is a normal alert with
# type "maintenance" and source "test-alert" — resolve it in the app after.
set -euo pipefail
cd "$(dirname "$0")/.."

SECRET=$(grep -E '^WORKER_SHARED_SECRET=' .env | cut -d= -f2-)
[[ -n "$SECRET" ]] || { echo "WORKER_SHARED_SECRET missing from .env"; exit 1; }

FACTORY="${1:-Usine A}"
PAYLOAD=$(cat <<EOF
{
  "factory": "${FACTORY}",
  "line": 1,
  "station": 1,
  "machine": "TEST-RIG",
  "metric": "installer_selftest",
  "value": 1,
  "severity": "normal",
  "type": "maintenance",
  "description": "Installer test alert — safe to resolve",
  "source": "test-alert"
}
EOF
)

echo "POSTing test alert for factory \"${FACTORY}\"…"
RESULT=$(docker compose exec -T worker-runner sh -c \
  "wget -qO- --timeout=10 --header 'Content-Type: application/json' \
   --header 'Authorization: Bearer ${SECRET}' \
   --post-data '$(echo "$PAYLOAD" | tr -d '\n')' http://127.0.0.1:8787/ingest")
echo "runner verdict: ${RESULT}"

case "$RESULT" in
  *'"status":"created"'*) echo "SUCCESS — alert created; it should appear on supervisor dashboards now." ;;
  *'"status":"duplicate"'*) echo "DEDUPED — an identical test alert exists within the dedup window (that means ingestion works)." ;;
  *) echo "UNEXPECTED — inspect: docker compose logs --tail 50 worker-runner"; exit 1 ;;
esac

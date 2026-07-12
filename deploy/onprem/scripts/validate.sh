#!/usr/bin/env bash
# Setup validation: every service up, healthy and answering.
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
check() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  \033[1;32mOK\033[0m   %s\n' "$name"
  else
    printf '  \033[1;31mFAIL\033[0m %s\n' "$name"
    FAIL=1
  fi
}

curl_in() { # container-side curl via a throwaway container on the compose network
  docker compose exec -T worker-runner wget -qO- --timeout=5 "$1"
}

echo "SIAS on-prem validation:"
check "docker compose services running" bash -c '[ -z "$(docker compose ps --status exited --status dead -q)" ] && [ -n "$(docker compose ps -q)" ]'
check "PocketBase /api/health"          bash -c 'docker compose exec -T pocketbase wget -qO- --timeout=5 http://127.0.0.1:8090/api/health'
check "worker-runner /health"           curl_in "http://127.0.0.1:8787/health"
check "worker-runner /ready (PB reachable)" curl_in "http://127.0.0.1:8787/ready"
check "edge-gateway /health"            bash -c 'docker compose exec -T edge-gateway wget -qO- --timeout=5 http://127.0.0.1:8788/health'

echo
echo "licence status:"
curl_in "http://127.0.0.1:8787/license-status" 2>/dev/null | head -c 600 || echo "  (worker-runner not answering)"
echo

if [[ "$FAIL" -ne 0 ]]; then
  echo "One or more checks FAILED. Inspect with: docker compose logs --tail 100 <service>"
  exit 1
fi
echo "All checks passed."

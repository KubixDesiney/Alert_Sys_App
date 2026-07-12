#!/usr/bin/env bash
# Roll back to the state captured by the last scripts/update.sh run.
# Restores compose files + .env (i.e. the previous pinned versions) and
# re-deploys. Data (pb_data) is NOT touched — use restore.sh for data.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d .update-rollback ]] || { echo "no rollback point (.update-rollback/) found"; exit 1; }

echo "restoring pinned configuration from .update-rollback/…"
cp .update-rollback/.env .env 2>/dev/null || true
cp .update-rollback/docker-compose.yml docker-compose.yml
cp .update-rollback/docker-compose.prod.yml docker-compose.prod.yml 2>/dev/null || true
cp .update-rollback/Caddyfile Caddyfile 2>/dev/null || true
[[ -f .update-rollback/gateway.config.json ]] && cp .update-rollback/gateway.config.json gateway.config.json

echo "rebuilding & redeploying the previous release…"
docker compose -f docker-compose.yml -f docker-compose.prod.yml build --pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

sleep 8
./scripts/validate.sh && echo "rollback complete."

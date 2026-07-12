#!/usr/bin/env bash
# Update to a new pinned release, keeping a rollback point.
# Usage: update.sh [new-SIAS_TAG]     (no arg = rebuild current tag, e.g. after git pull)
set -euo pipefail
cd "$(dirname "$0")/.."

NEW_TAG="${1:-}"

echo "[1/4] snapshotting rollback point (.update-rollback/)…"
mkdir -p .update-rollback
cp .env docker-compose.yml docker-compose.prod.yml Caddyfile .update-rollback/ 2>/dev/null || true
[[ -f gateway.config.json ]] && cp gateway.config.json .update-rollback/
docker compose images > .update-rollback/images.txt || true

echo "[2/4] taking a pre-update backup…"
./scripts/backup.sh ./backups-export/pre-update || echo "WARN: backup failed — continue at your own risk"

if [[ -n "$NEW_TAG" ]]; then
  echo "[3/4] bumping SIAS_TAG -> $NEW_TAG"
  sed -i "s|^SIAS_TAG=.*|SIAS_TAG=$NEW_TAG|" .env
fi

echo "[3/4] pulling pinned base images + rebuilding local images…"
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull --ignore-buildable
docker compose -f docker-compose.yml -f docker-compose.prod.yml build --pull

echo "[4/4] rolling the stack…"
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

sleep 8
if ./scripts/validate.sh; then
  echo "update complete."
else
  echo "UPDATE VALIDATION FAILED — roll back with: ./scripts/rollback.sh"
  exit 1
fi

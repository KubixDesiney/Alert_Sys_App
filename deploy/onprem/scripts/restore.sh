#!/usr/bin/env bash
# Restore command.
#   restore.sh <pb_data-*.tar.gz>        full PocketBase restore (authoritative)
#   restore.sh <sias-backup-*.json.gz>   JSON collection restore (upsert via API)
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="${1:-}"
[[ -n "$FILE" && -f "$FILE" ]] || { echo "usage: restore.sh <backup file>"; exit 1; }

case "$FILE" in
  *pb_data-*.tar.gz)
    echo "FULL RESTORE from $FILE — PocketBase will be stopped."
    read -r -p "This REPLACES the current database. Continue? [y/N] " ok
    [[ "$ok" == "y" || "$ok" == "Y" ]] || exit 1
    docker compose stop pocketbase
    docker compose cp "$FILE" pocketbase:/tmp/restore.tar.gz 2>/dev/null || {
      # container stopped -> use a helper container on the volume
      VOL=$(docker volume ls -q | grep -E '(^|_)pb_data$' | head -1)
      [[ -n "$VOL" ]] || { echo "pb_data volume not found"; exit 1; }
      docker run --rm -v "$VOL":/pb_data -v "$(cd "$(dirname "$FILE")" && pwd)":/host alpine:3.20 \
        sh -c "rm -rf /pb_data/* && tar xzf /host/$(basename "$FILE") -C /pb_data"
    }
    docker compose start pocketbase
    echo "restore complete; validating…"
    ./scripts/validate.sh
    ;;
  *sias-backup-*.json.gz)
    echo "JSON collection restore from $FILE (upsert through the PocketBase API)…"
    BASENAME=$(basename "$FILE")
    docker compose cp "$FILE" "worker-runner:/tmp/$BASENAME"
    docker compose exec -T worker-runner node --input-type=module -e "
import { PocketBaseStore } from '/app/worker-runner/store.mjs';
import { restoreBackup } from '/app/worker-runner/backup.mjs';
const store = new PocketBaseStore(process.env.PB_URL, process.env.PB_TOKEN);
const out = await restoreBackup(store, '/tmp/$BASENAME');
console.log(JSON.stringify(out));
"
    ;;
  *)
    echo "unrecognized backup file: $FILE"; exit 1 ;;
esac

#!/usr/bin/env bash
# Manual backup, in addition to the runner's nightly automatic snapshots.
#  1. JSON snapshot of every collection (runner backup module) -> backups volume
#  2. Raw pb_data tarball (PocketBase = SQLite dir; this is the full restore)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-./backups-export}"
mkdir -p "$OUT_DIR"
STAMP=$(date -u +%Y-%m-%dT%H-%M-%S)

echo "[1/3] JSON snapshot via worker-runner…"
docker compose exec -T worker-runner node --input-type=module -e "
import { PocketBaseStore } from '/app/worker-runner/store.mjs';
import { runBackup } from '/app/worker-runner/backup.mjs';
const store = new PocketBaseStore(process.env.PB_URL, process.env.PB_TOKEN);
const out = await runBackup(store, process.env.BACKUP_DIR || '/backups', { keep: 9999 });
console.log(JSON.stringify(out.counts));
"

echo "[2/3] copying JSON snapshots out of the backups volume…"
docker compose cp worker-runner:/backups/. "$OUT_DIR/" >/dev/null

echo "[3/3] raw pb_data tarball…"
docker compose exec -T pocketbase sh -c 'cd /pb_data && tar czf - .' > "$OUT_DIR/pb_data-$STAMP.tar.gz"

echo "backup complete -> $OUT_DIR"
ls -lh "$OUT_DIR" | tail -5

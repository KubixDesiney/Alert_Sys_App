// Local backups: nightly gzip'd JSON snapshot of every operational collection
// into BACKUP_DIR (a mounted volume), with pruning. `restoreBackup` is the
// counterpart used by deploy/onprem/scripts/restore.sh.
//
// PocketBase itself is a single SQLite directory, so the volume copy is the
// primary backup; these JSON snapshots add a storage-engine-independent,
// human-inspectable second layer (and power the retention archive).
import { gzipSync, gunzipSync } from 'node:zlib';
import { mkdirSync, writeFileSync, readFileSync, readdirSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

export const DEFAULT_COLLECTIONS = [
  'alerts', 'users', 'notifications', 'escalation_settings', 'audit_logs',
];

function stamp(now) {
  return new Date(now).toISOString().replace(/[:.]/g, '-');
}

export async function runBackup(store, dir, {
  collections = DEFAULT_COLLECTIONS,
  keep = 14,
  now = Date.now(),
  audit = async () => {},
} = {}) {
  mkdirSync(dir, { recursive: true });
  const data = { createdAt: new Date(now).toISOString(), collections: {} };
  const counts = {};
  for (const name of collections) {
    try {
      const rows = await store.listCollection(name);
      data.collections[name] = rows;
      counts[name] = rows.length;
    } catch (err) {
      data.collections[name] = [];
      counts[name] = `error: ${(err && err.message) || err}`;
    }
  }
  const file = join(dir, `sias-backup-${stamp(now)}.json.gz`);
  writeFileSync(file, gzipSync(JSON.stringify(data)));
  const pruned = pruneBackups(dir, keep);
  await audit('backup.created', { detail: `${file} ${JSON.stringify(counts)}` });
  return { file, counts, pruned };
}

/** Keep the newest `keep` backups, delete the rest. Returns deleted names. */
export function pruneBackups(dir, keep) {
  const files = readdirSync(dir)
    .filter((f) => f.startsWith('sias-backup-') && f.endsWith('.json.gz'))
    .sort()
    .reverse();
  const doomed = files.slice(Math.max(0, keep));
  for (const f of doomed) unlinkSync(join(dir, f));
  return doomed;
}

export function readBackup(file) {
  return JSON.parse(gunzipSync(readFileSync(file)).toString('utf8'));
}

/** Restores every collection in the snapshot through the store (upsert). */
export async function restoreBackup(store, file) {
  const data = readBackup(file);
  const restored = {};
  for (const [name, rows] of Object.entries(data.collections || {})) {
    if (!Array.isArray(rows)) continue;
    restored[name] = await store.restoreCollection(name, rows);
  }
  return { createdAt: data.createdAt, restored };
}

/** Retention-archive sink: appends expired records beside the backups. */
export function makeArchiveSink(dir, now = () => Date.now()) {
  return async (label, rows) => {
    mkdirSync(dir, { recursive: true });
    const file = join(dir, `${label}-${stamp(now())}.json.gz`);
    writeFileSync(file, gzipSync(JSON.stringify(rows)));
    return file;
  };
}

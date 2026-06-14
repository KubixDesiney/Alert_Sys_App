#!/usr/bin/env node
/**
 * Restore a Realtime Database backup JSON. DRY-RUN by default.
 *
 * Restores the whole tree, or just one path (e.g. only `/alerts`) — useful for
 * undoing an accidental delete without rolling back everything.
 *
 * Usage:
 *   SA_PATH=./sa.json FB_DB_URL=https://... node tool/restore_rtdb.mjs backups/rtdb-2026-06-14-02-00-00.json
 *     -> dry run, prints what WOULD be written
 *   ... node tool/restore_rtdb.mjs <file> --path=/alerts --apply
 *     -> OVERWRITES /alerts with the backup's /alerts
 *
 * WARNING: --apply uses set(), which REPLACES the target path. Take a fresh
 * backup first (node tool/backup_rtdb.mjs).
 */
import admin from 'firebase-admin';
import { readFileSync } from 'fs';

const saPath = process.env.SA_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS;
const dbUrl = process.env.FB_DB_URL;
const file = process.argv[2];
const APPLY = process.argv.includes('--apply');
const pathArg = process.argv.find((a) => a.startsWith('--path='));
const path = pathArg ? pathArg.slice('--path='.length) : '/';

if (!saPath || !dbUrl || !file) {
  console.error('Usage: SA_PATH=./sa.json FB_DB_URL=https://... node tool/restore_rtdb.mjs <backup.json> [--path=/alerts] [--apply]');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(readFileSync(saPath, 'utf8'))),
  databaseURL: dbUrl,
});

try {
  const data = JSON.parse(readFileSync(file, 'utf8'));
  const node = path === '/'
    ? data
    : path.split('/').filter(Boolean).reduce((o, k) => (o == null ? o : o[k]), data);

  const preview = JSON.stringify(node ?? null).slice(0, 240);
  console.log(`Restore source : ${file}`);
  console.log(`Target path    : ${path}`);
  console.log(`Preview        : ${preview}${preview.length >= 240 ? '…' : ''}`);

  if (!APPLY) {
    console.log('\nDRY RUN — nothing written. Re-run with --apply to OVERWRITE the target path.');
    process.exit(0);
  }
  await admin.database().ref(path).set(node === undefined ? null : node);
  console.log(`\nRestore applied to ${path}.`);
  process.exit(0);
} catch (e) {
  console.error('Restore failed:', e.message);
  process.exit(1);
}

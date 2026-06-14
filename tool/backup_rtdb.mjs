#!/usr/bin/env node
/**
 * Full Realtime Database backup to a timestamped JSON file, with retention.
 *
 * Read-only on the database. Run on a schedule (Windows Task Scheduler / cron)
 * or on demand. For a fully serverless option see cloudflare_backup_worker.js.
 *
 * Usage:
 *   SA_PATH="C:\\path\\service-account.json" ^
 *   FB_DB_URL="https://<project>-default-rtdb.firebaseio.com" ^
 *   node tool/backup_rtdb.mjs
 *
 * Env:
 *   SA_PATH / GOOGLE_APPLICATION_CREDENTIALS  service-account JSON (required)
 *   FB_DB_URL                                  database URL (required)
 *   BACKUP_DIR   destination folder            (default: backups)
 *   BACKUP_KEEP  how many backups to retain    (default: 30)
 */
import admin from 'firebase-admin';
import {
  readFileSync, writeFileSync, mkdirSync, readdirSync, unlinkSync,
} from 'fs';
import { join } from 'path';

const saPath = process.env.SA_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS;
const dbUrl = process.env.FB_DB_URL;
const dir = process.env.BACKUP_DIR || 'backups';
const keep = Number(process.env.BACKUP_KEEP || 30);

if (!saPath || !dbUrl) {
  console.error('Usage: SA_PATH=./sa.json FB_DB_URL=https://<proj>-default-rtdb.firebaseio.com node tool/backup_rtdb.mjs');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(readFileSync(saPath, 'utf8'))),
  databaseURL: dbUrl,
});

const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
const file = join(dir, `rtdb-${stamp}.json`);

try {
  mkdirSync(dir, { recursive: true });
  const snap = await admin.database().ref('/').get();
  const data = snap.exists() ? snap.val() : {};
  const json = JSON.stringify(data);
  writeFileSync(file, json);
  console.log(`Backup written: ${file} (${(json.length / 1024 / 1024).toFixed(2)} MB)`);

  // Retention: keep the newest `keep`, delete the rest.
  const files = readdirSync(dir)
    .filter((f) => /^rtdb-.*\.json$/.test(f))
    .sort()
    .reverse();
  for (const f of files.slice(keep)) {
    unlinkSync(join(dir, f));
    console.log('pruned', f);
  }
  process.exit(0);
} catch (e) {
  console.error('Backup failed:', e.message);
  process.exit(1);
}

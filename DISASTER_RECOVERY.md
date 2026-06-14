# Disaster recovery & reliability

How Smart Industrial Alert protects a customer's data and keeps running through
failures. One isolated instance per company (see PROVISIONING.md), so a disaster
in one company's project never touches another's.

## Objectives

| Metric | Target | How |
| --- | --- | --- |
| **RPO** (max data loss) | ≤ 24 h (≤ minutes with on-demand backup before risky ops) | Daily automated snapshot + ad-hoc backups |
| **RTO** (time to restore) | < 30 min | One-command restore from the latest snapshot |
| **Durability of backups** | 11 nines | Cloudflare R2 object storage (or your own GCS bucket) |

## What's protected

- **Realtime Database** (all operational data: alerts, users, shifts, hierarchy,
  AI model, audit log, config) — backed up in full.
- **Firebase Auth users** — managed by Google (export via Admin SDK if required
  for contractual portability).
- **Cloudflare Workers + rules + app** — code in git; redeploy is the recovery.
- **Built-in resilience already in the product:** offline-first cache
  (`OfflineDatabaseService`), a durable worker-trigger queue that retries on
  reconnect, distributed cron locks, and ETag-guarded push so nothing double-fires.

---

## Backups

### A. Serverless, automatic (recommended)
`cloudflare_backup_worker.js` exports the whole database to **Cloudflare R2**
every night and keeps the newest 30 snapshots — no machine to maintain.

```bash
npx wrangler r2 bucket create alertsys-backups
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.backup.toml
npx wrangler secret put FB_DB_URL --config wrangler.backup.toml
npx wrangler deploy --config wrangler.backup.toml
```
Verify: `GET https://<worker>/backup?key=<secret>` returns `{ ok: true, key, bytes }`.

### B. On-demand / scheduled on a machine
`tool/backup_rtdb.mjs` writes a timestamped JSON locally (Task Scheduler / cron),
with retention. **Always run this before any risky operation** (migrations,
bulk edits, the PII purge):

```powershell
$env:SA_PATH = "C:\path\service-account.json"
$env:FB_DB_URL = "https://<project>-default-rtdb.firebaseio.com"
node tool/backup_rtdb.mjs        # -> backups\rtdb-<timestamp>.json
```

---

## Restore

`tool/restore_rtdb.mjs` is **dry-run by default** and can restore the whole tree
or just one path (e.g. undo an accidental `/alerts` delete without rolling back
everything else).

```powershell
# 1) ALWAYS take a fresh backup first
node tool/backup_rtdb.mjs

# 2) Preview (writes nothing)
node tool/restore_rtdb.mjs backups\rtdb-2026-06-14-02-00-00.json --path=/alerts

# 3) Apply (OVERWRITES the target path)
node tool/restore_rtdb.mjs backups\rtdb-2026-06-14-02-00-00.json --path=/alerts --apply
```
(For an R2 snapshot, download it first: `npx wrangler r2 object get alertsys-backups/rtdb/<file>.json`.)

---

## Failure scenarios & response

| Scenario | Response |
| --- | --- |
| **Accidental delete / bad bulk write** | Restore just the affected path from the latest snapshot (`--path=/...`). |
| **Data corruption** | Identify the last good snapshot; restore the affected subtree. |
| **A worker is down** | App keeps working from cache + queue; redeploy the worker (`npm run deploy:ai` / `deploy:notify`). The 1-min cron is the durable fallback for missed triggers. |
| **Firebase / region outage** | Reads/writes degrade to the offline cache; queued actions flush on recovery. For a hard regional loss, stand up the project in another region and restore the latest snapshot. |
| **Account / key compromise** | Rotate the service-account key + worker secrets immediately, review `audit_log` and `security/*`, restore from a pre-incident snapshot if data was tampered. |
| **Ransomware / mass tamper** | Snapshots in R2 are separate from Firebase auth, so they survive a Firebase-side compromise. Restore from before the event. |

---

## Monitoring & alerting

- **Cron health** is already written to `workers/health/lastRun` every minute and
  surfaced in SuperAdmin → Logs (NOMINAL / DEGRADED / STALLED).
- **Client errors** flow to `bugs/client`; security events to `security/*`.
- **Add an external uptime check** (e.g. a 5-min cron hitting the AI worker
  `/config` and the notify worker `/config`) so you're paged if an edge goes dark
  independently of the app.
- **Watch:** cron freshness > 10 min, a spike in `bugs/client`, backup worker
  errors, and the continuous-learning accuracy ledger drifting.

---

## Test your DR (do this quarterly)

1. Trigger a manual backup; confirm a new object lands in R2.
2. Restore the latest snapshot into a **throwaway** Firebase project.
3. Point a debug build at it and confirm sign-in + alerts load.
4. Time it — confirm you're inside the RTO. Record the result.

An untested backup is not a backup.

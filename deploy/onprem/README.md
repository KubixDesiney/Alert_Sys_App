# SIAS Edge — on-prem production installation

Air-gapped stack: **Caddy** (TLS + web hosting) · **PocketBase** (data/auth/realtime,
persistent volume) · **worker-runner** (assignment, escalation, ingestion, SSE fan-out,
retention, backups, audit, licence) · **edge-gateway** (read-only industrial input
adapters). No Firebase, no Cloudflare. Architecture: `../../ONPREM.md`.

## Install

Linux:
```bash
cd deploy/onprem
./install.sh
```

Windows (PowerShell, elevated not required if Docker Desktop runs):
```powershell
cd deploy\onprem
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer is idempotent. It: checks Docker + Compose v2, generates strong
secrets into `.env` (0600, never regenerated), creates `secrets/` and a minimal
`gateway.config.json` (with a generated HTTP API key), builds the pinned images,
starts the stack with the production override
(`docker-compose.prod.yml`: restart always, no-new-privileges, read-only rootfs,
memory/CPU limits, JSON log rotation) and runs `scripts/validate.sh`.

Post-install (one time):
1. `https://<SIA_HOST>/api/_/` → create the PocketBase superuser.
2. Settings → **Import collections** → paste `pocketbase/pb_schema.json`
   (the customer RBAC — see `pocketbase/RULES_PORT.md`).
3. Create the worker-runner service token → `.env` `PB_TOKEN=` →
   `docker compose up -d worker-runner`.
4. Provision the first `company_owner` account (they manage everyone else in-app).
5. Copy the Flutter web build into `./web`:
   `flutter build web --release --dart-define=SIAS_BACKEND=pocketbase --dart-define=SIAS_POCKETBASE_URL=https://<SIA_HOST>`
6. Licence: drop the vendor token at `secrets/license.sias` (+ `license_public.pem`),
   or set `LICENSE_SERVER_URL` in `.env`. Core alerting runs even unlicensed
   (safety floor); Industrial features gate on the plan.

## Day-2 commands (`scripts/`)

| Command | Purpose |
|---|---|
| `validate.sh` / `validate.ps1` | Health of every service + licence status; non-zero exit on failure |
| `test-alert.sh [factory]` / `test-alert.ps1` | Fires a canonical test alert through `/ingest` and reports the verdict |
| `backup.sh [outdir]` | Manual backup: JSON collection snapshot **and** raw `pb_data` tarball (nightly JSON snapshots also run automatically at 02:00, kept `BACKUP_KEEP`) |
| `restore.sh <file>` | `pb_data-*.tar.gz` = full DB restore (confirmed, stops PB); `sias-backup-*.json.gz` = per-collection API upsert |
| `update.sh [new-tag]` | Pre-update backup + rollback point, pull/build pinned images, redeploy, validate |
| `rollback.sh` | Restore the pre-update pinned configuration and redeploy (data untouched) |
| `encrypt-env.sh [decrypt]` | AES-256 (PBKDF2) at-rest encryption of `.env` |

Structured logs: every SIAS service logs JSON lines (`docker compose logs worker-runner`);
Docker's json-file driver rotates at 10 MB × 5 files. The worker-runner also keeps an
append-only audit trail in PocketBase `audit_logs` **and** `/backups/audit.jsonl`.

## Security notes
- Deployment secrets (`.env`, `secrets/`, TLS material) never enter PocketBase and are
  not reachable by any in-app role — including the company owner (verified by
  `worker_test/onprem_rbac.test.js`).
- One named account per human; no shared credentials. Vendor-support accounts are
  disabled by default, time-boxed and audited.
- The edge-gateway is read-only toward PLC/SCADA by construction (Modbus builder has
  no write function codes; OPC UA is subscribe-only).

## Air-gap notes
- Vendor the pinned images (`caddy:2.8.4`, `pocketbase:0.22.21`, `node:20-alpine`) into
  your internal registry and retag in the compose file.
- Use an internal CA, or Caddy's `tls internal`.
- Licensing offline: annual licence file at `secrets/license.sias`; no outbound
  connection is ever required (and none is attempted when the file is valid).

## Uninstall (preserves customer data)

```bash
cd deploy/onprem
./scripts/backup.sh ./final-backup     # belt and braces
docker compose down                    # stops + removes containers, KEEPS volumes
```

Your data stays in the named Docker volumes (`pb_data`, `backups`) and in
`./final-backup`. To remove SIAS **and destroy all data** (irreversible):
`docker compose down -v` and delete this directory. Do not run `-v` unless the
customer has confirmed the final backup is safe elsewhere.

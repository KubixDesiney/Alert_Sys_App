# On-premise / air-gapped deployment

Many industrial buyers cannot use cloud services on the plant network. This document is
the architecture and the **honest status** of running SIAS entirely on a customer's own
hardware. The runnable stack lives under `deploy/onprem/` (see its README for the
production install guide).

## Honest status (updated 2026-07-12)

The cloud product runs on Firebase (Auth + RTDB) and Cloudflare Workers. The on-prem
build replaces both. What is genuinely DONE, PARTIAL or NOT DONE:

**DONE**
- **Data layer wired into the app**: `lib/services/data/` (`DataStore`) now carries the
  core alert lifecycle — watch (PM/usine/supervisor), create, claim, resolve,
  suspend/return, critical + note, comments, pagination, audit. `AlertProvider` →
  `AlertActionsService`/`AlertStreamService` route through it. `SIAS_BACKEND=firebase`
  is a pure delegation to the existing services (parity pinned by tests);
  `SIAS_BACKEND=pocketbase` performs zero Firebase I/O on this path.
- **On-prem auth + RBAC**: `PocketBaseAuthService` (password sign-in, token refresh,
  local session expiry from the JWT, password change with forced re-auth, account
  disable, vendor-window grant/revoke, MFA-ready `MfaProvider` seam) and the customer
  role model `company_owner` / `production_manager` / `supervisor` / `vendor_support`
  (`onprem_roles.dart`). PocketBase API rules in `deploy/onprem/pocketbase/pb_schema.json`
  enforce it server-side — factory scoping, role self-escalation block, write-only
  connector secrets, append-only author-pinned audit log, vendor disabled-by-default +
  time-boxed. The rules are executable-tested (`worker_test/onprem_rbac.test.js`).
  The platform SuperAdmin stays a vendor-cloud concept; on-prem "root" is PocketBase's
  own `_superusers`.
- **worker-runner** (Node, `deploy/onprem/worker-runner/`): cloud-parity AI assignment
  (vendored scoring), escalation, **alert ingestion** (`POST /ingest`, canonical
  payload), **dedup + alert-storm protection** (per-signal window, per-source/global
  ceilings, single critical storm meta-alert), **lifecycle fan-out over LAN SSE**
  (`/events`, token + session gated, heartbeat) driven by a snapshot ChangeWatcher
  (new/critical/suspend/claim/resolve) with persisted notification rows for offline
  devices, **retention** (archive-then-delete terminal alerts, notification purge),
  **local backups** (nightly gzip JSON snapshots + prune; restore command),
  **append-only audit trail** (PocketBase + local JSONL), retry/backoff on every
  PocketBase call, `/health`, `/ready`, `/license-status`, structured JSON logs.
- **Edge Gateway** (`deploy/onprem/edge-gateway/`): modular **read-only** adapters —
  ESP32 HTTP, generic REST webhook, MQTT, OPC UA, Modbus TCP — all reduced to one
  canonical alert payload with configurable tag/register mapping, scaling and
  thresholds; API keys, token-bucket rate limiting, 32 KB payload cap; a bounded
  retrying forwarder into the runner (which owns dedup). The Modbus builder only knows
  read function codes (FC3/FC4) and OPC UA is subscribe-only, so writing to a PLC is
  structurally impossible. **Adapter logic is tested against simulated data only — no
  real PLC/OPC UA server/broker has been commissioned against it yet.**
- **Licensing** (`deploy/onprem/license/`): Ed25519-signed tokens whose payload is a
  hard whitelist (`companyId, plan, status, expiresAt, features, installationId,
  version, issuedAt`) — operational data cannot be smuggled in on either end; offline
  annual licence file for air-gapped plants; server validation with a 7/14-day cached
  grace window when unreachable; Standard vs Industrial feature flags (protocol
  adapters, forecaster, AI commander); validation runs inside the worker-runner.
  Deliberate policy: an expired licence never bricks core alerting (safety floor) —
  paid extras switch off and the state is surfaced on `/health`.
- **Production installer** (`deploy/onprem/`): Linux `install.sh` + Windows
  `install.ps1`, pinned image versions, health checks + restart policies, prod
  hardening override (read-only rootfs, no-new-privileges, resource limits, log
  rotation), generated secrets (0600) with optional AES-256 at-rest encryption,
  `validate` / `test-alert` / `backup` / `restore` / `update` / `rollback` commands,
  uninstall procedure that preserves customer data.

**PARTIAL / NOT DONE (be honest in sales conversations)**
- PocketBase reads in the Flutter app are **polled (5s)**, not realtime SSE, and the
  worker-runner SSE stream is not yet consumed by the Flutter client for auto-refresh.
- Collaborator/help/shift flows, voice claim and the SuperAdmin console still call
  Firebase services directly — on the PocketBase build those surfaces are not yet
  functional (v3 scope). The supervisor/PM core alert loop is.
- On-prem claim concurrency is last-write-wins (no RTDB-style transaction); a
  PocketBase hook or runner-side claim endpoint is the planned guard.
- Login UI still drives FirebaseAuth; `PocketBaseAuthService` is implemented and
  tested but the on-prem login screen wiring is not merged yet.
- The Firebase→PocketBase data migration script exists (`migrate_rtdb_to_pocketbase.mjs`)
  but has not been exercised against a production-size export.

## Cloud -> on-prem component map
| Cloud component | On-prem replacement | Status |
|-----------------|---------------------|--------|
| Firebase Auth | PocketBase auth + customer RBAC | service + rules done; login-screen wiring pending |
| Realtime Database | PocketBase (SQLite + REST; realtime later) | core alert lifecycle wired |
| Cloudflare Workers (cron + HTTP) | `worker-runner` Node service | done for assignment/escalation/ingest/fan-out/maintenance |
| FCM push | LAN SSE hub (`/events`) + persisted notification rows | done server-side; Flutter SSE client pending |
| SCADA/PLC ingest worker | Edge Gateway (5 read-only adapters) | done (simulated-data tested) |
| Firebase Hosting | Caddy static hosting | done |
| — | Privacy-preserving licensing | done |

## Data residency & security benefits (sell these)
- All data stays on the customer's hardware/network — no third-party processors.
- Deployment secrets never enter the database; no in-app role can read them.
- Backups are local files (nightly JSON snapshots + `pb_data` tarballs).
- No outbound internet required — including licensing (offline annual file).
- The licence service can only ever learn: company id, plan, status, expiry, features,
  installation id, software version. This is enforced by code and tests, not policy.

## Test coverage
- Flutter: `test/services/data/` — PocketBase REST contract, Firebase delegation parity,
  lifecycle-through-`AlertActionsService` on both backends, provider-level widget tests
  on both backends, auth/role-policy suite.
- Node (Jest): `worker_test/onprem_*.test.js` — RBAC rule matrix, ingestion pipeline
  (ingest→assign→escalate→notify), dedup/storm, change fan-out, retention,
  backup/restore, retry, licensing; `worker_test/edge_gateway.test.js` — all five
  adapters against simulated frames/payloads, security, forwarder, plan gating.

See `deploy/onprem/README.md` to install, and `lib/services/data/README.md` for the
app-side coverage table.

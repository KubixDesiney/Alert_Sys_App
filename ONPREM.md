# On-premise / air-gapped deployment

Many industrial buyers cannot use cloud services on the plant network. This is the
architecture and migration plan to run SIA entirely on a customer's own hardware, plus a
runnable scaffold under `deploy/onprem/`.

## Honest status
Today SIA runs on Firebase (Auth + Realtime Database) and Cloudflare Workers. A true
air-gapped build replaces those two cloud dependencies. This document is a **plan + a
working scaffold of the surrounding infrastructure** — the data/auth backend port and
the worker-logic port are scoped here as defined engineering work, not yet shipped.

## What already helps
- The **GBDT forecaster runs fully on-device** (no inference server) — already air-gap friendly.
- The **worker logic is plain JavaScript** — it can run under Node instead of Cloudflare.
- **Per-tenant isolation** (`PROVISIONING.md`) already assumes a self-contained instance.

## Cloud -> on-prem component map
| Cloud component | On-prem replacement | Notes |
|-----------------|---------------------|-------|
| Firebase Auth | PocketBase auth (recommended) or Keycloak / Supabase GoTrue | OIDC/SAML SSO still supported via the IdP on the LAN |
| Realtime Database | PocketBase (SQLite + realtime) for small/medium; Supabase (Postgres + realtime) for large | Requires a data-model + rules port |
| Cloudflare Workers (cron + HTTP) | Node service (`worker-runner`) with `node-cron` | Reuses existing assignment/AI/notify logic |
| FCM push | LAN WebSocket/SSE push; optional self-hosted UnifiedPush (ntfy) | Devices are on-site, so server-push over the LAN works |
| Firebase Hosting | Caddy/Nginx static serving of the Flutter web build | Single TLS entry point |

## Recommended air-gapped stack
- **Caddy** — TLS termination + reverse proxy + static web hosting (one entry point).
- **PocketBase** — single Go binary: data, realtime, auth, admin UI, SQLite (ideal for a
  factory's local server; trivial backups = copy the data dir).
- **worker-runner** — Node container running the cron + HTTP worker logic on the LAN.
- (Large sites) swap PocketBase for **Supabase** self-hosted (Postgres + Realtime + GoTrue).

## Phased migration
1. **Abstract the data layer** in the Flutter app behind an interface (today it calls
   Firebase directly). Add a PocketBase implementation alongside the Firebase one.
2. **Port `database.rules.json`** authorization to PocketBase API rules (RBAC is the same
   model: superadmin/admin/supervisor).
3. **Port worker logic** to `worker-runner`. DONE for AI assignment: `runAssignmentCycle`
   reuses the cloud's pure `buildSupStats`/`scoreSupervisor` against a `PocketBaseStore`
   (tested in `worker_test/onprem_assignment.test.js`). Remaining: escalation + notifications.
4. **Replace push** with LAN WebSocket/SSE; keep FCM as an optional path for internet sites.
5. **Package** with the `deploy/onprem/` compose; ship as an appliance image.

## Data residency & security benefits (sell these)
- All data stays on the customer's hardware/network — no third-party processors.
- Backups are a local file copy (PocketBase) or `pg_dump` (Supabase).
- No outbound internet required; satisfies air-gap and data-sovereignty requirements.

## Limitations to be honest about
- Mobile push without internet relies on LAN connectivity to devices.
- The data-layer + worker port is real work (estimate: a focused engineering effort, not a
  config change). The scaffold in `deploy/onprem/` stands up the surrounding infra so that
  port has a home.

See `deploy/onprem/README.md` to run the scaffold.

# Security Remediation — Codex scan of 2026-07-09

This document tracks the fixes for the 16 findings in the repository-wide Codex
Security scan (`report.md`). 15 findings are fixed in code + rules with tests;
finding 3 is a documented, mitigated single-tenant design trade-off (see below).

**After merging, you must:**

```bash
firebase deploy --only database              # ship the tightened RTDB rules
npm run deploy:workers                        # redeploy all 7 workers (auth-mode flip lives in wrangler vars)
# on-prem sites: re-import deploy/onprem/pocketbase/pb_schema.json and redeploy the worker-runner
```

The AI + notify workers now run `WORKER_AUTH_MODE = "required"`, so
`WORKER_SHARED_SECRET` **must** be set on the AI, notify, ingest and monitor
workers (it already is via CI) for worker-to-worker fast triggers; the
per-minute cron remains the durable delivery fallback if a trigger 401s.

| # | Finding | Fix | Tests |
|---|---------|-----|-------|
| 1 | Supervisor can self-attach as assistant + change lifecycle | `alerts/$alertId` self-attach branch now requires an active `helpRequestId` on the alert whose `help_requests/{id}/targetSupervisorId` is the caller; `status` restricted to the 4 lifecycle values | `firebase_rules_configuration.test.js`, `database_rules_security.test.js` |
| 2 | AI worker `log` auth mode → unauthenticated privileged access | `wrangler.ai.toml` `WORKER_AUTH_MODE = "required"` | `worker_auth.test.js` |
| 3 | Broad `auth != null` reads of `/alerts` + `/users` | **Mitigated / accepted** for the single-tenant model — see below | — |
| 4 | Any supervisor can claim any unassigned alert (cross-factory) | claim branch now requires `alert.usine`/`factoryId` == the caller's own factory | `firebase_rules_configuration.test.js` |
| 5 | Ingest `/verify` + `/control` fail **open** when secret unset | `adminAuthorized` fails **closed** (`return false` when `WORKER_SHARED_SECRET` unset) | `connectors.test.js` |
| 6 | Public GitHub proxy trusts client-shipped secret | direct route now requires a **SuperAdmin Firebase ID token** (`X-Firebase-Auth`), verified via RTDB role read; the shared secret alone no longer authorizes. Pages-proxy `skipAuth` path unchanged | `github_e2e.test.js` |
| 7 | Notify worker `log` auth mode | `wrangler.notify.toml` `WORKER_AUTH_MODE = "required"`; ingest + monitor worker-to-worker triggers now send `x-worker-secret` | `worker_auth.test.js` |
| 8 | SCIM email/userName change leaves stale active provisioning | `writeUser` now deletes `provisioning/{oldKey}` + `scim/byUserName/{oldKey}` when the email changes | `scim.test.js` |
| 9 | GitHub proxy accepts caller-selected `repo` | a `repo` query param that differs from the configured Guardian repo returns `403`; token routes are bound to `creds.repo` | `github_e2e.test.js` |
| 10 | Any authed user can suppress push delivery | worker-only lock fields `push_sending`/`push_sending_at` restricted to admin/superadmin/worker (closes the lock-holding DoS). See residual note below | `firebase_rules_configuration.test.js`, `database_rules_security.test.js` |
| 11 | Connector polling can exfiltrate stored credentials to an attacker `tag.url` | credentials (bearer/basic/api-key headers + query token) are only attached when the target host equals the connector's configured endpoint host (`credentialsAllowedForUrl`) | `connectors.test.js` |
| 12 | Supervisor can forge notifications for any user | a supervisor writing another user's queue may not set a reserved AI/system `type` (`ai_assigned`, `ai_recommendation`, `ai_rejected`, `alert_suspended`, `handover`, `shift_handover`, `shift_ai_assignment`, `confirm_presence`). Legit producer fan-out (new_alert/help/collaboration) is unaffected | `firebase_rules_configuration.test.js` |
| 13 | Self-writable `usine`/`factoryId` trusted by AI Functions | both locked to unchanged-or-admin (same pattern as `role`) — closes the cross-factory confused-deputy. Presence `status`/`aiOptOut` stay self-writable | `firebase_rules_configuration.test.js` |
| 14 | On-prem PocketBase alerts writable by any authed user | `createRule` → admin/superadmin; `updateRule` → admin/superadmin OR owner/assistant OR unassigned self-claim | (schema; validated on PB import) |
| 15 | On-prem SSE stream fails open + no uid binding | `tokenOk` fails **closed** when the secret is unset; `/events` now binds `uid` to a PocketBase-authenticated session (`authorizedForUid`) — admins may watch any uid | (module exports `tokenOk`/`authorizedForUid`) |
| 16 | Backup `/backup` + `/retention` public when secret unset | both fail **closed** (`403`) when `WORKER_SHARED_SECRET` is unset | `retention.test.js` |

## Finding 3 — broad reads of `/alerts` and `/users` (mitigated / accepted)

The report flags that `/alerts` and `/users` are readable by any authenticated
user (`.read: auth != null`) and are cached offline. Fully factory-scoping these
reads at the RTDB layer is **not compatible** with the current product without a
larger redesign, and shipping it blindly would break core features:

- Realtime Database rules gate list reads at the queried node; they cannot
  filter children. Every read shape the app performs would each have to satisfy
  a single `.read` expression. The app reads `/alerts` **unscoped** (Production
  Manager dashboards, the on-device forecaster/overview engine) *and* by
  `usine`, `superviseurId`, and `assistantId` (supervisor streams). The
  `/users` root is read to build supervisor rosters, resolve assignment names,
  and score assignments.
- Locking those reads to factory scope breaks the PM global views, the
  forecaster, cross-factory collaboration, and roster UIs.

What is already true and bounds the exposure:

- This is a **dedicated single-tenant deployment** (one customer instance per
  environment) — the "cross-factory" data is one customer's own operational
  data exposed to that same customer's own authenticated employees.
- Sensitive PII (`email`, `phone`, `currentLocation`) is already segregated into
  `users_private` (self + admin roles only); the broadly-readable `users` node
  carries only operational metadata (name, role, factory, status).

**Recommended path (future work), if a customer requires hard factory
isolation:** move alert/user reads behind a trusted, factory-scoped Worker/Cloud
Function read API (server enforces scope, client never reads the raw roots), or
split supervisors onto query-scoped `.read` rules (`query.orderByChild ==
'usine' && query.equalTo == <caller's factory>`) while keeping PM/admin on the
broad node. Both are multi-file changes that must be validated end-to-end
against the live app, so they are out of scope for this hardening pass.

## Finding 10 — residual note

`push_sent`, `push_sent_at`, `push_delivery_mode`, and `notificationSent` on the
alert record intentionally stay client-writable: every stream client marks them
to dedup the new-alert fan-out (see the "stream fan-out dedup" design in
`CLAUDE.md`). A malicious client setting `push_sent: true` early only defeats the
legacy `/alerts` cron fallback — the primary delivery path is the
worker-controlled `/notifications/{uid}/new_alert_*` queue, whose `pushSent` the
client cannot flip on another user's delivered row. The effective
lock-holding DoS vector (`push_sending`) is now admin/worker-only.

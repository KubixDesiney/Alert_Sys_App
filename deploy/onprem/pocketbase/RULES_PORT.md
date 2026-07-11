# RTDB -> PocketBase rules port (customer RBAC)

Translation of SIAS's authorization model into PocketBase collection API rules for the
on-prem path — now built around the **customer role set**, not the cloud role names.

## Customer roles (on-prem)
| Role | Purpose | Key limits |
|------|---------|-----------|
| `company_owner` | Owns the deployment: branding, user accounts, connectors | **No deployment secrets** — TLS keys, PB admin password, worker shared secret and license keys live in the host `.env`/encrypted store, never in PocketBase |
| `production_manager` | Factory operations: alerts, escalation policy, rosters | Cannot manage users/branding/connectors; cannot reach secrets |
| `supervisor` | Handles alerts | Scoped to their own factory (`usine = @request.auth.usine`); cannot create or delete alerts |
| `vendor_support` | Vendor diagnostics | **Disabled by default**, time-boxed (`vendorAccessExpiresAt > @now`), read-only (security logs only), every sign-in audited. One named account per engineer — no shared credentials |

The internal **platform SuperAdmin does not exist on-prem**: vendor-side platform roles stay
in the vendor cloud. On-prem "root" is PocketBase's own `_superusers` admin, held by the
customer's IT, and the worker-runner's service identity (which bypasses collection rules —
the equivalent of the Firebase service account).

Legacy `admin` is still accepted in rules as an alias for `production_manager`
(migration compatibility).

## Rule cheatsheet
| Concept | PocketBase rule |
|---------|-----------------|
| authed | `@request.auth.id != ""` |
| account not disabled | `@request.auth.disabled != true` |
| factory scoping | `usine = @request.auth.usine` |
| vendor window | `@request.auth.vendorAccessExpiresAt > @now` |
| block role self-escalation | `@request.data.role:isset = false` on self-update |
| author-pinned audit append | `@request.data.actorId = @request.auth.id` |
| worker / service-account only | rule = `null` (superuser-only) |

`null` = locked (superuser only), `""` = public, non-empty string = filter that must pass.

## Per-collection summary (exact strings in `pb_schema.json`)
| Collection | list/view | create | update | delete |
|------------|-----------|--------|--------|--------|
| `users` (auth) | self, owner, PM | owner | self (password only — role/disabled/vendor fields locked) or owner | owner (not self) |
| `alerts` | owner/PM all; supervisor own factory | owner/PM | owner/PM; supervisor own-factory claim/own/assist | nobody |
| `supervisor_active_alerts` | authed / self-or-managing | self or PM | self or PM | self or PM |
| `notifications` | recipient or owner/PM | authed non-vendor | recipient or PM | nobody |
| `escalation_settings` | authed | owner/PM | owner/PM | owner/PM |
| `branding` | authed | owner | owner | owner |
| `connectors` | owner | owner | owner | owner |
| `connector_secrets` | **nobody (write-only)** | owner | owner | nobody |
| `audit_logs` | owner | any active user, actorId pinned | **nobody** | **nobody** |
| `security_logs` | owner, or vendor inside window | worker only | nobody | nobody |

These rules are executable-tested: `worker_test/onprem_rbac.test.js` evaluates the real
strings from `pb_schema.json` against a persona matrix via `rules_eval.mjs`.

## Session / credential hygiene
- Sessions expire with the PocketBase JWT; the Flutter `PocketBaseAuthService` also
  enforces expiry locally and re-checks the disabled/vendor gates on every `auth-refresh`.
- Password change requires the old password (PocketBase invalidates the token — forced
  re-login). `mustChangePassword` supports first-login rotation.
- MFA: `MfaProvider` interface is wired in the sign-in path (`NoopMfaProvider` by default).
- No shared credentials: PocketBase enforces unique emails; provisioning scripts create
  individual accounts only.

## Field validation
RTDB `.validate` rules become PocketBase field **types** + `required` (`text`/`number`/
`bool`/`date`/`json`); range checks use field `min`/`max` or a small
`onRecordBeforeCreate/Update` hook.

## Applying it
1. PocketBase Admin -> **Settings -> Import collections** -> paste `pb_schema.json`
   (verify field types against your PocketBase version), **or** drop it into
   `pb_migrations/` as a migration.
2. Create the superuser the worker-runner uses; put its token in `PB_TOKEN`.
3. Migrate existing data (optional): `node migrate_rtdb_to_pocketbase.mjs --input export.json
   --pb http://localhost:8090 --token <superuser> --dry-run` (drop `--dry-run` to apply).
4. Provision the first `company_owner` user, who then provisions everyone else in-app.

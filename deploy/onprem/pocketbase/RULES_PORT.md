# RTDB -> PocketBase rules port

Faithful translation of `database.rules.json` (Firebase RBAC) into PocketBase collection
API rules for the on-prem path. The RBAC model is unchanged — only the enforcement engine.

## Identity mapping
- The authed user is `@request.auth`. Its `role` field is `@request.auth.role`; its id is
  `@request.auth.id`.
- The **worker-runner connects as a PocketBase superuser**, which bypasses all collection
  rules — the exact equivalent of the Firebase service-account bypassing RTDB rules. So any
  node that was "worker/service-account writes" becomes a `null` (locked) client rule.

## Rule cheatsheet
| RTDB | PocketBase rule |
|------|-----------------|
| `auth != null` | `@request.auth.id != ""` |
| `root.child('users').child(auth.uid).child('role').val() === 'admin'` | `@request.auth.role = "admin"` |
| `auth.uid === $ownerId` | `<ownerField> = @request.auth.id` |
| superadmin only | `@request.auth.role = "superadmin"` |
| worker / service-account only | rule = `null` (superuser-only) |
| public (pre-auth) read | rule = `""` |

PocketBase semantics to remember: **`null` = locked (superuser only)**, **`""` = public**,
a non-empty string = a filter that must pass.

## Per-collection rules
| Collection | list | view | create | update | delete |
|------------|------|------|--------|--------|--------|
| `users` (auth) | authed | authed | null (provisioned by superadmin/worker) | self or admin/superadmin | superadmin |
| `alerts` | authed | authed | authed | authed | null |
| `supervisor_active_alerts` | authed | self or admin | self or admin | self or admin | self or admin |
| `notifications` | self or admin | self or admin | authed | self or admin | null |
| `escalation_settings` | authed | authed | admin | admin | admin |
| `collaboration_requests` / `help_requests` | authed | authed | authed | authed | admin |
| `security_logs` / `security_actions` | superadmin | superadmin | null | null | null |
| `provisioning` / `infra_config` / `scim` | superadmin | superadmin | null | null | null |
| `branding_config` / `auth_config` | public (`""`) | public | superadmin | superadmin | superadmin |

Exact PocketBase filter strings are in `pb_schema.json` (this folder).

## Field validation
RTDB `.validate` rules become PocketBase field **types** + `required`:
- `isString()` -> `text`; `isNumber()` -> `number`; `isBoolean()` -> `bool`.
- `currentLocation {lat,lng}` numeric -> two `number` fields (or a `json` field validated in a hook).
- Range checks (e.g. `aiConfidence 0..1`, `startMinutes 0..1439`) -> PocketBase field
  `min`/`max` options, or a lightweight `onRecordBeforeCreate/Update` hook.

## Integration notes
- `escalation_settings` is modeled as a single record with a `settings` (json) field holding
  the `{type:{unclaimedMinutes,claimedMinutes}, default:{...}}` map. `PocketBaseStore.getEscalationSettings`
  should read `items[0]?.settings ?? {}` (one-line tweak when wiring).
- The unauthenticated constrained alert-create path (RTDB) is intentionally dropped on-prem:
  integrations create alerts via the worker (superuser) or an authed account.

## Applying it
1. PocketBase Admin -> **Settings -> Import collections** -> paste `pb_schema.json`
   (verify field types against your PocketBase version first), **or** drop it into
   `pb_migrations/` as a migration.
2. Create the superuser the worker-runner uses; put its token in `PB_TOKEN` (see
   `deploy/onprem/docker-compose.yml`).
3. Migrate existing data (optional): `node migrate_rtdb_to_pocketbase.mjs --input export.json
   --pb http://localhost:8090 --token <superuser> --dry-run` (drop `--dry-run` to apply).
4. Provision the first `superadmin` user record, then use the app/console as normal.

# Per-customer instance provisioning (v1)

SIAS is sold as **one dedicated instance per customer** — its own Firebase project
(RTDB + Auth) and its own set of 8 Cloudflare Workers. `tool/provision_instance.mjs`
automates everything scriptable in that runbook and prints an explicit TODO list
for the handful of steps that still require a human in the Firebase console.

This is v1: it biases toward **safe, idempotent, resumable** steps over full
automation. It defaults to `--dry-run` — nothing touches your Firebase project,
Cloudflare account, or the filesystem unless you pass `--execute`.

> Looking for the *older*, template-only flow? `../PROVISIONING.md` (repo root)
> documents `tool/provision_company.mjs`, which generates config/build-script
> artifacts but makes zero network calls and requires you to run every
> `firebase`/`wrangler` command yourself. `tool/provision_instance.mjs` (this
> doc) is the live-automation successor: it actually runs those commands for
> you, step by step.

---

## What the script does

```bash
node tool/provision_instance.mjs \
  --tenant nsw-7k2f \
  --project-id nsw-7k2f-alerts \
  [--region europe-west1] \
  [--execute] \
  [--skip step,step] \
  [--workers-subdomain your-cf-subdomain] \
  [--owner-email owner@customer.com --owner-name "First Last" --owner-company "Customer Co"]
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--tenant` | yes | — | Lowercase slug (`a-z0-9-`), e.g. `nsw-7k2f`. Used to suffix every worker name and the tenant config directory. |
| `--project-id` | yes | — | The Firebase/GCP project id to create or reuse. |
| `--region` | no | `europe-west1` | Passed to `firebase database:instances:create`. |
| `--execute` | no | off (dry-run) | Without it, the script only prints the numbered plan and touches nothing. |
| `--skip` | no | none | Comma-separated step ids to skip on a resumed run, e.g. `--skip preflight,firebase-project,rules`. |
| `--workers-subdomain` | no | `REPLACE-workers-subdomain` placeholder | Your `*.workers.dev` account subdomain, used to build `NOTIFY_WORKER_URL`. Falls back to `CLOUDFLARE_WORKERS_SUBDOMAIN` env var. |
| `--owner-email` / `--owner-name` / `--owner-company` | no | — | If all three are given, step 7 runs `tool/provision_owner.mjs` automatically. Otherwise step 7 prints the exact command to run once you have the buyer's details. |

The 8 numbered steps (each prints `DONE` / `SKIPPED` / `TODO` / `FAIL`):

1. **Preflight** — confirms `firebase` and `wrangler` are on `PATH`, that
   `firebase login:list` shows an authorized account, and that `wrangler whoami`
   succeeds. Fails immediately with the exact install/login command if not
   (`npm i -g firebase-tools`, `npm i -g wrangler`, `firebase login`, `wrangler login`).
2. **Firebase project** — `firebase projects:create <project-id>` (reused if it
   already exists — the script treats "already exists" as success, not
   failure) plus `firebase database:instances:create <project-id>-default-rtdb
   --location <region>`. Prints the manual-console TODOs listed below.
3. **Rules** — `firebase deploy --only database --project <project-id>`. Same
   `database.rules.json` as every other instance; nothing tenant-specific to
   template here.
4. **Worker configs** — templates all 8 root `wrangler.*.toml` files into
   `deploy/tenants/<tenant>/wrangler.<key>.<tenant>.toml`: the worker `name` is
   suffixed `-<tenant>`, the shared backup R2 bucket name is namespaced
   `<tenant>-alertsys-backups`, and `FB_DB_URL`/`NOTIFY_WORKER_URL` are injected
   into each config's `[vars]` block. **The root `wrangler.*.toml` files are
   never modified** — only read as templates.
5. **Secrets** — on first run, writes a fully-commented
   `deploy/tenants/<tenant>/.env.tenant` template (git-ignored) listing every
   secret each of the 8 workers needs, each set to the placeholder
   `REPLACE_ME`, and stops so you can fill in real values. On a subsequent run,
   parses that file and **refuses to proceed if any required value is still
   missing or still `REPLACE_ME`** — then pipes every filled-in value into
   `wrangler secret put <NAME> --config <tenant config>` (values are piped via
   stdin, never printed, never logged).
6. **Deploy** — `wrangler deploy --config <tenant config>` for all 8 tenant
   configs.
7. **Seed the Owner** — shells out to `tool/provision_owner.mjs` (see the
   "Owner Activation Flow" section of the root `CLAUDE.md`) with this
   instance's `--db-url`, and folds its JSON summary (`uid`, `email`,
   `tenantCode`, `activationLink`, `expiresNote`) into the final summary. If
   `--owner-email`/`--owner-name`/`--owner-company` weren't passed, this step
   just prints the exact command to run once you have the buyer's details.
8. **Summary** — writes `deploy/tenants/<tenant>/provision-summary.json` (no
   secret values — worker names/config paths, the RTDB URL, and the owner
   summary from step 7) and prints every outstanding manual TODO collected
   along the way.

Because steps 2–8 are keyed off files under `deploy/tenants/<tenant>/` and RTDB/
Cloudflare state that's safe to recheck, a second run with `--execute --skip
<already-done-steps>` picks up exactly where you left off.

---

## Manual console steps (not scriptable)

The Firebase/Google Cloud consoles don't expose these over the CLI, so the
script prints them as TODOs after step 2 rather than guessing at them:

1. **Enable Blaze (pay-as-you-go) billing** — required for SMS MFA and worker
   FCM sends. Console → *Usage and billing* → *Modify plan* → select **Blaze**
   → attach a billing account.
2. **Enable the Email/Password sign-in provider** — Console → *Build* →
   *Authentication* → *Sign-in method* tab → *Add new provider* → **Email/Password**
   → toggle *Enable* → *Save*. (This is what makes `generatePasswordResetLink`
   in `tool/provision_owner.mjs` work — without it, activation link generation
   fails.)
3. **Create the Android app**  — Console → *Project settings* (gear icon) →
   *Your apps* → *Add app* → **Android** → enter the package name (matches
   `applicationId` in `android/app/build.gradle`) → *Register app* → download
   **`google-services.json`** → place it at `android/app/google-services.json`
   for this customer's build (see the isolation guidance in the root
   `PROVISIONING.md` — never commit one customer's file as the shared default).
4. **Confirm Cloud Messaging (FCM) is enabled** — it's on by default for a new
   Android app registration, but double-check under *Project settings* →
   *Cloud Messaging* tab that an API key/sender ID is present. This is what the
   notify worker's `FIREBASE_SERVICE_ACCOUNT` uses to mint FCM OAuth tokens at
   the edge.

---

## Post-provision checklist

Once all 8 steps report `DONE`:

- [ ] The 4 manual console steps above are complete.
- [ ] `deploy/tenants/<tenant>/provision-summary.json` exists and looks right
      (worker names, RTDB URL, owner `uid`/`activationLink`).
- [ ] The buyer has received the one-time activation link — either handed over
      directly from the summary, or via the `N8N_ACTIVATION_WEBHOOK_URL` →
      Brevo branded email flow (see `tool/provision_owner.mjs` / CLAUDE.md
      "Owner Activation Flow").
- [ ] The buyer's Kubix agent context is correct: their `/copilot` link should
      carry `?tenant=<TENANT#CODE>&company=<Company>&name=<Name>&plan=<plan>`
      (see the Store Worker section of CLAUDE.md) so Kubix greets them by name
      and tenant from the first message.
- [ ] Monitoring probe URLs are noted somewhere the ops team can find them:
      `https://alertsys-monitor-<tenant>.<subdomain>.workers.dev/config` and
      each of the other 7 tenant workers' `/config` endpoints, for a quick
      manual health check before handing the instance to the customer.
- [ ] Build the customer's app (Android/web) per the root `PROVISIONING.md`
      build-command guidance, pointed at this tenant's worker URLs and Firebase
      project.

## Full flow, end to end

```
provision the instance (this doc, tool/provision_instance.mjs)
        │
        ▼
run npm run provision:owner  (or let step 7 do it automatically)
        │
        ▼
buyer receives the one-time activation link
        │
        ▼
buyer opens the link, sets their own password, enables MFA on first login
        │
        ▼
buyer lands on their SuperAdmin console — instance is live
```

## Lifecycle tooling (2026-07-20)

Provisioning is now verifiable, reversible, and CI-capable:

- **Verification** — `npm run verify:instance -- --tenant <slug>`
  (`tool/verify_instance.mjs`): probes every tenant worker's `GET /config`,
  confirms the RTDB REST endpoint responds, and proves rules are deployed (an
  unauthenticated read of `/users.json` MUST be denied — a 200 there is a
  critical red). Prints a green/red table; exit code reflects health. It runs
  automatically as the final step of `provision:instance --execute` (step 9,
  `--skip verify` to opt out) and marks the tenant `verified` /
  `failed-verification` in the registry.
- **Teardown** — `npm run teardown:instance -- --tenant <slug> [--execute]`
  (`tool/teardown_instance.mjs`): DRY-RUN BY DEFAULT. With `--execute` it
  deletes the tenant workers (`wrangler delete` per generated config), archives
  `deploy/tenants/<tenant>/` to `deploy/tenants/_archived/<tenant>-<date>/`,
  and marks the registry entry `deleted`. It **never** deletes the Firebase
  project or R2 backups — both are manual, deliberate steps it prints loudly.
- **Registry** — `deploy/tenants/registry.json` (git-ignored), maintained by
  provision/teardown via `tool/tenant_registry.mjs`; `npm run tenants`
  (`tool/list_tenants.mjs`) prints it as a table.
- **Backup drill** — `npm run backup:drill -- --tenant <slug>`
  (`tool/backup_drill.mjs`): fetches the tenant backup worker's `GET /config`
  (newest R2 snapshot metadata; endpoint added to
  `cloudflare_backup_worker.js`) and fails unless the newest snapshot is
  < 36h old. This is the "are backups actually happening" check.
- **CI provisioning** — `.github/workflows/provision-tenant.yml`:
  `workflow_dispatch` with tenant/project-id/subdomain inputs, gated behind
  the **`provisioning` GitHub environment** (configure required reviewers so a
  stray click cannot create infra). The environment supplies
  `TENANT_ENV_FILE` (the filled `.env.tenant`), Cloudflare and Firebase
  credentials; the run executes provision + verify and uploads the summary.

`provision-summary.json` now records `workersSubdomain` + `workerUrls` so
verification and the backup drill can find the tenant workers. Pure helpers
are covered by `worker_test/verify_instance.test.js` and
`worker_test/tenant_registry.test.js` (no live network in tests).

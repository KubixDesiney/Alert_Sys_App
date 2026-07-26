# Per-customer instance provisioning

> **Production B2B flow (2026-07-26):**
> [`ops/AUTOMATIC_ORDER_PROVISIONING.md`](ops/AUTOMATIC_ORDER_PROVISIONING.md)
> is the authoritative Accept/Paid runbook. The authenticated Paid action now
> creates the Firebase project, seven tenant data-plane Workers, day-one RTDB
> schema, Production Manager and supervisor accounts, verifies the instance,
> and then delivers activation emails. The older material below remains useful
> as the manual recovery/operator reference.

SIAS is sold as **one dedicated instance per customer** — its own Firebase project
(RTDB + Auth) and its own set of 7 data-plane Cloudflare Workers. `sias-store`
and `sias-app` are shared control-plane/front-door services and are never cloned
per buyer. `tool/provision_instance.mjs` is the strict, resumable lower-level
runner used by both manual recovery and the automatic Paid workflow.

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
  --tenant-code "T#CODE" --company "Customer Co" --plan growth \
  --pm-email pm@customer.com --pm-name "Production Manager" \
  --supervisor-email supervisor@customer.com --supervisor-name "Supervisor"
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--tenant` | yes | — | Lowercase slug (`a-z0-9-`), e.g. `nsw-7k2f`. Used to suffix every worker name and the tenant config directory. |
| `--project-id` | yes | — | The Firebase/GCP project id to create or reuse. |
| `--region` | no | `europe-west1` | Passed to `firebase database:instances:create`. |
| `--execute` | no | off (dry-run) | Without it, the script only prints the numbered plan and touches nothing. |
| `--skip` | no | none | Comma-separated step ids to skip on a resumed run, e.g. `--skip preflight,firebase-project,rules`. |
| `--workers-subdomain` | no | `REPLACE-workers-subdomain` placeholder | Your `*.workers.dev` account subdomain, used to build `NOTIFY_WORKER_URL`. Falls back to `CLOUDFLARE_WORKERS_SUBDOMAIN` env var. |
| `--tenant-code`, `--company`, `--plan` | live run | — | Commercial identity and `starter`/`growth` entitlement used by the day-one seed and TENANTS KV record. |
| `--pm-email` / `--pm-name` | live run | — | Production Manager account; RTDB role is the required lowercase `admin`. |
| `--supervisor-email` / `--supervisor-name` | live run | — | The first supervisor account. It must use a different email from the PM. |

The 11 numbered steps (each prints `DONE` / `SKIPPED` / `TODO` / `FAIL`):

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
4. **Worker configs** — templates the seven data-plane `wrangler.*.toml` files into
   `deploy/tenants/<tenant>/wrangler.<key>.<tenant>.toml`: the worker `name` is
   suffixed `-<tenant>`, the shared backup R2 bucket name is namespaced
   `<tenant>-alertsys-backups`, and `FB_DB_URL`/`NOTIFY_WORKER_URL` are injected
   into each config's `[vars]` block. **The root `wrangler.*.toml` files are
   never modified** — only read as templates.
5. **Secrets** — on first run, writes a fully-commented
   `deploy/tenants/<tenant>/.env.tenant` template (git-ignored) listing every
   secret each of the seven workers needs, each set to the placeholder
   `REPLACE_ME`, and stops so you can fill in real values. On a subsequent run,
   parses that file and **refuses to proceed if any required value is still
   missing or still `REPLACE_ME`** — then pipes every filled-in value into
   `wrangler secret put <NAME> --config <tenant config>` (values are piped via
   stdin, never printed, never logged).
6. **Deploy** — `wrangler deploy --config <tenant config>` for all seven tenant
   configs.
7. **Seed tenant data** — runs `tool/seed_tenant.mjs` and fills only missing
   RTDB leaves: hierarchy, first asset, alert vocabulary, escalation defaults,
   counters, tenant metadata, and plan/AI entitlements.
8. **App delivery** — builds the public tenant config from the Firebase web config
   file, per-tenant worker URLs, company identity, and Copilot URL; writes it to
   `deploy/tenants/<tenant>/tenant-kv.json`, then runs `wrangler kv key put` into
   the shared `TENANTS` namespace when the namespace id and web config are ready.
   If either is not ready, it writes safe templates and prints the exact TODO.
   It also records the app URL and branded ingest hostname and prints the route/DNS
   and APK follow-ups.
9. **Summary** — writes `deploy/tenants/<tenant>/provision-summary.json` (no
   secret values — worker names/config paths, RTDB URL, `appUrl`, `ingestHost`,
   and redacted delivery evidence) and prints every outstanding manual TODO.
10. **Verification** — runs `tool/verify_instance.mjs`: every tenant worker's
   `/config`, `<appUrl>/__config` with `hasConfig: true`, RTDB reachability, and
   anonymous `/users.json` denial.
11. **Seat delivery** — only after verification, runs
    `tool/provision_seats.mjs --require-delivery-pair --execute`; creates/reuses
    the PM and supervisor Auth users, keeps email under `users_private/{uid}`,
    and sends one fresh single-use activation link to each seat through the
    authenticated n8n activation webhook. Links never enter the summary/logs.

Because steps 2–10 are keyed off files under `deploy/tenants/<tenant>/` and RTDB/
Cloudflare state that's safe to recheck, a second run with `--execute --skip
<already-done-steps>` picks up exactly where you left off.

---

## Manual recovery console steps

The automatic Paid workflow performs the billing link, Email/Password provider,
Web app, and FCM/API setup through authenticated Google APIs. Use these console
steps only to repair or inspect a manually provisioned legacy tenant:

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

## Shared app delivery and DNS prerequisites

The web app is served by one shared `sias-app` Worker. It does not get rebuilt per
customer: the Worker reads the tenant slug from the host and injects that tenant's
public Firebase web config at request time.

Before activating a customer hostname, do these Cloudflare dashboard steps once:

1. In the `kubixdesiney.com` zone, create a proxied wildcard DNS record
   `*.kubixdesiney.com` (an A/AAAA placeholder or CNAME is sufficient because the
   Worker route handles the response).
2. Create a proxied `sias.kubixdesiney.com` record for the storefront and keep its
   `sias.kubixdesiney.com/*` route on `sias-store`.
3. Add the wildcard route `*.kubixdesiney.com/*` to `sias-app`. The storefront's
   more-specific route wins for `sias`; each generated tenant ingest config carries
   the still-more-specific `<tenant>-ingest.kubixdesiney.com/*` route for activation
   after the wildcard DNS record exists.
4. Create the Workers KV namespace named `TENANTS`, put its id in `wrangler.app.toml`,
   and deploy `sias-app` only after `flutter build web --release` has produced
   `build/web`.
5. Confirm Universal SSL is active for `*.kubixdesiney.com`. Keep all customer app
   and ingest hosts one level deep; nested hosts need a different certificate plan.

For each tenant, download the Firebase **Web app** config from Project settings →
Your apps → Web → SDK setup/config, save it as the git-ignored
`deploy/tenants/<tenant>/firebase-web-config.json`, then rerun the app-delivery step.
The resulting `tenant-kv.json` contains only public Firebase client configuration and
worker URLs; it must never contain service-account JSON, worker secrets, or private
keys. The app worker's `/__config` probe returns only `ok`, `tenant`, and `hasConfig`.

## Android delivery

Web/PWA delivery is immediate after the KV entry and app route are live. Android is
different because Firebase Messaging consumes `google-services.json` at build time.
The repository does not store a tenant Firebase file, signing key, or APK.

1. In the tenant's Firebase console, register the Android app using the package name
   from `android/app/build.gradle`, download `google-services.json`, and base64-encode
   it locally (`base64 -w0 google-services.json` on Linux/macOS; use an equivalent
   no-newlines encoder on Windows).
2. Store that value as `GOOGLE_SERVICES_JSON_B64` in the protected GitHub
   **`provisioning` environment**. Do not put it in repository variables or commit it.
3. Run `.github/workflows/build-tenant-apk.yml`, supplying the tenant slug,
   Firebase project id, Workers subdomain, and optional company/Copilot values. The
   workflow requires the `provisioning` environment approval, validates the project
   id inside the JSON, uploads a GitHub artifact, and publishes the APK to the
   tenant's R2 path so it is served at:
   `https://<tenant>.kubixdesiney.com/app/sias-<tenant>.apk`.
4. Supervisors can open `https://<tenant>.kubixdesiney.com/app` and scan the QR code,
   then allow installs from that source when Android prompts. Managed devices can
   receive the same APK through MDM. The browser PWA works immediately and needs no
   APK installation.

---

## Post-provision checklist

Once the script's 11 steps report `DONE`:

- [ ] The 4 manual console steps above are complete.
- [ ] `deploy/tenants/<tenant>/provision-summary.json` exists and looks right
      (worker names, RTDB URL, `appUrl`, `ingestHost`, redacted seat delivery;
      no activation link or account email).
- [ ] The PM and supervisor have each received their own activation email via
      `N8N_ACTIVATION_WEBHOOK_URL`.
- [ ] The buyer's Kubix agent context is correct: their `/copilot` link should
      carry `?tenant=<TENANT#CODE>&company=<Company>&name=<Name>&plan=<plan>`
      (see the Store Worker section of CLAUDE.md) so Kubix greets them by name
      and tenant from the first message.
- [ ] Monitoring probe URLs are noted somewhere the ops team can find them:
      `https://alertsys-monitor-<tenant>.<subdomain>.workers.dev/config` and
      each of the other 6 tenant workers' `/config` endpoints, for a quick
      manual health check before handing the instance to the customer.
- [ ] `https://<tenant>.kubixdesiney.com/__config` returns HTTP 200 with
      `hasConfig: true`, and the app root loads the injected runtime config.
- [ ] Build the customer's Android app with the gated workflow in the
      [Android delivery](#android-delivery) section. The web PWA is already
      available once the app route and KV entry are live.

## Full flow, end to end

```
Paid dispatch provisions and verifies the instance
        │
        ▼
seed the day-one tenant database and publish TENANTS KV
        │
        ▼
PM + supervisor receive separate one-time activation links
        │
        ▼
each user opens their link and sets their own password
        │
        ▼
buyer lands on the ready, dedicated SIAS instance
```

## Lifecycle tooling (2026-07-20)

Provisioning is now verifiable, reversible, and CI-capable:

- **Verification** — `npm run verify:instance -- --tenant <slug>`
  (`tool/verify_instance.mjs`): probes every tenant worker's `GET /config`,
  probes the shared `appUrl/__config` endpoint and requires JSON `hasConfig: true`,
  confirms the RTDB REST endpoint responds, and proves rules are deployed (an
  unauthenticated read of `/users.json` MUST be denied — a 200 there is a
  critical red). Prints a green/red table; exit code reflects health. It runs
  automatically as the final step of `provision:instance --execute` (step 10,
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

`provision-summary.json` now records `workersSubdomain` + `workerUrls` + `appUrl` +
`ingestHost` so
verification and the backup drill can find the tenant workers. Pure helpers
are covered by `worker_test/verify_instance.test.js` and
`worker_test/tenant_registry.test.js` (no live network in tests).

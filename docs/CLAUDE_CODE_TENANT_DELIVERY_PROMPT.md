# Claude Code prompts — per-tenant app delivery on kubixdesiney.com

Run from `alertsysapp/` repo root. Prompt 1 first (it unblocks every customer),
Prompt 2 after. Both are self-contained.

## The decided architecture (do not redesign it)

Domain: **kubixdesiney.com**, DNS on Cloudflare. Naming:

| Host | Serves |
|---|---|
| `sias.kubixdesiney.com` | the storefront (`sias-store` worker: landing, /buy, /copilot, /welcome) |
| `<tenant>.kubixdesiney.com` | that customer's SIAS web app (e.g. `nagati.kubixdesiney.com`) |
| `<tenant>-ingest.kubixdesiney.com` | that customer's ingest endpoint — a stable branded hostname plant IT can whitelist in their firewall |

**One shared app worker, not one per tenant.** A single `sias-app` worker serves the
Flutter web build to every tenant subdomain and injects that tenant's *public* Firebase
config at request time based on the `Host` header. Rationale: app updates ship once for
all customers instead of rebuilding N bundles, and `*.kubixdesiney.com` is covered by
Cloudflare's free universal SSL (one level deep — do NOT nest deeper, e.g.
`x.sias.kubixdesiney.com` would need paid Advanced Certificate Manager).

**Isolation is unaffected by sharing the app worker.** Firebase client config
(apiKey/appId/projectId/databaseURL/senderId) is public by design — isolation is
enforced by each tenant's own Auth realm and RTDB rules, which are unchanged. The app
worker only serves static assets plus a config blob; it never touches customer data.

Android keeps per-tenant APKs (build-time `google-services.json`), downloadable from
that tenant's own subdomain.

---

## Prompt 1 — Shared app worker + runtime Firebase config

```
Read CLAUDE.md first (especially "Active Worker Split", "Store Worker" and
"Per-Customer Provisioning"). You are in the SIAS repo.

CONTEXT
SIAS sells dedicated instances: each customer has their own Firebase project and their
own set of Cloudflare workers, created by tool/provision_instance.mjs. Today the Flutter
app is bolted to ONE Firebase project at build time (lib/firebase_options.dart hardcodes
"alertappsys"), so there is no way to deliver the app per customer. Fix that.

Decided design (implement exactly this):
- ONE new worker `sias-app` (cloudflare_app_worker.js + wrangler.app.toml) serves the
  Flutter web build to every tenant at <tenant>.kubixdesiney.com.
- It resolves the tenant from the Host header, looks up that tenant's PUBLIC Firebase
  config in a Workers KV namespace, and injects it into index.html as
  <script>window.__SIAS_CONFIG__ = {...}</script> before the flutter_bootstrap script.
- The Flutter web bootstrap reads window.__SIAS_CONFIG__ and initializes Firebase with
  it, falling back to DefaultFirebaseOptions when absent (local dev, Android).

TASK
1. Worker (cloudflare_app_worker.js):
   - Static assets binding for the Flutter web build directory (wrangler assets config;
     the build output is build/web — document that CI must build before deploy).
   - Host -> tenant: `nagati.kubixdesiney.com` -> `nagati`. Reject/404 with a friendly
     branded page for unknown tenants, the apex, and `www`.
   - KV binding `TENANTS`: key = tenant slug, value = JSON
     { tenantCode, company, firebase: {apiKey, authDomain, projectId, storageBucket,
     messagingSenderId, appId, databaseURL}, workers: {ai, notify, ingest, copilotUrl} }.
   - For `/` and any SPA route, fetch index.html from assets, inject the config script +
     a <base href="/"> if needed, return with correct headers (no-store on the injected
     HTML, long cache on hashed assets). Everything else passes through to assets.
   - `GET /__config` returns { ok, tenant, hasConfig } for probing (NEVER dump secrets —
     the Firebase client config is public, but do not echo anything from env).
   - Reuse the store worker's security-header helper (CSP with nonce, HSTS, etc.); the
     injected inline script needs the nonce.
2. Flutter web runtime config:
   - Add lib/config/runtime_firebase_config.dart with a web implementation reading
     window.__SIAS_CONFIG__ (package:web or dart:js_interop — match the repo's existing
     interop style) and a stub for non-web returning null.
   - In main.dart's _safeInitFirebase, prefer the runtime config when present, else
     DefaultFirebaseOptions.currentPlatform. Keep the existing CompanyConfig
     project-mismatch safety check working against whichever config was used.
   - Same for the worker base URLs: when window.__SIAS_CONFIG__.workers exists, prefer
     those over the dart-define values in AppConfig (add a small runtime override layer;
     do not break the const dart-define path used by Android).
   - web/firebase-messaging-sw.js also hardcodes config — make it fetch /__swconfig
     (new worker route returning that tenant's messaging config as JS) so web push works
     per tenant.
3. Provisioning wiring (tool/provision_instance.mjs):
   - New step: write the tenant's public config into the TENANTS KV namespace
     (wrangler kv key put), and add the Cloudflare route <tenant>.kubixdesiney.com/* to
     the sias-app worker. Also add <tenant>-ingest.kubixdesiney.com/* to that tenant's
     ingest worker config.
   - provision-summary.json gains appUrl + ingestHost; verify_instance probes appUrl
     (expects 200 and the injected config present) and adds it to its table.
4. package.json: "deploy:app": "wrangler deploy --config wrangler.app.toml"; add it to
   deploy:workers and to the CI deploy list in .github/workflows/ci.yml.
5. Tests (worker_test/app_worker.test.js): pure helpers — host->tenant parsing (valid,
   apex, www, unknown, uppercase, port suffix), config injection (script lands before
   flutter_bootstrap, HTML-escapes nothing that breaks JSON, missing tenant -> 404 page),
   and the SPA passthrough decision. No live network.
6. Docs: CLAUDE.md (new "Per-Tenant App Delivery" section + the worker table gains
   sias-app), docs/PROVISIONING.md (the DNS prerequisites below, and the new steps).

DNS PREREQUISITES (document, do not attempt): a wildcard A/AAAA or CNAME record for
`*.kubixdesiney.com` proxied through Cloudflare, plus `sias.kubixdesiney.com` routed to
the sias-store worker. Universal SSL covers one subdomain level.

ACCEPTANCE
- npm test green. node --check passes on the new worker.
- Smoke in Node: default.fetch with Host "nagati.kubixdesiney.com" and a stubbed KV
  returns HTML containing window.__SIAS_CONFIG__ with that tenant's projectId; Host
  "kubixdesiney.com" and Host "unknown.kubixdesiney.com" return the branded 404.
- flutter analyze clean; flutter test green; flutter build web --release succeeds.
- Root wrangler.*.toml files for the existing 8 workers are unchanged except the CI list.
```

---

## Prompt 2 — Per-tenant Android APK + download page

```
Read CLAUDE.md and docs/PROVISIONING.md first. You are in the SIAS repo. Prompt 1
(shared sias-app worker serving <tenant>.kubixdesiney.com) is already merged.

CONTEXT
The web app is delivered per tenant at runtime. Android cannot be: firebase_messaging
binds to a build-time google-services.json, so each customer needs their own APK. This
is accepted — build it in CI and hand it to them from their own subdomain.

TASK
1. .github/workflows/build-tenant-apk.yml — workflow_dispatch with inputs: tenant slug,
   plus repo-secret-sourced google-services.json (base64 input or an environment
   secret named per tenant; pick the approach that keeps the JSON out of git and
   document it). Steps: checkout, Flutter, drop google-services.json into
   android/app/, build a release APK with the tenant's dart-defines (worker URLs +
   ALERTSYS_COPILOT_URL), then upload the APK as a workflow artifact AND to the
   tenant's asset location so it is downloadable at
   <tenant>.kubixdesiney.com/app/sias-<tenant>.apk. Gate the job behind the existing
   "provisioning" GitHub environment (manual approval).
2. sias-app worker: serve /app/* for the tenant (from an R2 bucket keyed by tenant, or
   an assets path — choose R2 if the repo already has an R2 binding pattern in the
   backup worker; reuse that style) plus a simple branded /app page with the QR code
   for the APK URL (generate the QR client-side from a tiny inline library or an SVG
   QR implementation — no external CDN).
3. tool/provision_instance.mjs: print the APK build command/URL in the summary TODOs so
   the operator knows the Android step is pending after a new tenant is created.
4. docs/PROVISIONING.md: an "Android delivery" section — how to get google-services.json
   from the tenant's Firebase console, how to trigger the workflow, how supervisors
   install (direct download + "install unknown apps" prompt, or MDM push), and the note
   that the web PWA works immediately with no install.
5. Tests for any new pure helpers (APK path resolution, tenant slug validation).

ACCEPTANCE
- npm test green; workflow YAML lints (actionlint if available, else careful review).
- No google-services.json, keystore, or APK committed to git; .gitignore covers them.
- The /app page renders for a known tenant and 404s for an unknown one.
```

---

## Your steps (Cloudflare dashboard, ~10 minutes, do once)

1. `kubixdesiney.com` zone → DNS → add a proxied wildcard record `*` (A to
   192.0.2.1 placeholder or CNAME; Cloudflare workers routes take over the response).
2. Add `sias` as a proxied record the same way (for the storefront).
3. Workers → `sias-store` → Triggers → add route `sias.kubixdesiney.com/*`.
4. Create a KV namespace named `TENANTS` and note its id — Prompt 1 puts it in
   `wrangler.app.toml`.
5. Confirm Universal SSL is active for `*.kubixdesiney.com` (SSL/TLS → Edge Certificates).

## Still open (deliberately deferred)

- **Gemini billing** — Kubix is capped at 20 requests/day on the free tier. The plumbing
  is proven; it just cannot serve a real customer until billing is enabled and the WF2
  model node is bumped. Do not demo Kubix live to a prospect until then.
- Header Auth on the n8n webhooks (`sias-knowledge-ingest` especially — it currently
  accepts unauthenticated writes into any tenant's knowledge namespace).

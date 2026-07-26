# SIAS - Smart Industrial Alert System App Handoff Notes

Last verified: 2026-07-21 from the local repository.

This file is the working context for future coding agents. Keep it updated when the
app structure, worker deployment, Firebase schema, or CI behavior changes.

## Product Summary

SIAS - Smart Industrial Alert System is a Flutter industrial supervision app for factory alerts. It combines:

- Live alert intake, assignment, claiming, resolution, escalation, and validation.
- Admin and supervisor role flows backed by Firebase Authentication and Realtime Database.
- AI supervisor assignment, shift commander actions, collaboration decisions, predictive risk, and morning briefings.
- Firebase Cloud Messaging plus local full-screen notifications for alert buzz and voice claim actions.
- Offline-aware startup, cached account role data, queued worker triggers, and background sync.
- Voice command and voice claim flows with Android-native lock-screen capture, Sherpa ONNX STT, TFLite speaker verification, and fallback stubs for non-Android platforms.
- Factory hierarchy, assets, custom plant maps, station QR scanning, location tracking, and locator routing.
- SuperAdmin command console (role `superadmin`/`SuperAdmin`) with on-device forecaster training/deployment, an AI Agent Fleet console (per-agent on/off toggles, action logs, stats decks, AI-assist prompt editing, security defense toggles, predictive learning telemetry), Production Manager account provisioning, platform-wide logs/bugs/security/cron/database observability, and a **Hardware Lab** — the factory-wide machinery binding map (binds controllers and their sensors/actuators to real factory machines picked from live plant inventory).
- Pure-Dart gradient-boosted decision tree (GBDT) forecaster (no external inference service) that trains in seconds on uploaded company alert history (CSV/Excel/JSON/SQL dump/PDF), serves live next-24h machine risk on every Production Manager dashboard, grades its own forecasts against realized alerts, and adapts daily on fresh production data.

## Current Versions

- Flutter app package: `alertsysapp`
- Flutter app version: `1.2.1` (source of truth: pubspec.yaml)
- Dart SDK constraint: `>=3.10.3 <4.0.0`
- Flutter SDK constraint: `>=3.38.4`
- CI Flutter version: `3.41.6`
- Worker npm package: `alertsys-worker@1.1.0`
- CI Node version: `20`
- Firebase project alias: `alertappsys`
- Primary target platform: Android. Web, iOS, Windows, Linux, and macOS have support paths, but Android has the full voice/lock-screen stack.

## Repository Map

- `lib/`: Flutter application code. There are currently 212 Dart files (recounted 2026-07-04).
- `lib/main.dart`: Firebase init, service init, providers, localization, auth gate, role router, offline account fallback, and per-tenant runtime config.
- `lib/config/app_config.dart`: Single source for worker URLs, Dart defines, runtime tenant overrides, worker endpoints, and request timeouts.
- `lib/config/runtime_firebase_config.dart`: Web runtime parser for the public Firebase/worker config injected by `sias-app`, with native/test stubs.
- `lib/models/`: Alert, user, collaboration, hierarchy, factory map, shift, and predictive data models.
- `lib/providers/alert_provider.dart`: Main app state facade for alert streams, per-supervisor alert buckets, actions, comments, critical flags, help, and assistance.
- `lib/services/`: Firebase, alerts, auth, FCM, voice, AI, predictions, shifts, hierarchy, location, offline, PDF, and worker queue services.
- `lib/services/ai/`: Dart AI scoring engine, state manager, feedback repository, and score adjuster.
- `lib/services/forecast/`: Pure-Dart GBDT forecaster stack — multi-format dataset parser, tabular feature engineer, histogram gradient-boosting engine, resumable trainer (+ learning diagnosis), app-global training controller (background runs + checkpoint auto-resume), RTDB model store, forecast engine, continuous-learning service (outcome grading + adaptation boosting), and the overview engine that adapts forecasts into the PM dashboard's predictive cards.
- `lib/services/superadmin_service.dart`: Production Manager account provisioning via a secondary Firebase app.
- `lib/services/bug_report_service.dart`: Deduplicated client error reporting into `bugs/client`.
- `lib/screens/`: Admin, supervisor, alert tree, detail, scan, mapping, locator, collaboration, voice, dashboard, hierarchy, and escalation screens.
- `lib/screens/superadmin/`: SuperAdmin command console (theme, shell, AI Training, AI Agents, Production Managers, Overview Monitor, Hardware tabs). The `monitor/` subfolder holds the Overview Monitor war-room (replaced the old Logs tab on 2026-06-19).
- `lib/widgets/`: Shared UI widgets for dashboard, overview, shifts, admin header/tabs, loading/empty/offline states, locator painter, voice command button, and AI logs.
- `android/app/src/main/kotlin/com/example/alertsysapp/`: Native Android method channels and lock-screen voice capture.
- `cloudflare_app_worker.js`, `wrangler.app.toml`: Shared `sias-app` Flutter web/APK delivery worker and its Assets/KV/R2 bindings.
- `web/firebase-messaging-sw.js`: Web push service worker; fetches the current tenant's messaging config from `/__swconfig`.
- `assets/models/conformer_tisid_small.tflite`: Speaker embedding model used by voice auth.
- `worker/`: Modular Cloudflare worker source and helper modules. This is also re-exported by `cloudflare_worker.js` for tests and compatibility.
- `worker_test/`: Jest worker test suite. There are currently 39 worker test files (recounted 2026-07-04).
- `test/`: Flutter unit/widget tests. There are currently 39 Dart test files (recounted 2026-07-04).
- `tool/autonomous_bugfix_agent.mjs`: Autonomous bug-fix runner for UI/worker/log/RTDB health checks, Claude fix generation, OpenAI review gating, direct `main` push, Firebase Hosting deploy, optional worker deploy, `bugs/agent` RTDB run records, and GitHub issue escalation on rejection.
- `functions/`: Firebase Cloud Functions. AI assignment retry triggers (the legacy third-party push function was removed 2026-06-14).
- `database.rules.json`: Realtime Database security rules and validation.
- `.github/workflows/ci.yml`: Flutter analysis/tests/build plus Worker Jest/deploy.
- `.github/workflows/deploy.yml`: Firebase Hosting deploy for Flutter web.
- `README.md`, `TESTING.md`, `PUSH_NOTIFICATION_UPDATE.md`: Broader docs. Some details there may lag the split-worker implementation; prefer this file plus current code for deployment truth.

## Build And Test Commands

Flutter:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --reporter expanded
flutter build apk --debug --dart-define=ALERTSYS_WORKER_SHARED_SECRET=... --dart-define=ALERTSYS_AI_WORKER_URL=https://alert-notifier.aziz-nagati01.workers.dev --dart-define=ALERTSYS_NOTIFY_WORKER_URL=https://alertsys.aziz-nagati01.workers.dev
flutter build web --release --no-wasm-dry-run --dart-define=ALERTSYS_AI_WORKER_URL=https://alert-notifier.aziz-nagati01.workers.dev --dart-define=ALERTSYS_NOTIFY_WORKER_URL=https://alertsys.aziz-nagati01.workers.dev
```

Workers:

```bash
npm install
npm test
npm run test:watch
npx wrangler deploy --config wrangler.ai.toml
npx wrangler deploy --config wrangler.notify.toml
```

Autonomous bug-fix agent:

```bash
npm run agent:bugfix:dry-run
npm run agent:bugfix
```

Active agent runs require `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, git credentials that can push to `main`, and any runtime context secrets needed for Firebase/worker health.

Firebase:

```bash
firebase deploy --only database
firebase deploy --only functions
firebase deploy --only hosting
```

The npm test command is:

```bash
node --experimental-vm-modules node_modules/jest/bin/jest.js
```

The VM modules warning from Node is expected.

## Active Worker Split

SIAS - Smart Industrial Alert System runs **nine** active Cloudflare Workers. The core split keeps notification delivery from competing with AI/security work inside one invocation; the rest carve out ingestion, identity, observability, backups, the shared tenant app shell, and the commercial storefront:

| Worker | Config | Main file | Cron | Role |
|---|---|---|---|---|
| `alert-notifier` | `wrangler.ai.toml` | `cloudflare_ai_worker.js` | `* * * * *` | AI assignment, escalations, security agent |
| `alertsys` | `wrangler.notify.toml` | `cloudflare_notify_worker.js` | `* * * * *` | FCM push fan-out |
| `alertsys-github` | `wrangler.github.toml` | `cloudflare_github_worker.js` | — | Guardian GitHub proxy |
| `alertsys-ingest` | `wrangler.ingest.toml` | `cloudflare_ingest_worker.js` | `* * * * *` | SCADA/PLC/MQTT/historian connectors |
| `alertsys-scim` | `wrangler.scim.toml` | `cloudflare_scim_worker.js` | — | SCIM 2.0 provisioning from IdPs |
| `alertsys-monitor` | `wrangler.monitor.toml` | `cloudflare_monitor_worker.js` | every 5 min | Synthetic probes + SLO/error-budget alerting |
| `alertsys-backup` | `wrangler.backup.toml` | `cloudflare_backup_worker.js` | daily 02:00 UTC | RTDB → R2 snapshots + **alert retention policy** |
| `sias-store` | `wrangler.store.toml` | `cloudflare_store_worker.js` | — | B2B storefront: landing/pricing, Stripe Checkout, purchase webhook → n8n intake |
| `sias-app` | `wrangler.app.toml` | `cloudflare_app_worker.js` | — | Shared Flutter web shell, per-tenant runtime Firebase config, APK download/QR |

The eight data-plane/store workers deploy from CI on protected `main` pushes and via `npm run deploy:workers`; `sias-app` deploys after the web build and is gated by `ENABLE_APP_WORKER_DEPLOY` until the TENANTS KV id and wildcard DNS are configured. Do not hand-deploy a subset — that is how config drift happens.

### Per-Tenant App Delivery (2026-07-21)

`sias-app` is one shared Worker, not one Worker per customer. It serves the Flutter
`build/web` bundle through the `ASSETS` binding for every one-level tenant host:
`https://<tenant>.kubixdesiney.com`. The Worker resolves the slug from `Host`, reads
the tenant's public Firebase web config from the `TENANTS` KV namespace, and injects
`window.__SIAS_CONFIG__` into `index.html` before `flutter_bootstrap.js`. The Flutter
web runtime (`lib/config/runtime_firebase_config.dart`) uses that blob for Firebase
initialization and worker URLs; native builds continue using `firebase_options.dart`
and dart-defines.

The app worker never reads customer data. Firebase client config is public; isolation
comes from each customer's Firebase Auth realm and RTDB rules. `GET /__config` is a
safe probe returning only `{ok, tenant, hasConfig}`, while `/__swconfig` returns the
minimal messaging config used by `web/firebase-messaging-sw.js`.

Provisioning writes the KV value `{tenantCode, company, firebase, workers}` to the
shared namespace and records `appUrl` plus `ingestHost` in
`deploy/tenants/<tenant>/provision-summary.json`. The generated tenant ingest config
contains the more-specific `<tenant>-ingest.kubixdesiney.com/*` route block. DNS and
route activation are deliberate operator steps: create a proxied wildcard record
`*.kubixdesiney.com`, route the wildcard to `sias-app`, keep the more-specific
`sias.kubixdesiney.com/*` route on `sias-store`, and confirm Universal SSL covers one
subdomain level. The app worker returns a branded 404 for the apex, `www`, reserved
labels, and unprovisioned tenant slugs.

Android remains build-time per tenant because FCM consumes `google-services.json`.
The manual `Build tenant APK` workflow takes the base64 file from the protected
`provisioning` environment, publishes a GitHub artifact and uploads
`<tenant>/sias-<tenant>.apk` to the app worker's R2 bucket. The tenant's `/app` page
renders a dependency-free QR code and direct download link; the web PWA is available
immediately without an install.

### Store Worker (2026-07-13)

`sias-store` (`cloudflare_store_worker.js`, `wrangler.store.toml`) is the commercial front door — it is NOT part of the product data plane and never touches customer instances or Firebase. Routes: `GET /` landing page, `GET /buy` intake form, `POST /api/checkout` (validates intake, generates the buyer's tenant code e.g. `NSW#7K2F`, creates a Stripe Checkout Session with all intake fields + tenant code in session metadata), `GET /api/session` (success-page status), `GET /success`, `GET /cancel`, `POST /api/stripe-webhook` (HMAC-verified via `STRIPE_WEBHOOK_SECRET`; maps `checkout.session.completed` → `purchase_completed` and `invoice.payment_failed` → `payment_failed`, forwards to `N8N_INTAKE_WEBHOOK_URL` for provisioning/agent-creation/Brevo email; forward failure returns 500 so Stripe retries — n8n must dedupe on `eventId`), `GET /config` status probe. **Dual payment rails (2026-07-13):** international cards go through Stripe (monthly or annual, USD); Tunisian CB cards go through **ClicToPay (SMT)** — BPC-style REST: `/api/checkout` with `method: 'clictopay'` calls `register.do` (amount in TND millimes, currency 788, annual prepay only since ClicToPay has no subscriptions) and redirects to `formUrl`; `GET /clictopay/return` verifies via `getOrderStatusExtended.do` (paid = `orderStatus === 2`), forwards a `purchase_completed` event (`eventId: ctp_<orderId>`, n8n dedupes) and lands on `/success?ctp_order=`; `GET /api/ctp-order` feeds the success page. TND prices live in `PLAN_CATALOG.tnd*` (Starter 17,880 TND/yr; Growth 35,880 TND/yr). Secrets: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `CLICTOPAY_USER`, `CLICTOPAY_PASSWORD`, `N8N_INTAKE_WEBHOOK_URL` (= `https://kubixdesiney.app.n8n.cloud/webhook/sias-purchase-intake`, n8n WF1 `S7PiPrb3DWm2T7GN`), optional `N8N_WEBHOOK_AUTH`; vars: `SALES_EMAIL`, `STORE_RATE_LIMIT`, `CLICTOPAY_BASE` (prod `https://ipay.clictopay.com/payment/rest`, test `https://test.clictopay.com/payment/rest`), `CLICTOPAY_AMOUNT_EXPONENT` (default 3 = millimes — **verify with a small test payment before go-live**). USD pricing in `PLAN_CATALOG` (Starter $590/mo / $5,880/yr; Growth $1,190/mo / $11,880/yr; Enterprise = mailto sales) — inline `price_data`, so no Stripe dashboard products are required. Pure helpers (`makeTenantCode`, `validateIntake`, `checkoutParams`, `verifyStripeSignature`, `purchaseEventPayload`, `clictopayRegisterParams`, `clictopayPaid`, `ctpPurchasePayload`, `rateLimited`) are covered by `worker_test/store_worker.test.js`.

**Kubix Copilot chat (2026-07-17):** `GET /copilot` serves the buyer-facing chat page (localStorage transcript + sessionId, XSS-safe escape-first markdown renderer, escalation banner, context via `?tenant=&company=&name=&plan=` — the `/success` page deep-links it). `POST /api/kubix` is the server-side proxy: validates (`validateChatRequest`, message ≤2000 chars, sessionId `[A-Za-z0-9._-]{1,80}`), rate-limits 20/min/IP, forwards to secret `N8N_CHAT_WEBHOOK_URL` (n8n WF2 `dI4h0nH3bAsjuzGJ`, optional bearer `N8N_WEBHOOK_AUTH`, 25s AbortController timeout) and returns `{ok, reply, escalated, agent}` — the n8n URL never reaches the client. Pure helpers (`clipText`, `validateChatRequest`, `buildForwardPayload`) are covered in `worker_test/store_worker.test.js`.

**Pricing extraction (2026-07-20):** `PLAN_CATALOG`, `planPrice`, `TND_CURRENCY_CODE`, `tndMinorUnits`, and the new `listPrice(plan, billing, currency)` helper moved to root-level `pricing.mjs` — the single source of truth shared by the store worker (re-exported for backward compatibility) and `tool/generate_quote.mjs`. Never duplicate a price figure outside `pricing.mjs`.

**Invoice-led sales mode (2026-07-20):** `SALES_MODE` in `wrangler.store.toml` `[vars]` controls the storefront's commercial motion — `"quote"` (**current default**) makes `/buy` collect the same intake but submit a **quote request** instead of a card checkout; `"card"` restores the original self-serve Stripe/ClicToPay flow byte-for-byte (both code paths are tested in `worker_test/store_quote.test.js`). In quote mode: `POST /api/quote` validates via `validateQuoteIntake` (adds optional `phone` + `currency` USD/TND/EUR, no `method` field), generates the tenant code, and forwards a `quote_requested` event (`quoteEventPayload`, `eventId: qr_<uuid>`, includes indicative `listPrice` in USD cents + TND) to `N8N_INTAKE_WEBHOOK_URL` — n8n dedupes on eventId same as purchases. Landing CTAs/FAQ/pricing footnote and the `/buy` form (currency picker instead of payment-method radios, no monthly/annual-per-ClicToPay coupling) switch server-side on `salesMode(env)` — no client-side flicker. `GET /config` reports `salesMode`. Card rails (Stripe/ClicToPay) stay fully deployed and untouched; flipping back to `"card"` is a one-var change. `tool/generate_quote.mjs` (`npm run quote --`) renders a branded, signature-ready quote PDF (+ JSON sidecar under git-ignored `quotes/`) from the same `pricing.mjs` figures, with discount/validity/currency options.

**Kubix feedback + i18n + onboarding (2026-07-20):** `POST /api/kubix-feedback` (`validateFeedbackRequest`: sessionId, `messageIndex` 0-999, `verdict` up/down) forwards thumbs-up/down verdicts to secret `N8N_FEEDBACK_WEBHOOK_URL` (same optional-bearer pattern as the other n8n forwards); the copilot page persists verdicts into the local transcript and shows a "thanks" state. `GET /copilot?lang=fr` renders French page chrome via the `COPILOT_I18N` dictionary (`copilotLang(url)` picks `fr` only for that exact query value) — Kubix itself already answers in the user's language, this only localizes labels/placeholders/errors. `GET /welcome` is the buyer-facing "what happens after you buy" onboarding page (four milestones: activation email, first 30 minutes, first integration, meet Kubix), linked from `/success`. Flutter: `AppConfig.copilotUrl` (`ALERTSYS_COPILOT_URL` dart-define) plus a "Kubix Copilot" card on the SuperAdmin **Status** tab (`lib/screens/superadmin/status_tab.dart`, `_KubixCopilotCard`) that deep-links to `/copilot` with `lang=fr` appended when the console runs in French. `tool/kubix_chat_report.mjs` is a pure-Node CSV analytics report (sessions/day, escalation rate, top question words EN+FR-stopword-filtered, median reply length) over a `sias_chats` data-table export.

**Controlled B2B orders dashboard (2026-07-26):** Payment remains offline/manual. Buyer submission creates a private Supabase order in `under_review` and requires the buyer, PM, supervisor, and payment-method fields. The founder dashboard offers two distinct, CSRF-protected actions: **Accept** (`under_review → confirmed`, sends the “we will contact you shortly about payment” event) and **Paid** (`under_review|confirmed|provisioning_failed → provisioning_queued`, including direct virement). Paid repository-dispatches only `orderId` + `tenantCode`; the private GitHub job fetches the rest, provisions and verifies the dedicated Firebase/Cloudflare instance, then creates exactly one `admin` PM and one `supervisor` account and sends single-use activation emails. Legacy `POST /admin/approve` is permanently `410 Gone`. See `docs/ops/AUTOMATIC_ORDER_PROVISIONING.md` and `docs/ops/sias_orders_schema.sql`.

**Legal pack gate (2026-07-20):** `GET /legal`, `/legal/privacy`, `/legal/terms` render the embedded legal markdown (generated copy in `store_legal_content.js` via `npm run legal:embed` from `docs/legal/*.md` — regenerate whenever a draft changes) through a small server-side renderer (`renderMarkdownDoc`, escape-first). The routes hard-404 unless `LEGAL_PUBLISH === "true"` in `wrangler.store.toml` `[vars]` (default `"false"`); footer links appear only when enabled. `npm run legal:lint` (`tool/legal_lint.mjs`) checks the drafts for unresolved `[[PLACEHOLDER]]` markers (reported as a warning count, never blocking), naming consistency (only "KubixDesiney" / "SIAS — Smart Industrial Alert System" allowed), forbidden claims (SOC 2/ISO 27001 certification, bare "guarantee" outside SLA/money-back contexts), and MSA→DPA/SLA cross-references; wired as a non-blocking `legal-lint` job in `ci.yml`. See `docs/legal/COUNSEL_BRIEF.md` for the counsel handoff.

**Security headers (2026-07-20):** every `html()` response now carries a strict nonce-based CSP (`contentSecurityPolicy(nonce)` — `script-src 'self' 'nonce-<random>'`, no `unsafe-inline` script; every `<script>` tag is stamped with the response's nonce), HSTS, and a locked-down `Permissions-Policy`. All inline `onclick=`/`onchange=` handlers across the landing/buy pages were refactored to `addEventListener`. `GET /.well-known/security.txt` (RFC 9116) is public, 1-year expiry, contact = `SALES_EMAIL`.

Worker HTTP auth (2026-07-04; enforced 2026-07-09): the AI and notify workers verify callers with the Firebase **ID token** (`Authorization: Bearer …`, validated against Google's JWKS) or the legacy `x-worker-secret`, controlled by `WORKER_AUTH_MODE` in their wrangler `[vars]` (`off`/`log`/`required`, **currently `required`** after the 2026-07-09 security pass). `/config` stays public for status probes. Client side, `lib/services/worker_auth.dart` (`WorkerAuth.headers()`) attaches both credentials; the ingest + monitor worker-to-worker `/notify` triggers now send `x-worker-secret`, so `WORKER_SHARED_SECRET` must be set on the AI/notify/ingest/monitor workers (the per-minute cron is the durable fallback if a trigger 401s). `ALERTSYS_WORKER_SHARED_SECRET` should be dropped from public app builds and rotated if it ever shipped in one. See `SECURITY_REMEDIATION_2026-07-09.md` for the full remediation of the buyer/Codex security scan (worker fail-closed fixes, GitHub proxy SuperAdmin gate, connector credential host-binding, SCIM stale-key cleanup, tightened alert/notification/user RTDB rules, on-prem PocketBase + SSE hardening).

### AI And Security Worker

- Worker name: `alert-notifier`
- URL: `https://alert-notifier.aziz-nagati01.workers.dev`
- Main file: `cloudflare_ai_worker.js`
- Config: `wrangler.ai.toml`
- Cron: every minute (`* * * * *`)
- Workers AI binding: `AI`

Responsibilities:

- AI assignment and shift AI actions.
- Escalation checks.
- Collaboration approval automation and assistant alert suspension.
- Shift handover generation.
- Predictive model generation and validation.
- Security guard, request rate limits, prompt-injection detection, anomaly scan, `/security-status`.
- AI suggestions and generic AI proxy.
- AI auto-fix endpoints used by CI self-heal flow.
- Worker health write under `workers/health`.

Important cron behavior:

- Acquires `cron_lock/ai`.
- Loads core data with `loadCoreData`.
- Runs `checkEscalations`.
- Runs `runAIAssignments`.
- Runs `processShiftCollaborations`.
- Runs `processShiftEnding`.
- Runs prediction validation every 30 minutes.
- Rebuilds base predictive model every 60 minutes.
- Runs security anomaly scan every 30 minutes.
- Writes health with assignment, collaboration, handover, security, and error metrics.
- The legacy HuggingFace LSTM integration (`kubixdesiney-alertsys-lstm.hf.space`, gated off since the GBDT swap) was DELETED on 2026-07-04 — code, `/predict-lstm` endpoint, and tests. The GBDT forecaster is the only ML path.

HTTP routes:

- `GET/POST /config`
- `POST /ai-proxy`
- `POST /ai-suggest`
- `GET /predict`
- `GET /briefing`
- `GET /suggest-assignee`
- `POST /auto-fix`
- `POST /auto-fix-full`
- `POST /shift-ai-action`
- `POST /validate-predictions`
- `GET /security-status`
- `POST /ai-retry`
- `/` default manual trigger for AI/security work only.

### Notifications Worker

- Worker name: `SIAS - Smart Industrial Alert System`
- URL: `https://alertsys.aziz-nagati01.workers.dev`
- Main file: `cloudflare_notify_worker.js`
- Config: `wrangler.notify.toml`
- Cron: every minute (`* * * * *`)

Responsibilities:

- New-alert push fan-out through queued `/notifications/{uid}/{notifId}` rows.
- Legacy `/alerts` push fallback through `processAlerts`.
- Queued in-app notification fan-out through `fanOutPendingNotifications`.
- Single alert push shortcut through `pushSingleAlert`.
- Single queued notification shortcut through `pushSingleNotification`.
- FCM token cleanup for unregistered tokens.
- Basic request rate limiting.
- Notification worker health under `workers/health/notifyLastRun`.

HTTP routes:

- `GET /config`: notification worker status.
- `POST /notify`: queues a notification cycle. Fast-path payloads:
  - `{ "alertId": "<alertId>" }` tries one alert first.
  - `{ "notification": { "uid": "<uid>", "notifId": "<notifId>" } }` tries one queued notification first.
  - `{ "notifications": [{ "uid": "<uid>", "notifId": "<notifId>" }] }` tries a bounded batch of queued notifications first.
- `POST /notify?sync=1` or `/notify-sync`: runs synchronously and returns counts/errors.
- `/`: manual notification cycle.

Notification limits and locks:

- `MAX_ALERTS_TO_PUSH = 1`
- `MAX_FANOUT = 5`
- `MAX_CRON_FANOUT = 5`
- `PUSH_LOCK_TTL_MS = 2 minutes`
- Notification cron lock path: `cron_lock/notify`.

Push lock fields on alerts:

- `push_sent`: boolean only.
- `push_sending`: boolean lock flag.
- `push_sending_at`: ISO lock timestamp.
- `push_sent_at`: ISO completion timestamp.
- `push_last_error_at`: ISO retryable failure timestamp.
- `push_skip_reason`: string reason when a claimed alert push closes without an FCM send attempt.

Push lock fields on queued notifications:

- `pushSent`: boolean completion flag.
- `pushSentAt`: ISO completion timestamp.
- `pushSending`: boolean lock flag.
- `pushSendingAt`: ISO lock timestamp.
- `pushLastErrorAt`: ISO retryable failure timestamp.
- `pushSkipReason`: string set when the row is closed terminally without an
  FCM send (`busy_supervisor`, `factory_mismatch`, `expired`, `role_mismatch`,
  `no_fcm_token`, `unknown_user`).
- Stale notification locks are retried after `NOTIFICATION_LOCK_TTL_MS = 2 minutes`.

Queued notification send-time gates (2026-07-08):

- `evaluateNotificationDelivery` in `cloudflare_notify_worker.js` is the single
  policy function for both the targeted push path (`pushSingleNotification`)
  and the cron fan-out (`fanOutPendingNotifications`). It returns
  send / terminal-skip / defer; terminal skips write `pushSent: true` +
  `pushSkipReason` so dead rows stop being rescanned by every future cron.
- **`new_alert` rows no longer bypass the busy and factory gates.** Even if a
  producer queued a row for the wrong supervisor, the worker terminally skips
  it at send time: busy supervisors (owner or assistant of an `en_cours` alert,
  or a valid active claim) never buzz, and supervisors only receive alerts
  from their own factory.
- All other queued types (collaboration, help, AI assignment/recommendation,
  presence, handover, critical updates) are personally addressed by their
  producer and still bypass those gates.
- Factory matching is candidate-set based (`factoryCandidates`/`factoryMatches`):
  each side expands `factoryId`/`usine`/`factoryName` into sanitized ids and
  matches on any intersection, so a factoryId-keyed user still matches a
  usine-keyed alert. An alert with no factory info passes (never silently
  drops everyone); a user with no factory assignment blocks.
- Freshness caps: `new_alert` rows older than 15 minutes and any queued row
  older than 24 hours are closed with `pushSkipReason: expired` — a buzz about
  old news is worse than none, and the caps keep the `/notifications` backlog
  bounded. Terminal closes are capped at `MAX_TERMINAL_SKIPS_PER_RUN = 25`.
- Notify health (`workers/health/notifyLastRun`) includes
  `notificationsSkipped` next to `notificationsProcessed`.
- `pushSingleAlert` (fast path) computes busy supervisors with the same
  semantics as the cron path: it queries
  `alerts.json?orderBy="status"&equalTo="en_cours"` (indexed) in parallel and
  feeds it to `engagedSupervisorIds`, so assistants count as busy and stale
  `supervisor_active_alerts` entries no longer block free supervisors. If the
  query fails it falls back to treating every claim entry as busy
  (over-exclude, never over-notify).

No-recipient push behavior:

- `processAlerts` and `pushSingleAlert` now call `skipAlertPush(alertUrl, 'no_recipients')`.
- That writes `push_sent: true`, clears `push_sending`, clears `push_last_error_at`, and records `push_skip_reason`.
- Retryable FCM failures still keep `push_sent: false` through `finishAlertPush(alertUrl, false)`.

Real-time delivery behavior:

- Producers call `POST /notify` immediately after Firebase writes commit.
- The worker still reads RTDB and claims ETag locks before sending, so duplicate producer triggers are safe.
- The one-minute cron remains the durable fallback for missed producer triggers, offline clients, worker errors, and retryable FCM failures.
- New-alert FCM delivery uses the same targeted queue path as collaboration/help/AI notifications: producers write supervisor-only `new_alert` rows under `/notifications`, then call `POST /notify` with exact refs.
- Producers filter recipients before queuing (2026-07-08): `AlertService._queueNewAlertPushNotifications` only writes rows for supervisors of the alert's factory who are not busy (`lib/utils/notification_eligibility.dart` mirrors the worker's gates; busy = owner/assistant of an `en_cours` alert or a valid active claim, computed from the indexed `status == en_cours` query + `supervisor_active_alerts`). If the eligibility lookup fails the producer stays permissive — the worker enforces the same gates at send time.
- Queued `new_alert` rows use the deterministic key `new_alert_<alertId>` so racing producers (alert creator + every stream client) converge on one row per supervisor: supervisors hit the create-only rule on the second write, admin producers skip when the row exists, and a duplicate producer can never reset `pushSent` on a delivered row.
- The `/alerts/{alertId}` push path remains only as a fallback when queued `new_alert` rows cannot be created. It targets supervisors, not admins/Production Managers.
- App-created queued `new_alert` rows use `pushDeliveryMode: notification_queue`; the alert record is marked with `push_delivery_mode: notification_queue` so cron does not send a duplicate `/alerts` fan-out.
- WebSockets/Durable Objects are not the primary wake-up mechanism because Firebase writes do not wake a Worker WebSocket, and mobile background sockets are not reliable; FCM remains the background/offline delivery path.

### GitHub Proxy Worker (Guardian)

- Worker name: `alertsys-github`
- URL: `https://alertsys-github.aziz-nagati01.workers.dev`
- Main file: `cloudflare_github_worker.js`
- Config: `wrangler.github.toml`
- No cron. Pure HTTP proxy, read-only against GitHub plus one `repository_dispatch` write.

Purpose: lets the SuperAdmin Guardian console render **live GitHub Actions runs and Pull Requests inside the app**, styled to match GitHub's own UI, without ever shipping a GitHub token to the client. The worker holds the token server-side; the app authenticates to the worker with the shared `WORKER_SHARED_SECRET` bearer.

HTTP routes:

- `GET /config`: `{ connected, repo }` — whether server-side GitHub creds resolved, and the resolved `owner/name`.
- `GET /runs`: recent workflow runs (mapped to `{id, name, workflow, status, conclusion, branch, event, actor, createdAt, updatedAt, htmlUrl, ...}`).
- `GET /pulls`: open + recently closed pull requests.
- `GET /deployments`: recent deployments.
- `GET /run-jobs?id=<runId>`: jobs + steps for one run (drives the expand-to-jobs view and the 3D pipeline frontier).
- `GET /job-logs?id=<jobId>`: raw stdout **tail** of one job (the real `$ npm test` / build output) for the live Guardian terminal. The worker follows GitHub's 302→signed-blob redirect manually (drops `Authorization` on the second hop), strips per-line ISO timestamps (`stripLogTimestamps`) and tails to ~16 KB on a clean line boundary (`tailText`); returns `''` (never throws) while a job is still warming up. Both helpers are pure + unit-tested in `worker_test/github_worker.test.js`.
- `POST /dispatch`: fires a `repository_dispatch` (`event_type: guardian_drill`) using the worker's server-side token — used by `GithubService.dispatchDrill()` for Guardian incident simulations.

Credential resolution (`resolveCreds` in `cloudflare_github_worker.js`):

- Prefers the RTDB vault once either Guardian credential has been set: `ai_agents/guardian/repo` (plain string, `owner/name`) and `ai_agent_secrets/guardian/githubToken` (string, PAT/App token with `actions` + `pull_requests` read scope), read via a minted Google OAuth token from `FIREBASE_SERVICE_ACCOUNT` + `FB_DB_URL` (same service-account JWT pattern as `cloudflare_ai_worker.js`'s `getAccessToken`). This makes the SuperAdmin console authoritative: changing the repo or token immediately invalidates the previous connection instead of silently falling back to deployed secrets.
- Falls back to Cloudflare secrets/vars `GITHUB_TOKEN` / `GITHUB_REPO` only before the vault is populated. These are bootstrap defaults, not the long-term source of truth.
- 60-second in-memory cache (`_credCache`) avoids refetching the vault on every request. Requests with `fresh=1` or `Cache-Control: no-cache` bypass the cache; `GithubService.status()` and `verify()` use this so edited credentials are tested immediately.

Flutter side: `lib/services/github_service.dart` (`GithubService`) wraps every route — `runs()`, `pulls()`, `deployments()`, `runJobs(id)`, `jobLogs(id)` (raw tail), `dispatchDrill()`, `status()` and `verify()` (deep check: token actually reaches the repo, with a human-readable message for the Verify affordance). `AppConfig.githubWorkerBase` (default `https://alertsys-github.aziz-nagati01.workers.dev`, override via `--dart-define=ALERTSYS_GITHUB_WORKER_URL=...`) is the single source of the base URL.

### Guardian Console — Control / Actions / Pull Requests Subtabs

The Guardian agent lives inside the SuperAdmin **AI Agents** fleet tab (`lib/screens/superadmin/ai_agents_tab.dart`, `_GuardianAgentPanel`) — there is no separate top-level SuperAdmin nav-rail entry for it. The panel has three subtabs:

- **Control**: enabled toggle, Automatic/Human deploy-mode switch (selecting **Automatic** opens `_AutomaticModeWarningDialog`, a deliberate premium warning — Guardian will push verified fixes to `main` and auto-deploy to production with no human in the loop — and only commits the change on confirm), the live **3D self-heal pipeline** + **live terminal** (both in `lib/screens/superadmin/guardian_pipeline_view.dart`, see below), AI provider config (fix model + review model, any of the 15+ providers in `tool/guardian_providers.mjs`), GitHub connection config (repo + token → writes to the RTDB vault above) with a live **Connected / Not connected** badge next to the section title and a **Verify connection** button (animated spinner → green check / red cross via `GithubService.verify()`), knowledge upload, and a draggable incident-simulation toolbar (`dispatchDrill`).

#### Live 3D pipeline + terminal (`guardian_pipeline_view.dart`, 2026-06-18)

The Control subtab's headline is a genuinely live, GitHub-driven pipeline — not a canned animation:

- **`GuardianLiveTracker`** (a `ChangeNotifier`) polls the proxy worker (4s while a run is in progress, ~13s idle). It **latches onto the real workflow run**: after the Simulate button fires the drill it calls `expectDrill()` to grab the next `repository_dispatch`/guardian run; with no simulation it watches the newest run, so an **actual** CI / autonomous-bugfix run lights the schema with zero clicks. It turns the run's jobs+steps into a **proportional frontier** (as real steps complete, stages advance; the first failing step pins the red stage) plus a live terminal feed, and exposes a per-node `PipeStatus` map via `computePipelineNodes(...)` (shared by the offline preview).
- **`GuardianPipeline`** renders the operator's flow-chart (UI checks · Log watcher · CF+cron → Agent orchestrator → Source/Errors/DB → Anthropic Claude API → Test suite · AI review → Fix approved? → Alert human / GitHub PR → CI checks → Auto-merge + deploy) as 3D glass node cards (depth shadow + glow + pulse) wired by a `CustomPainter` that draws bezier connectors with flowing energy particles. Each node glows **amber** while active, **green** when its stage passes, **blood-red** the instant a stage fails (lighting the *Alert human* branch + retry edge); when GitHub is **not connected** the whole schema is desaturated grey behind a "Connect GitHub" veil. Human-review mode shows the PR/CI green but leaves *deploy* awaiting a person.
- **`GuardianTerminal`** shows the real run: a per-job/step checklist (✓/✗/▶ glyphs, colored) followed by the actual stdout tail from `/job-logs` (`$ npm test`, build output, `##[error]`/warning highlighting), auto-scrolled. Offline it falls back to the staged textual preview the Simulate button writes to `ai_agents/guardian/activeRun`.
- **Actions**: `GuardianActionsView` (`lib/screens/superadmin/guardian_github_view.dart`) — a GitHub Actions-faithful live list (own GitHub-dark `GhTheme` palette, deliberately decoupled from the app's `Sa.*` SuperAdmin theme). Event/Status/Branch/Actor filters, status glyphs, branch pills, relative time; tapping a run lazily fetches `runJobs()` and expands to jobs/steps. Polls every 12s while mounted.
- **Pull Requests**: `GuardianPullsView` (same file) — Open/Closed segmented tabs with live counts, search, PR state icons (open/merged/closed), branch pills, draft/bot tags. Polls every 12s while mounted.

Both live views are built only when their subtab is active, so polling stops the moment the SuperAdmin navigates away. `lib/screens/superadmin/guardian_tab.dart` (an empty, never-imported orphan file from an earlier "dedicated tab" iteration) was deleted on 2026-06-18.

### Compatibility And Deprecated Worker Files

- `cloudflare_worker.js` re-exports `./worker/index.js`. Worker tests import it for modular helper coverage.
- `worker/index.js` is a modular worker implementation with AI, assignment, predictions, fanout, and helper exports.
- `cloudflare_workerV2.js` (the deprecated monolith) was DELETED on 2026-06-14. The four test files that imported unique helpers from it (`predictive_model`, `proximity`, `reliability`, `security_prompt_injection`) were repointed to the deployed `cloudflare_ai_worker.js`, which already exports every symbol they need. All 15 worker suites (188 tests) pass against the deployed worker.
- The legacy `wrangler.toml` and `worker/wrangler.toml` (both pointed at the deleted monolith) were also DELETED on 2026-06-14. The old `wrangler.toml` was named `alert-notifier`, so a bare `wrangler deploy` would have overwritten the live AI worker with dead code — removing it closes that footgun.
- Active production deployments use `wrangler.ai.toml`, `wrangler.notify.toml`, and `wrangler.github.toml` (`npm run deploy:ai` / `deploy:notify` / `deploy:github`, or `npm run deploy:workers` for all three; CI deploys with the same `--config` flags on protected `main` pushes). There is no longer any bare-`wrangler.toml` deploy path.

## Worker Secrets And Runtime Config

Set Cloudflare secrets per worker. Do not commit secret values.

- `FB_DB_URL`
- `FB_API_KEY`
- `FIREBASE_SERVICE_ACCOUNT`
- `FB_DB_Secret` if still needed by operational scripts.
- Optional AI/provider secrets used by AI endpoints.
- `WORKER_SHARED_SECRET` / `ALERTSYS_WORKER_SHARED_SECRET` when protected worker requests are enabled.
- Optional `NOTIFY_WORKER_URL` / `ALERTSYS_NOTIFY_WORKER_URL` for AI-worker-to-notification-worker fast triggers; defaults to `https://alertsys.aziz-nagati01.workers.dev/notify`.

`alertsys-github` (`wrangler.github.toml`) secrets: `WORKER_SHARED_SECRET` (required — same value the app sends), `FB_DB_URL` + `FIREBASE_SERVICE_ACCOUNT` (enable the RTDB vault for the GitHub repo/token), `GITHUB_TOKEN`/`GITHUB_REPO` (optional bootstrap fallback before the vault is populated). As of 2026-06-18 these three secrets are pushed automatically by `.github/workflows/ci.yml`'s "Set github worker secrets" step on every protected push to `main`, reusing the repo's existing `WORKER_SHARED_SECRET`/`FIREBASE_SERVICE_ACCOUNT_ALERTAPPSYS` Actions secrets and `FB_DB_URL` Actions variable — no new secret material needed. The actual GitHub PAT is never put in a workflow file; it lives only in the RTDB vault (`ai_agent_secrets/guardian/githubToken`, set via `firebase database:set` or the SuperAdmin GitHub Connection panel).

`FIREBASE_SERVICE_ACCOUNT` is parsed by the workers to mint Firebase custom auth JWTs and FCM OAuth tokens at the edge.

## Flutter Config

`lib/config/app_config.dart` owns cross-cutting constants:

- `ALERTSYS_WORKER_URL`: legacy fallback URL.
- `ALERTSYS_AI_WORKER_URL`: AI/security worker base URL.
- `ALERTSYS_NOTIFY_WORKER_URL`: notification worker base URL.
- `ALERTSYS_WORKER_SHARED_SECRET`: optional request secret.
- `configEndpoint`: AI `/config`.
- `aiSuggestEndpoint`: AI `/ai-suggest`.
- `shiftAiActionEndpoint`: AI `/shift-ai-action`.
- `briefingEndpoint`: AI `/briefing`.
- `predictEndpoint`: AI `/predict`.
- `suggestAssigneeEndpoint`: AI `/suggest-assignee`.
- `notifyEndpoint`: notification `/notify`.
- `notifyTriggerEndpoint`: notification `/`.
- `aiRetryEndpoint`: AI `/ai-retry`.
- Default timeout: 8 seconds.
- Short timeout: 5 seconds.

Use `AppConfig` instead of hard-coded worker URLs.

## Localization / Bilingual EN-FR (2026-06-20)

The whole app is bilingual (English default, full French) with **instant runtime
switching** and a persisted choice. The active language drives every visible
string the moment it flips.

- **Language state:** `lib/providers/locale_provider.dart` (`LocaleProvider`,
  mirrors `ThemeProvider`) — persists `appLanguageCode` to `SharedPreferences`,
  exposes `locale`/`languageCode`/`isFrench`/`toggle()`/`setFrench()`. Provided in
  `main.dart`'s `MultiProvider`; `MaterialApp.locale` is bound to it via
  `Consumer2<ThemeProvider, LocaleProvider>`, so a toggle re-renders the tree.
- **Translation backend (runtime dictionary, keyed by English source):**
  `lib/l10n/app_strings.dart` exposes `context.tr('English text', {params})` (a
  `BuildContext` extension) and `context.isFrench`. It reads the active language
  via `Localizations.maybeLocaleOf` (null-safe → defaults to English, so it never
  crashes in provider-less widget tests). `lib/l10n/strings_fr.dart`
  (`kStringsFr`) holds the French map — **the key is the English string itself**,
  so any un-wrapped/un-translated string still renders correctly in English.
  Placeholders use `{name}` tokens filled from the `params` map (keep the same
  tokens in the French value). Const-map keys must be unique — duplicates are a
  compile error.
- **To localize a string:** wrap the literal as `context.tr('...')` (drop any
  `const` on that `Text`/`Row`), and add one `'English': 'Français'` entry to
  `kStringsFr`. For helpers without a `BuildContext`, thread `context` in (or
  translate at the call site / inside a `State` method via `this.context`).
- **Language toggle widget:** `lib/widgets/common/language_toggle.dart` —
  `LanguageToggle` (translate icon + EN/FR badge, flips on tap) and
  `LanguageSegmented` (EN/FR segmented control, used on login). Both `watch` a
  **nullable** `LocaleProvider?` so they degrade gracefully when no provider is
  in the tree. A `LanguageToggle` sits in every role's header: login top bar,
  supervisor dashboard header, Production Manager header
  (`admin_dashboard_screen_header.dart`), and the SuperAdmin console header.
- **Already-localized via gen-l10n ARB:** `lib/l10n/app_en.arb`/`app_fr.arb` +
  generated `AppLocalizations` still exist (login title, admin tab labels in
  `widgets/admin/pill_tab_bar.dart`, offline banner) and switch with the same
  `MaterialApp.locale`. New work uses the `context.tr` dictionary; both coexist.
- **Coverage status (2026-06-21):** fully translated end to end — infra + all
  four role shells/nav chrome + login; the **entire supervisor experience**
  (dashboard, alert cards/actions, collaboration, locator, QR scan web+mobile);
  the **entire Production Manager experience** (Overview + history/export,
  Supervisors + charts/assignments, Shifts + creation/live/timeline/presence,
  Escalations + collaborations/settings, Hierarchy + dialogs/QR, Alerts tree +
  viz/filters); auth (MFA, voice enrollment, factory mapping); shared
  `alert_detail_screen` and `ai_logs_panel`; and the **entire SuperAdmin
  console** — shell + Production Managers, Access & Identity, Reliability,
  Branding/Theme, Infrastructure tabs, the full AI Training tab (including
  chart legends and metric micro-labels), the full AI Agents fleet (all six
  per-agent control/telemetry bodies — Shift Commander brain, Briefing
  Officer, AI Assist prompt lab, Security Sentinel defense grid, Predictive
  Core model/brain views, Guardian pipeline/GitHub config, plus the custom
  agent editor/detail panels), the Overview Monitor war-room (`monitor/*`:
  command strip, fleet constellation, edge workers grid, database hologram,
  security feed, sessions panel), and the Hardware Lab (`hardware/*`: the
  factory machinery binding map + machine editor/roster/dialogs).
  AI provider/model brand names (Anthropic, OpenAI, Llama, …), agent
  codenames, board/component product names (e.g. "ESP32 DevKit V1"), RTDB
  path/technical identifiers are intentionally left untranslated. A few deep
  service-layer dynamic messages (forecast trainer `diagnose()` reasons)
  remain English-only — they're pure-Dart/non-widget layers without a
  `BuildContext`, a deliberate narrow exception to the one-line
  `context.tr(...)` pattern used everywhere else.
- **Gotcha:** `widgets/admin/header.dart` (`AdminDashboardHeader`/`AdminPillTabBar`)
  is orphan/unused — the live PM header is `admin_dashboard_screen_header.dart`.

## Theme-Aware Brand Colour And Reduced Motion (2026-07-11)

An accessibility pass fixed a dark-mode contrast bug and added a reduce-motion
mechanism. Both follow the same "global mirror set from the `MaterialApp`
builder" pattern already used by `setRuntimeBrand`/`Sa.setDark`.

- **Dark-mode contrast bug (fixed):** many screens declare file-level,
  context-less colour getters — `Color get _navy => ...` in
  `dashboard_screen.dart`, `admin_dashboard_screen.dart`, `hierarchy_screen.dart`,
  `admin_escalation_screen.dart`, and `Color get adminNavy => ...` in
  `admin/admin_dashboard_shared.dart` (`supervisors_tab.dart`'s `_navy` aliases
  `adminNavy`). These previously hard-coded `brandPrimary(false)` /
  `brandPrimaryTint(false)` — i.e. **always the light-mode brand colour** —
  so in dark mode navy text (`#0D4A75`) rendered on the dark card
  (`#1E293B`) at ~1.57:1 contrast, far under WCAG AA's 4.5:1 floor.
- **Fix:** `lib/theme.dart` now exposes `setThemeBrightness(bool isDark)` /
  `appIsDark` (a global mirror, same shape as `setRuntimeBrand`) plus
  theme-aware getters `themeBrandPrimary`, `themeBrandPrimaryTint`, and
  `themeMuted`. `main.dart`'s `MaterialApp` builder calls
  `setThemeBrightness(themeProvider.isDark)` on every rebuild, before any
  descendant screen builds — so the file-level getters listed above now read
  `themeBrandPrimary`/`themeBrandPrimaryTint`/`themeMuted` instead of the
  light-mode-only calls, and resolve correctly in both themes.
- **When adding a new file-level `_navy`/`_muted`-style getter:** point it at
  `themeBrandPrimary`/`themeMuted`, never at `brandPrimary(false)` directly —
  that reintroduces the same bug. Prefer `context.appTheme.navy` /
  `context.appTheme.muted` when a `BuildContext` is available; the top-level
  getters exist only for the older screens that predate `AppTheme`.
- **Regression test:** `test/theme_contrast_test.dart` asserts AA contrast
  (>= 4.5:1) for the brand/muted colours against their real card surfaces in
  both themes, and documents the old ~1.57:1 bug as a `lessThan(2.0)` check
  so it can't silently return.

- **Reduce motion:** `lib/providers/motion_provider.dart` (`MotionProvider`,
  registered in `main.dart`'s `MultiProvider`) persists an in-app "Reduce
  motion" toggle (SharedPreferences). `reduceMotionOf(context)` is the single
  entry point — it returns true if either the in-app toggle **or** the OS-level
  `MediaQuery.disableAnimations` accessibility flag is set, and degrades
  safely (OS flag only) in provider-less contexts like widget tests. Wired
  into the SuperAdmin console's decorative motion: `NeuralBackground` freezes
  the mesh to a single frame, `PulseDot` renders a static dot with a soft
  halo instead of animating, and `SaButton`'s hover lift/opacity transitions
  collapse to zero duration. The toggle itself lives in the Theme Studio tab
  (`theme_studio_tab.dart`, "Motion & Accessibility" card, above the save bar).
  Any new decorative `AnimationController`-driven widget in the SuperAdmin
  console should check `reduceMotionOf(context)` the same way before repeating
  an animation.

- **SuperAdmin console minimum label size:** `Sa.body()`/`Sa.mono()` in
  `superadmin_theme.dart` now clamp to `Sa.minLabelPx` (11px) via
  `math.max(size, minLabelPx)` — this was a systemic fix for dozens of
  7.5–9.5px metadata labels across the console (fleet cards, hardware lab,
  monitor panels, connectors, status tab, etc.) that were under the
  accessibility floor. Call sites keep whatever `size:` they pass (some still
  read `size: 7.5` in source) but the rendered size is always >= 11px. The
  Theme Studio's **miniature dashboard previews** (`_SupervisorPreview`,
  `_PmPreview`, `_SuperAdminPreview` in `theme_studio_tab.dart`) intentionally
  use raw `TextStyle`, not `Sa.body`/`Sa.mono`, so their deliberately small
  preview-scale text is unaffected by the floor.

- **Other accessibility fixes in the same pass:** the supervisor dashboard's
  bottom nav (`widgets/dashboard/dashboard_bottom_nav.dart`) and summary
  cards (`dashboard_screen_views.dart`'s `_SummaryCard`) went from bare
  `GestureDetector` to `MergeSemantics` + `Semantics(button, selected)` +
  focusable/keyboard-activatable `InkWell` (visible focus ring, Enter/Space
  activation) + `Tooltip`. Covered by
  `test/accessibility_bottom_nav_test.dart` (200% text-scale overflow check
  in both themes, selected-button semantics assertion). The supervisor
  dashboard header's dead `clientName: 'SAGEM'` param (never rendered in
  `_Header.build()`) was removed rather than resolved through config, since
  nothing displayed it. The "Click to see details" microcopy became
  "View details" (EN + FR) to match the touch-first supervisor product.

## Flutter Startup Flow

`main.dart` does the following:

- Ensures Flutter bindings.
- Registers `AppLifecycleObserver`.
- Installs global Flutter error handling and a red error widget fallback.
- Safely initializes Firebase with `DefaultFirebaseOptions.currentPlatform`.
- Initializes `ServiceLocator`.
- Configures `OfflineDatabaseService`.
- Starts `BackgroundSyncService`.
- Starts `WorkerTriggerQueue`.
- Registers `firebaseMessagingBackgroundHandler`.
- Starts FCM initialization asynchronously with an 8 second timeout.
- Initializes Shorebird code push object.
- Pre-warms `VoiceService` after the first frame.
- Runs `SmartIndustrialAlertApp`.

Providers:

- `AlertProvider`, also assigned to `FcmService.alertProvider` for lock-screen voice actions.
- `ThemeProvider`.
- `ConnectivityService`.

Routing:

- `AuthGate` listens to Firebase auth state.
- Logged-out users see `LoginScreen`.
- Logged-in users enter `RoleRouter`.
- `RoleRouter` loads `users/{uid}/role` with an 8 second timeout.
- Valid `admin` users see `AdminDashboardScreen`.
- Every non-admin valid role currently sees `DashboardScreen`.
- Offline startup can use cached role/usine from `OfflineAccountCache`; first offline launch without cache shows a retry screen.
- `LocationTrackingService` starts/stops according to role and sign-out/dispose.

## Primary Data Model

Important RTDB roots from `database.rules.json` and code:

- `alerts`
- `alertCounter`
- `users`
- `supervisors`
- `supervisor_active_alerts`
- `notifications`
- `hierarchy`
- `factories`
- `assets`
- `assetCounter`
- `collaboration_requests`
- `collaboration_alerts`
- `help_requests`
- `escalation_settings`
- `ai_decisions`
- `ai_feedback`
- `ai_master`
- `ai_predictions`
- `ai_briefing`
- `ai_runtime`
- `shifts`
- `shift_ai_logs`
- `security/logs`
- `security/actions`
- `workers/health`
- `cron_lock`
- `ai_forecast` (GBDT model trees/metadata, training telemetry, resumable run checkpoint and persisted training dataset under `ai_forecast/training/*`, run history, self-evaluation ledger under `ai_forecast/accuracy/*`, adaptation lock under `ai_forecast/learning/lock`). `ai_forecast/model` now persists the exact ordered `types` list the model learned plus its `featureCount` (feature width = `3 * typeCount + 13`); inference rebuilds the identical vector and a mismatch vs the live `app_config/alertTypes` marks the model stale.
- `bugs/client` (deduplicated app error reports) and `bugs/agent` (autonomous agent run outcomes)
- `hardware_lab` (SuperAdmin Hardware Lab: `bindings/{id}` machine↔device bindings, `machines/{id}` lab-added machine catalog entries)
- `app_config/alertTypes` (tenant-configurable alert-type registry; `auth != null` readable, SuperAdmin-writable; each `{code}` entry is `{ code, label, color, icon, synonyms[], severityDefault, order }`, indexed on `order`). Seeded with the standard set on first read if empty — see the "Configurable Alert Types" section.

Alert fields used across app and workers:

- Identity/location: `id`, `alertNumber`, `type`, `usine`, `factoryId`, `convoyeur`, `poste`, `adresse`, `assetId`.
- Source/origin: `source` (e.g. `Manual` for app/console-created alerts, or `scada:<kind>` stamped by the ingest worker), `sourceType` (optional). Both optional strings; legacy alerts without them show no source badge.
- Lifecycle: `status`, `timestamp`, `takenAtTimestamp`, `resolvedAt`, `validatedAt`, `elapsedTime`.
- Assignment: `superviseurId`, `superviseurName`, `assistantId`, `assistantName`, collaborators.
- Collaboration/help: `helpRequestId`, `helpRequesterId`, `helpRequesterName`, `collaborationRequestId`.
- Escalation/critical: `isCritical`, `criticalNote`, `isEscalated`, `escalatedAt`, `escalationAcknowledgedAt`, `escalationAcknowledgedBy`.
- AI: `aiAssigned`, `aiAssignmentReason`, `aiConfidence`, `aiAssignedAt`, `aiRecommendationPending`, `aiRecommendationStatus`, `aiRecommendedSupervisorId`, `aiRecommendedSupervisorName`, `aiRecommendationReason`.
- Push: `push_sent`, `push_sending`, `push_sending_at`, `push_sent_at`, `push_last_error_at`, `push_skip_reason`, `notificationSent`.
- Comments: `comments`.

User fields used across app and workers:

- `firstName`, `lastName`, `email`, `phone`
- `role`
- `usine`, `factoryId`, `factoryName`
- `status`, `active`, `isActive`
- `fcmToken`
- `currentLocation`
- `aiOptOut`
- `aiCooldownUntil`

Role conventions:

- `superadmin` (also accepted as `SuperAdmin` — role matching is case-insensitive in the app): SuperAdmin command console with forecaster training, Production Manager provisioning, and platform observability. Database rules check both literal spellings.
- `admin`: Production Manager — admin dashboard, broad database access, can manage hierarchy, supervisors, settings, shifts, collaborations.
- `supervisor`: dashboard, alert handling, collaboration/help, voice claim, location tracking.
- Other roles can log in if role is valid, but non-admin routing currently lands on supervisor dashboard.
- `security/*` and `workers/*` reads are limited to the worker service token and `superadmin`; plain `admin` accounts are deliberately excluded (enforced by `worker_test/database_rules_security.test.js`).

## Alert Lifecycle

Typical app path:

1. Admin or integration creates an alert under `alerts`.
2. Alert creation reserves `alertCounter`.
3. Alert initially includes `push_sent: false`.
4. The producer creates supervisor-only `new_alert` rows under `/notifications/{uid}/new_alert_{alertId}` with `pushSent: false` — only for eligible supervisors (same factory, not busy, has FCM token), with a deterministic key so racing producers converge on one row.
5. `WorkerTriggerQueue.enqueueNotificationTriggers(...)` POSTs exact `{ uid, notifId }` refs to the notification worker fast path.
6. Notification worker claims each queued notification with `pushSending: true`, sends FCM with `notifType: new_alert`, then marks `pushSent: true`.
7. The alert record is marked `push_sent: true` / `push_delivery_mode: notification_queue` once queued rows are durable; if queuing fails, `WorkerTriggerQueue.enqueueAlertTrigger(alertId)` uses the legacy `/alerts` fallback.
8. Supervisor claims the alert through `AlertService.takeAlert`.
9. Claiming writes `supervisor_active_alerts/{supervisorId}` and transitions the alert to `en_cours`.
10. Resolving writes resolution fields, clears active claim, and can credit assisted work.
11. Escalation, collaboration, validation, AI feedback, and PDF/export flows build on those same records.

Claim concurrency:

- Client uses RTDB transactions around `supervisor_active_alerts/{supervisorId}` and `alerts/{alertId}`.
- Workers use locks such as `cron_lock/ai`, `cron_lock/notify`, and Firebase ETag `if-match` when claiming push sends.

## Notification And FCM Details

`lib/services/fcm_service.dart` handles:

- Background message setup.
- Navigator key for notification-driven navigation.
- Local notification channels.
- Full-screen lock-screen alert notification.
- Voice action category.
- FCM token refresh/write to `users/{uid}/fcmToken`.
- Notification tap routing to alert detail.
- Android voice lock flow dispatch through `VoiceLockService` and `VoiceCommandParser`.
- Local buzz cancellation with stable alert notification ids.
- Deep-color lock-screen backgrounds (2026-07-08): every local notification is
  `colorized: true` with a deep tone per kind via `_deepNotificationColor` —
  new-alert buzz deep crimson `0xFF7F1D1D`, collaboration deep indigo, help
  deep teal, AI deep violet, cross-factory deep bronze, handover deep navy,
  presence deep green, default deep slate — plus `BigTextStyleInformation` for
  expanded body text.

Notification worker recipient logic:

- Supervisors are eligible by factory unless `allFactories` is set.
- Busy supervisors are excluded unless `allSupervisors` is true.
- Busy means active `en_cours` ownership/assistance or a valid `supervisor_active_alerts` entry for an in-progress alert.
- Optional active status gate accepts `active`, `available`, `online`, `ready`, `active: true`, or `isActive: true`.
- Admin inclusion is controlled per notification type.
- Unregistered FCM tokens are cleared from RTDB only if the stored token still matches the failed token.

Queued notification fan-out:

- Reads `notifications/{uid}`.
- Supports supervisor-only `new_alert`, collaboration, assistant, cross-factory, help, critical update, AI recommendation, AI rejection, alert suspended, confirm-presence, and handover types.
- Fast-path FCM data includes `notifType`, `notificationId`, `recipientId`, and available `alertId`, `collabRequestId`, `helpRequestId`, `shiftId`, `factoryId`, and factory/name fields.
- Writes notification fan-out status fields after FCM send attempts.
- Collaboration/help/AI direct-notification types bypass busy-supervisor and factory gates because they are addressed to specific users. **`new_alert` does NOT bypass** (changed 2026-07-08): busy and factory gates are enforced at send time via `evaluateNotificationDelivery`, with terminal skips recorded in `pushSkipReason` — see "Queued notification send-time gates" above.

AI-to-notification handoff:

- AI/Security worker keeps making decisions and writing alert/shift/collaboration state.
- User-visible AI Commander events are persisted under `notifications/{uid}/{notifId}` with `pushSent: false`.
- The AI worker then calls the Notifications worker with the exact `{ uid, notifId }` reference.
- If that worker-to-worker trigger fails, the queued notification stays pending and the notification cron sweeps it later.

## Voice Stack

Voice command pieces:

- `VoiceService`: platform-facing service wrapper.
- `voice_service_io.dart`: Android/native implementation.
- `voice_service_stub.dart`: non-Android fallback.
- `SherpaSttService`: offline ASR wrapper.
- `sherpa_stt_service_io.dart`: Android production ASR path.
- `VoiceAuthService`: speaker verification wrapper.
- `voice_auth_service_io.dart`: TFLite speaker verification.
- `VoiceLockService`: method channel bridge for lock-screen capture.
- `voice_command_parser.dart`: parses claim, resolve, escalate, dashboard, alerts, fixed, shift ready, join shift, and handover intents.
- `voice_command_dispatcher.dart`: applies parsed voice commands to `AlertProvider`.

Native Android pieces:

- `MainActivity.kt` registers method channels for voice lock and audio.
- `VoiceLockRecorderActivity.kt` is translucent, can show above keyguard, turns screen on, records voice, and returns transcript/audio metadata.
- Android audio channel includes `boostMediaVolume`.

Assets:

- `assets/models/conformer_tisid_small.tflite` is declared in `pubspec.yaml`.

## AI And Prediction Details

Dart-side AI:

- `lib/services/ai_assignment_service.dart`: client-side assignment support.
- `lib/services/ai/ai_scoring_engine.dart`: JS-compatible scoring parity surface.
- `lib/services/ai/ai_decision_repository.dart`: feedback event and summary persistence.
- `lib/services/ai/ai_state_manager.dart`: in-flight, skipped alert, cooldown, and processed history state.
- `lib/services/ai/score_adjuster.dart`: reinforcement adjustments.
- `lib/services/score_reinforcement_service.dart`: feedback-driven scoring adjustments.

Worker-side AI:

- `buildSupStats` builds supervisor statistics from alert history.
- `scoreSupervisor` scores candidates using history, workload, cooldown, status, factory, critical history, feedback, and optional commander mode.
- `runAIAssignments` picks and assigns eligible supervisors.
- `aiAssignAlert` writes alert assignment data, AI decisions, notifications, and cooldowns.
- `processShiftCollaborations` evaluates pending collaboration requests.
- `suspendAcceptedAssistantAlerts` avoids assistant overload after accepted collaboration.
- `processShiftEnding` can generate handover summaries.
- `handleSuggestAssignee` returns best candidate and runners-up.
- `buildPredictiveModel` produces risk curves, predictions, and factory risk.
- `validatePredictions` records prediction accuracy after enough time has elapsed.
- The LSTM path (`_runLstmForecast` and friends) was deleted on 2026-07-04.

Predictive app services:

- `PredictiveRepository`: HTTP and RTDB streams for briefing, predictions, and assignee suggestions.
- `predictive_models.dart`: `MorningBriefing`, `PredictiveModel`, `RiskCurve`, `RiskBucket`, `PredictedFailure`, `FactoryRisk`, `AssigneeSuggestion`, `RunnerUp`.
- `predictive_scope.dart`: user/factory scoping support.
- Overview widgets render briefing hero, predictive failure card, heatmap, insights, stats, and critical alerts.

## Collaboration, Help, And Shifts

Collaboration:

- `CollaborationService` creates, cancels, approves, rejects, expands, and indexes collaboration requests.
- `CollaborationRequest` includes requester, target supervisors, assistant decisions, PM/admin approval metadata, factory/alert context, and PM-added supervisors.
- Cross-factory and cancel-original flows are explicitly modeled.
- `collaboration_alerts/{supervisorId}` indexes shared alert visibility for collaborators.

Help:

- `AlertService.createHelpRequest`, `acceptHelpRequest`, and `refuseHelpRequest` write `help_requests` and notifications.
- Help acceptance writes assistant fields onto the alert.

Shifts:

- `ShiftModel` stores name, kind, start/end minutes, supervisor roster, max supervisors, AI commander flags, randomization, and handover fields.
- `ShiftService` streams shifts, creates/updates/deletes shifts, marks supervisor readiness, streams shift AI logs, and triggers worker shift actions.
- `shift_ai_logs/{shiftId}` stores commander actions and handovers.
- AI commander capabilities are controlled by `handleAssignments`, `handleCollaborations`, `handleCrossFactoryTransfer`, and `fullControl`.

## Factory, Hierarchy, Mapping, And Location

Hierarchy:

- `HierarchyService` manages `hierarchy/factories`, conveyors, stations, asset ids, factory metadata, and active alert counts.
- Assets are tracked under `assets/{assetId}` with station/location metadata and movement history.
- `assetCounter` reserves asset identifiers.
- `Factory`, `Conveyor`, and `Station` model the hierarchy.

Factory maps:

- `FactoryMap`, `MapNode`, `MapEdge`, and `MapCell` model custom plant maps.
- Maps are stored under `hierarchy/factories/{factoryId}/map`.
- `FactoryMappingTab` edits maps.
- `LocatorTab` streams maps and can route from entrance or supervisor position to an alert station.

Location:

- `LocationTrackingService` writes supervisor GPS to `users/{uid}/currentLocation`.
- Proximity tests cover `inferFactoryLocation`, haversine distance, and assignment scoring by location.
- Google Maps support is split across platform-specific utility files.

Station scan:

- `mobile_scanner` handles QR station scanning on mobile.
- Web has a separate scan screen variant.
- Station history panel surfaces asset/station history.

## Offline And Reliability

- `OfflineAccountCache` stores role/usine for offline startup.
- `OfflineDatabaseService` configures local/offline RTDB behavior.
- `BackgroundSyncService` is initialized at startup.
- `ConnectivityService` tracks connectivity for UI and worker queue behavior.
- `WorkerTriggerQueue` persists worker POSTs in SharedPreferences, deduplicates queued requests by URL/body, retries on reconnect, and routes:
  - notify trigger to notification worker.
  - AI retry to AI worker.
  - alert-specific notification trigger with POST body `{ alertId }`.
  - queued-notification trigger with POST body `{ notification: { uid, notifId } }`.
  - queued-notification batch trigger with POST body `{ notifications: [{ uid, notifId }] }`.

## Firebase Rules Notes

Important validation:

- Alerts allow unauthenticated creation only for a minimal first-write shape with address/location/type/timestamp fields.
- Alert `push_sent`, `push_sending`, `notificationSent`, `isCritical` are booleans.
- Alert push timestamp/error/skip fields are strings when present.
- Users are readable to authenticated clients; user writes are scoped to self/admin.
- `users/{uid}/currentLocation` must include numeric `lat` and `lng`.
- Hierarchy and shift writes require admin.
- Collaboration/help reads and writes are open to authenticated admin/supervisor roles.
- `security/logs`, `security/actions`, and `workers` are admin-readable/writable.
- Indexes exist for common query paths: alert factory/status/assignment/push, users role/usine/aiOptOut, collaboration status/timestamp, shifts start/AI commander, security logs/actions.

## Firebase Cloud Functions

`functions/index.js` exports:

- `retryAIAssignmentOnAlertAvailable`: retries AI when an alert becomes available/unassigned.
- `retryAIAssignmentOnSupervisorAvailable`: retries AI when a supervisor becomes active.
- `retryAIAssignmentOnCooldownSignal`: sleeps until cooldown signal expiry, then retries one factory.
- `retryAIAssignmentOnUserCooldown`: fallback cooldown expiry watcher.
- `retryAIAssignmentOnAlertResolved`: retries AI when an alert is validated/resolved.

Operational note:

- The legacy third-party push Cloud Function (`sendAlertPush`) was removed on 2026-06-14 — it was dead code that embedded a hard-coded credential and never actually sent. Push is FCM-only via the notify worker. The previously committed credential still needs rotating at its provider and purging from git history (see `tool/purge_leaked_secret.sh`).

## Testing Inventory

Worker Jest tests (`worker_test/`, 65+ files) — grouped by what they cover:

- **Modular worker (`worker/*.js`) direct tests**: `alerts_module.test.js`, `escalation_module.test.js`, `auth_module.test.js` (real generated-RSA-key JWT signing, no stub), `utils_module.test.js`, `fcm_module_coverage.test.js`, `ai_handler_routes.test.js`, `briefing_handler.test.js`, `suggest_assignee_handler.test.js` — each imports its `worker/*.js` module directly (`jest.unstable_mockModule` for cross-module deps) rather than the deployed monolith.
- **AI/security worker (deployed `cloudflare_ai_worker.js`)**: `scoring.test.js`, `score_supervisor.test.js`, `predictive_model.test.js`, `briefing_helpers.test.js`, `security_prompt_injection.test.js`, `security_siem_export.test.js`, `validation.test.js`, `reliability.test.js`, `worker_auth.test.js`, `model_eval.test.js`, `llm_router.test.js`, `shift_weights.test.js`, `agent_control.test.js`.
- **Notify worker**: `notification_fanout.test.js`.
- **GitHub proxy worker**: `github_worker.test.js`, `github_e2e.test.js`.
- **Ingest worker + connectors**: `ingest.test.js`, `ingest_e2e.test.js`, `connectors.test.js`.
- **Reference edge gateway (`gateway/`)**: `gateway_mapping.test.js`, `gateway_queue.test.js`, `gateway_contract.test.js` (conformance against the real ingest normalizer), plus the pre-existing on-prem `edge_gateway.test.js`.
- **Store worker (`sias-store`)**: `store_worker.test.js`, `store_quote.test.js` (invoice-led SALES_MODE + pricing.mjs round-trip + quote PDF tool), `kubix_copilot.test.js` (feedback/i18n/welcome/chat-report), `legal_lint.test.js` (legal pack linter + `/legal` gate).
- **Route-level integration** (`worker_test/integration/`): `ingest_routes.test.js`, `store_routes.test.js` — real `default.fetch` request/response cycles against an in-memory fake RTDB / mocked network, not just pure-helper imports.
- **RTDB rules**: `database_rules_security.test.js` (incl. adversarial fuzz cases — cross-role self-escalation, foreign-factory claims, credential-vault reads), `firebase_rules_configuration.test.js`.
- **Provisioning/tenant lifecycle**: `provision_owner.test.js`, `provision_instance.test.js`, `verify_instance.test.js`, `tenant_registry.test.js`.
- **Guardian/self-heal pipeline**: `guardian_preflight.test.js`, `guardian_providers.test.js`, `guardian_detect.test.js`, `guardian_drill.test.js`, `guardian_ci_watch.test.js`, `joint_fix.test.js`, `mutation_test.test.js`.
- **SCIM, monitor, retention, on-prem**: `scim.test.js`, `monitor_slo.test.js`, `slo_delivery.test.js`, `retention.test.js`, `onprem_*.test.js` (assignment, changes, escalation, ingest, license, migrate, rbac, retention_backup, retry).
- **Pure utility**: `factory_id.test.js`, `haversine.test.js`, `proximity.test.js`, `auth_gate.test.js`.

Flutter tests (`test/`, 49 files):

- `theme_test.dart` / `theme_brand_test.dart` / `theme_contrast_test.dart` (incl. the WCAG AA contrast regression test), `voice_command_parser_test.dart`, `widget_test.dart`, `accessibility_bottom_nav_test.dart`.
- Model tests for alert, collaboration, predictive, shift, and user models.
- Service tests for AI scoring (+ parity + score-adjuster/reinforcement), alert actions, alert stream, collaboration, offline account cache, predictive scope, connector service, alert type registry, branding/infra/AI-model config, GitHub service, PDF common, telemetry, worker trigger queue, and the data-layer abstraction (`services/data/*` — Firebase/PocketBase/on-prem-auth backends, alert lifecycle, provider backend widget test).
- Forecaster tests: `gradient_boost_test.dart` (loss beats the prior baseline on a separable task, learned rules hold, serialization round-trip, truncation, clone), `forecast_feature_engineer_test.dart` (daily rows, tabular samples, lags/trend/recency, padded inference features), `forecast_trainer_test.dart` (end-to-end learning verdict, cancel, small-dataset rejection, checkpoint resume, adaptation boosting), `alert_record_parser_test.dart` (CSV/JSON/SQL/PDF/timestamps/type normalization), `forecast_overview_engine_test.dart` (forecast→PredictiveModel adapter math, bucket decomposition, learning diagnosis, learning-verdict rule).
- Utility tests for alert metadata, factory ids, notification eligibility, alert-claim-error formatting, and user-friendly error messages.
- Widget tests for the admin dashboard, factory location picker, locator painter, and the Overview tab's `EliteStatCard` (admin overview stat tile — value/spark-line/trend-badge/critical-badge states, light+dark theme).
- Hardware Lab: `hw_machines_test.dart`.

Current verified results (2026-07-20, after the commercial/integration max-out pass — invoice-led storefront, reference edge gateway, Kubix upgrades, provisioning lifecycle tooling, legal-pack linter, security hardening, and the worker coverage ratchet):

- `npm test`: 67 suites passed, 928 tests passed.
- `npm run test:coverage`: statements 89.4%, branches 70.8%, functions 92.5%, lines 89.4% — `coverageThreshold` raised to `{ statements: 84, branches: 65, functions: 86, lines: 84 }` (from `60/54/62/60`), a few points below the measured baseline for headroom.
- `flutter test`: 453 tests passed.
- `flutter analyze --no-fatal-infos --no-fatal-warnings`: clean (style infos only).
- `flutter build web --release --no-wasm-dry-run`: succeeds.

## CI And Deploy

`.github/workflows/ci.yml` (runs on pushes to `main`, pull requests to `main`, and manual dispatch; `FLUTTER_VERSION: 3.41.6`, `NODE_VERSION: 22`):

- **`flutter` job**: checkout, Java 17, Flutter (pub-cache keyed on `pubspec.lock`), `flutter pub get`, `flutter analyze --no-fatal-infos --no-fatal-warnings`, `flutter test --reporter expanded`, then `flutter build apk --debug` + `flutter build web --release --no-wasm-dry-run` (both with the split worker URLs baked in via `--dart-define`), uploads `build/web` as the `web-build` artifact (7-day retention). The AI auto-fix flow described in older notes lives in the separate `autonomous-bugfix-agent.yml` workflow, not in `ci.yml` — `ci.yml` itself has no auto-fix step; a failing Flutter test simply fails the job.
- **`worker` job**: Node 20, `npm ci`, `npm test` (the full Jest suite — all 8 data-plane/store workers, `sias-app`, `tool/`, and `gateway/`), then on direct pushes to `main` only (when `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` are set): deploys the 8 data-plane/store workers via their explicit configs (never a subset — that is how config drift happens) and idempotently pushes the `alertsys-github` worker's bootstrap secrets. The Flutter job deploys `sias-app` after building `build/web` when `ENABLE_APP_WORKER_DEPLOY=true`.
- **`legal-lint` job** (2026-07-20, non-blocking — `continue-on-error: true`): `node tool/legal_lint.mjs` over `docs/legal/*.md`. Surfaces naming/forbidden-claim violations and counts `[[PLACEHOLDER]]` markers loudly without ever gating a deploy (counsel resolution is ongoing work, not a CI blocker).

`.github/workflows/security.yml` (push/PR/weekly cron): `secret-scan` (gitleaks, blocking on the current tree; full-history scan is warning-only pending the documented history purge), `dependency-audit` (`npm audit --omit=dev --audit-level=high` across root/`functions`/`codebasedelta`), and `sbom` (2026-07-20 — `npm sbom --sbom-format cyclonedx --omit dev`, uploaded as the `sbom-cyclonedx` artifact for buyer due-diligence).

`.github/workflows/provision-tenant.yml` (2026-07-20): `workflow_dispatch` (tenant/project-id/workers-subdomain inputs) gated behind the **`provisioning` GitHub environment** (configure required reviewers there) — runs `provision_instance --execute` then a standalone `verify_instance` check, uploads the summary artifact. See "Provisioning lifecycle tooling" above.

`.github/workflows/deploy.yml`:

- Builds Flutter web release with split worker URLs.
- Installs Firebase CLI.
- Deploys Firebase Hosting from `build/web`.

`.github/workflows/autonomous-bugfix-agent.yml`:

- Runs hourly and by manual dispatch.
- Probes deployed UI, Cloudflare worker config/security endpoints, recent logs, RTDB worker health, and configured detection commands.
- Builds structured context from `CLAUDE.md`, source files, logs, DB state, and worker responses.
- Sends the fix request to Claude using `CLAUDE_FIX_MODEL` (default `claude-opus-4-8`), applies safe text-file updates, then validates with Jest, Flutter analysis, and Flutter tests.
- Sends the resulting diff to the OpenAI review gate using `OPENAI_REVIEW_MODEL` (default `o3`).
- Retries up to three times with validation/review feedback.
- If approved, commits on `main`, pushes `HEAD:main`, builds Flutter web, and deploys Firebase Hosting directly.
- If rejected after all attempts, writes the rejection context under `.dart_tool/autofix-agent` and fails the workflow. There is no Slack/email human escalation path.

Required GitHub Actions secrets:

- `WORKER_SHARED_SECRET`
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `FIREBASE_TOKEN`
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `FIREBASE_SERVICE_ACCOUNT_ALERTAPPSYS` — also used by `ci.yml`'s `alertsys-github` secret-push step and `firebase-hosting-pull-request.yml`.
- Repo variable `FB_DB_URL` (Settings → Secrets and variables → Actions → Variables) — also used by `ci.yml`'s `alertsys-github` secret-push step and `uptime.yml`.
- Optional but recommended: `AUTOFIX_GITHUB_TOKEN`
- Optional worker deploy: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` when `AGENT_DEPLOY_WORKERS=1`.

## Important Gotchas

- Do not write strings to `alerts/{id}/push_sent`; database rules require boolean.
- Keep `cloudflare_notify_worker.js` and `worker/alerts.js` behavior aligned when changing notification fan-out.
- Keep `database.rules.json` validation aligned with any new alert fields written by workers or Flutter.
- `cloudflare_workerV2.js` was deleted (2026-06-14); its helper test coverage now runs against the deployed `cloudflare_ai_worker.js`. Do not reintroduce a monolithic worker.
- `README.md`'s top half is the product front door (architecture Mermaid diagram, audience-scoped quickstarts) as of 2026-07-20; deep implementation detail still lives in this file and `docs/`.
- `TESTING.md` was refreshed 2026-07-20 to match the current 8-worker/gateway/store-worker test layout and the real `ci.yml` job list (`flutter`, `worker`, `legal-lint`) — trust it again, but re-verify against `.github/workflows/ci.yml` if CI structure changes.
- `docs/README.md` is the full documentation index (2026-07-20) — link any new doc there, one line per entry.
- A repo-wide scan on 2026-06-14 found no NUL bytes in any source file. `functions/index.js` previously carried a 767-byte NUL tail (now fixed; `node --check` passes). `cloudflare_ai_worker.js` parses cleanly (0 NUL bytes) but may still contain mojibake in string/comment literals; use `rg -a` if normal search treats it as binary.
- `lib/screens/overview_tab.dart` may have local uncommitted changes in this workspace; do not revert user changes.
- Generated Flutter localization files live under `lib/l10n/generated`; update ARB files and regenerate instead of hand-editing generated files when possible.
- `firebase_options.dart` is generated by FlutterFire; avoid manual edits unless intentionally updating Firebase config.
- `node_modules`, `.dart_tool`, `build`, `.wrangler`, and Firebase/Flutter generated caches should not be committed.
- Never put the GitHub PAT used by `alertsys-github` directly in a workflow file or commit — it lives only in the RTDB vault (`ai_agent_secrets/guardian/githubToken`). Rotate it via `firebase database:set` or the SuperAdmin Guardian → Control → GitHub Connection panel.
- On this dev machine, `npx firebase database:set "/some/path" ...` fails with "Path must begin with /" unless run as `MSYS_NO_PATHCONV=1 npx firebase database:set ...` — Git Bash on Windows mangles the leading-slash argument otherwise.
- **Naming (2026-06-27):** the product's display/brand name is **SIAS - Smart Industrial Alert System** (short form `SIAS`) — every UI string, doc, and PDF/notification title was repointed to it on this date. This is distinct from the long-lived internal identifiers that stay as-is and must NOT be renamed to match: the Flutter package/import root `alertsysapp`, the npm worker package `alertsys-worker`, the Firebase project alias `alertappsys`, every `ALERTSYS_*` dart-define / env var, and every deployed Cloudflare worker name/hostname (`alert-notifier`, `alertsys`, `alertsys-github`, `alertsys-ingest`, plus their `*.workers.dev` URLs). Renaming those is a live-infrastructure operation (new worker, new DNS, redeploy, Firebase relink) that was explicitly out of scope for the brand rename. If you ever see the old name spelled out as `Smart Industrial Alert - SIA` or `Smart Industrial Alert (SIA)` in a file, that's stale — fix it to the new name, but never touch an `alertsys*`/`ALERTSYS_*` token while doing so.

## Due-Diligence Remediation (2026-07-04)

A buyer technical review drove a hardening pass. What changed:

- **Database rules — ownership model.** `alerts/$alertId` writes now require a
  privileged role (PM `admin`, superadmin, worker token) or supervisor
  ownership: own the alert, claim it while unassigned, assist (or accept
  assistance on an assistant-less alert), hold its AI recommendation, or share
  it via `collaboration_alerts`. Supervisors can never delete an alert. Push
  bookkeeping fields (`push_sent*`, `push_delivery_mode`, `notificationSent`)
  keep a field-level `auth != null` write so the stream fan-out dedup works
  without ownership. `alertCounter` writes are privileged-only.
- **Parent-grant holes closed.** RTDB cascades a parent `.write` past child
  restrictions, so the blanket `auth != null` writes on
  `supervisor_active_alerts`, `collaboration_alerts`, `notifications`,
  `pm_actions`, and `shift_presence` were removed; child rules now carry the
  real policy (producers create-only for other users' queues). Because the
  roots are no longer world-readable, `OfflineDatabaseService` keeps
  per-user copies synced via `syncUserScopedPaths(uid)` (called from
  `RoleRouter`).
- **Role self-escalation blocked.** `users/$userId/role` validates as
  unchanged unless the writer is admin/superadmin/worker.
- **PII split completed.** `email`, `phone`, and `currentLocation` are
  `.validate: false` under `users/*` — they live only in `users_private`
  (readable by self + admin roles). `UserModel.toMap()` no longer serializes
  email/phone (`toPrivateMap()` exists for the private write). One-time
  cleanup of legacy values: `tool/migrate_user_pii.mjs` (staged, dry-run
  first).
- **Alert retention policy.** The backup worker archives terminal alerts
  older than `RETENTION_DAYS` (default 365) to R2 `alerts_archive/` and
  deletes them from RTDB after each successful daily snapshot (batch-capped).
  This bounds the full-table alert scan the every-minute crons perform — see
  LOAD_TESTING.md for the actual scaling math.
- **Worker HTTP auth.** Firebase ID-token verification landed on the AI and
  notify workers (`WORKER_AUTH_MODE`, currently `log`), as the migration path
  off the client-baked shared secret. See "Active Worker Split" above.
- **LSTM removed** (see cron notes above). **CI deploys all seven workers.**
  `ai_agents_tab.dart` was split into part files (`ai_agents_tab_shift.dart`,
  `_briefing_assist`, `_security_predictive`, `_guardian`) — one library,
  same private namespace, ~1.5k lines each instead of 8.4k in one file.
- After pulling: `firebase deploy --only database` and redeploy the AI,
  notify, and backup workers.

## Recent Local Fix

On 2026-05-15, the notification push lock behavior was fixed:

- No-recipient new alert pushes now close with `skipAlertPush(..., 'no_recipients')`.
- `push_sent` remains boolean-safe and is set to `true` for no-send skip completion.
- `push_sending` and `push_sending_at` are cleared.
- `push_skip_reason` validation was added to `database.rules.json`.
- `worker/alerts.js` was kept in sync with the deployed notification worker.
- `npm test` passes all worker tests after the change.


## Configurable Alert Types (Tenant Registry, 2026-07)

Alert types are no longer a hardcoded standard set — each single-tenant deployment defines its own from the SuperAdmin console, and the operational DB, all UI, and the on-device GBDT forecaster adapt to it.

- **Source of truth:** RTDB `app_config/alertTypes` (SuperAdmin-writable, `auth != null` readable). Each `{code}` child is `{ code, label, color (#hex), icon (key), synonyms[], severityDefault (normal|critical), order }`. The default seed **equals the historical standard set** (`qualite`, `maintenance`, `defaut_produit`, `manque_ressource`) with the same labels/icons/colours and synonyms that reproduce the old `normalizeType` substring behaviour — so a fresh/empty deployment behaves exactly as before with zero migration, and existing alerts with old type strings keep rendering.
- **Model + service:** `lib/models/alert_type.dart` (pure, no Firebase) — `AlertTypeDef`, `kDefaultAlertTypeDefs`, `kDefaultAlertTypeCodes`, `parseHexColor`, `alertTypeIcon`/`kAlertTypeIcons`/`kAlertTypeIconKeys`. `lib/services/alert_type_registry.dart` — `AlertTypeRegistry.instance` (a `ChangeNotifier` singleton) streams the node, seeds defaults if empty (best-effort, SuperAdmin-gated), and **serves `kDefaultAlertTypeDefs` synchronously** before the stream resolves and in provider-less widget tests (mirrors the `context.tr` null-safe pattern). `start()` is called from `main.dart` after Firebase init. `debugSetTypes`/`debugReset` are `@visibleForTesting` injectors.
- **UI:** `typeMeta()` in `lib/utils/alert_meta.dart` resolves label/icon/colour through the registry; unknown/legacy codes degrade to a neutral chip with the raw string. `allAlertTypeCodes()`/`allAlertTypes()` replaced the old `kAllAlertTypes` const and drive every picker/filter/breakdown (admin "Simulate" dialog, `tree_filter_bar`, overview type stats + history/export filters, escalation per-type thresholds — with a default threshold for types missing from `escalation_settings`, supervisor performance breakdowns). Custom labels render English (their source) since operators author them; type CODES are never translated.
- **Management tab:** SuperAdmin console **Alert Types** tab (`lib/screens/superadmin/alert_types_tab.dart`) — add/edit/reorder/delete types (label, colour swatch, icon grid, synonyms, default-severity toggle), Save/Revert against the registry. Code is locked after creation so existing alerts + the trained model keep matching. Shows a stale-model banner (below) and an unsaved-changes hint.
- **Forecaster:** see the type-dynamic plumbing under "Pure-Dart Gradient-Boosted Forecaster". `ai_forecast/model` persists the exact `types` + `featureCount`; if the deployed model's `types` ≠ the live registry the model is **stale** → `ForecastOverviewEngine` clears its forecasts and both PM predictive cards fall back to the statistical model until a retrain (surfaced in the Alert Types tab). A width-mismatch guard in `ForecastEngine.computeForecasts` prevents mis-indexing.
- **Tests:** `test/services/alert_type_registry_test.dart` (defaults, custom set, unknown-type rendering, model round-trip), plus dynamic-type cases in `gradient_boost_test`/`forecast_feature_engineer_test`/`forecast_overview_engine_test` (incl. the stale-width fallback) and `alert_record_parser_test` (custom synonyms). Rules coverage in `worker_test/database_rules_security.test.js`.

## SuperAdmin Console And On-Device Gradient-Boosted Forecaster (2026-06-10, GBDT swap 2026-06-11)

A full SuperAdmin tier was added on top of the existing admin/supervisor roles, together with a working, trainable machine-learning forecaster and a platform-wide observability surface. On 2026-06-11 the original pure-Dart LSTM was replaced end-to-end by an XGBoost-class gradient-boosted decision tree (GBDT) engine with continuous learning — better accuracy on tabular alert history, trains in seconds instead of minutes, no scaler/window fragility, and it grades its own forecasts against reality.

### Role And Routing

- New role `superadmin` (case-insensitive in the app; rules accept both `superadmin` and `SuperAdmin` literals). Create the account record manually in Firebase: `users/{uid}/role = "SuperAdmin"`.
- `RoleRouter` (lib/main.dart) normalizes the role and routes superadmin to `SuperAdminDashboardScreen`; `OfflineAccountCache.normalizeRole` persists the canonical lowercase form for offline startup.
- Database rules: superadmin can read/write `users/{uid}` (for Production Manager provisioning), read `security/*`, `workers/*`, `bugs`, and write `ai_forecast`. Plain `admin` (Production Manager) accounts remain excluded from `security/*` and `workers/*` reads — enforced by `worker_test/database_rules_security.test.js`.
- Deploy rules after pulling: `firebase deploy --only database`.

### SuperAdmin Console (lib/screens/superadmin/)

Futuristic "Command Center" design with an animated neural-mesh vector background (`superadmin_theme.dart`: `SaPalette`, `NeuralBackground`, `GlassPanel`, `GlowChip`, `PulseDot`, `SaButton`, …). Since 2026-06-11 the console follows the app-wide `ThemeProvider` (light/dark): the dashboard build calls `Sa.setDark(...)` and a sun/moon toggle sits in the console header. `Sa` color tokens are palette *getters* (deep-space dark + arctic light), so never capture `Sa.*` colors inside `const` expressions. Terminal-style surfaces (console viewer, raw JSON blocks, DB schema map) intentionally stay dark in both themes via the fixed `Sa.term*` constants. Decorative painters (neural mesh, DB map) are throttled to ~25–30fps behind RepaintBoundaries, the header clock/status chips are isolated self-refreshing widgets, and `PulseDot` paints its ripple outside a fixed-size box so status chips never shift layout. Key tabs (the shell `superadmin_dashboard_screen.dart` wires eleven, incl. a **Status** page — `status_tab.dart`, added 2026-06-29 — a public-status-page-style board for the Cloudflare workers, GitHub proxy and Firebase RTDB/Auth, each with a live reachability pill + rolling session-uptime strip; and an **Alert Types** page — `alert_types_tab.dart` — the tenant alert-type registry manager, see "Configurable Alert Types" below):

1. **AI Training** (`ai_training_tab.dart`): upload company alert history, watch deployed-model status plus the live continuous-learning ledger (forecasts graded, precision/recall, Brier score, last adaptation), auto-tuned but always-visible/editable hyperparameters (boosting rounds, learning rate, max depth, min leaf samples, subsample, L2 — AUTO-TUNE recomputes them from the dataset shape), live training monitor (gradient progress bar, train/val loss curves, accuracy/F1 curves, LEARNING/NOT-LEARNING verdict), next-24h forecast preview, one-click deploy.
2. **Alert Types** (`alert_types_tab.dart`): CRUD + reorder over the tenant alert-type registry (`app_config/alertTypes`) — label, colour, icon, parser synonyms, default severity. Surfaces a **stale-model banner** when the deployed forecaster's `types` no longer match the registry (retrain required). See "Configurable Alert Types" below.
3. **AI Agents** (`ai_agents_tab.dart`, added 2026-06-12): the AI Agent Fleet console — see "AI Agent Fleet" section below.
3. **Production Managers** (`production_managers_tab.dart`): provision/revoke Production Manager (`role: admin`) accounts and send password resets. Account creation runs through a secondary Firebase app (`superadmin_service.dart`) so the SuperAdmin session is never replaced.
4. **Overview Monitor** (`monitor/overview_monitor_tab.dart`, added 2026-06-19, replaced the old `logs_tab.dart`): a holographic "war-room" that lays the whole platform bare for the IT team in one scroll. All live state flows through a single `MonitorController` (`monitor/monitor_data.dart`) — worker health pulses, `ai_agents/*`, the `users` node (→ live sessions), `telemetry/daily/{today}`, `security/actions`, `bugs/client`, the `HwMachineStore` factory catalog, a REST shallow DB probe, and the `alertsys-github` proxy reachability. Sections (all theme-aware, capped-fps painters behind RepaintBoundaries): a KPI **command strip** + system-posture banner, **Operational Insight** ring gauges (fleet/hardware/database/sessions), the **Factory Digital Twin** (`monitor/factory_hologram.dart` — live isometric 3D plant floor: conveyors as belts, every `MACH-XXX` an extruded status-lit pillar with energy pulses, per-factory selector), the full-width **AI Agent Fleet constellation** (`monitor/fleet_workers.dart` — enlarged 2026-06-29: elliptical orbit, twinkling starfield, per-agent activity-ring orbs and a fleet stat strip; **the Cloudflare edge-workers heartbeat grid was removed from here and now lives in the new Status tab** — `WorkersGrid`/`_WorkerCard` were deleted), the **Database Conception** topology (`monitor/database_hologram.dart` — same REST shallow probe + RESCAN as before), a **Security & Integrity** threat feed (`monitor/security_feed.dart` — edge Sentinel enforcements + client-bug budget), and **Active Sessions** (`monitor/sessions_panel.dart` — presence from each user's `lastSeen`, online ring + crash-free %). Shared holographic widgets/painters live in `monitor/monitor_kit.dart` (`HoloPanel`, `HoloHeader`, `KpiReadout`, `RingGauge`, `Heartbeat`, `StatePip`). The old Logs sub-sections (raw AppLogBuffer console, standalone bugs list) were dropped; `AppLogBuffer` itself stays (it still feeds `bugs/client`). Note: never wrap a `monitor/` panel in `IntrinsicHeight` — they contain `LayoutBuilder`s; use `Row`+`Expanded`+`CrossAxisAlignment.start` like the orchestrator does.
5. **Hardware** (`hardware_tab.dart` → `hardware/hardware_lab.dart`): the **Hardware Lab** — see the "SuperAdmin Hardware Lab" section below.

### SuperAdmin Hardware Lab (2026-06-18, reduced to the factory machinery map only on 2026-06-22)

`lib/screens/superadmin/hardware/` is now just the **factory-wide machinery binding map** for the hardware/IoT engineering team — it binds controllers (ESP32, Arduino, …) and their sensors/actuators to real factory machines picked from live plant inventory. It is pure-Dart (no native deps) and self-contained. There is a single view; the Hardware tab no longer has DESIGN/CONNECT/FACTORY MAP sub-tabs — the binding map *is* the whole tab.

> **Removed on 2026-06-22:** the drag-and-drop circuit designer (canvas, component catalog, wire routing), the Arduino IDE + AI code generation, the circuit simulator/interpreter, and the live ESP32→Firebase connectivity tester were deleted entirely, along with the `/hardware-codegen` worker endpoint and the `hardware_lab/circuits` + `hardware_lab/telemetry` RTDB nodes. `HwDeviceBinding` no longer carries a `circuitId` — bindings only reference a controller type + peripheral list now, not a designed schematic. If you're looking for that code in history: `hw_canvas.dart`, `hw_code_panel.dart`, `hw_ai_codegen.dart`, `hw_connectivity.dart`, `hw_painters.dart`, `hw_runtime*.dart`, and their `test/screens/superadmin/hardware/` counterparts.

Files:

- `hw_models.dart`: pure data layer. `HwControllerDef` + `kHwControllers` (ESP32 DevKit, ESP32-C3, ESP8266 NodeMCU, Arduino UNO/Nano/Mega 2560, Raspberry Pi Pico) and `hwControllers()`/`hwControllerLabel()` for the binding picker, plus `HwDeviceBinding` (machine ↔ controller/peripherals) and the `hwNewId()` id helper.
- `hw_machines.dart`: the **machine catalog** (`HwMachine`, `HwFactoryCatalog`, `HwMachineStore`). Reads real `MACH-XXX` machines from `/assets` (read-only, **including archived/deleted** ones) plus lab-added machines under `hardware_lab/machines` (SuperAdmin-writable — `/assets` is admin-only), and the factory→conveyor tree from `hierarchy/factories`. Each machine/conveyor carries an `HwMachineStatus` (ACTIVE / OUT OF SERVICE / DELETED); conveyor status is derived from its machines.
- `hw_factory_binding.dart` (+ `hw_factory_binding_*.dart` parts: cards, fields, binding editor, machine dialog/editor/roster): the **factory machinery map** — a Plant-Machines roster (status-badged chips, incl. deleted) + an "Add machine" dialog (`_MachineEditor`: id/name/description/factory/conveyor/status), and `HwDeviceBinding`s grouped by factory. The binding editor picks factory (by name), conveyor line and machine (MACH-XXX) from **dropdowns with status badges** — no free-typing — and the controller from the full `hwControllers()` list; e.g. MACH-001 ← ESP32 + heat sensor + 4 colored buttons + LED bank. Deploy status lifecycle: designed/wired/verified/live.
- `hw_store.dart`: RTDB persistence — bindings at `hardware_lab/bindings/{id}`; lab machines at `hardware_lab/machines/{id}` via `HwMachineStore`.
- `hardware_lab.dart`: the orchestrator — loads/saves bindings through `HwLabStore` and renders `HwFactoryBindingView` directly (no sub-tab navigation).

RTDB: `hardware_lab/{bindings,machines}` is SuperAdmin-only r/w (`database.rules.json`, the whole `hardware_lab` subtree); real machines are also read from `/assets` (`.read: auth != null`).

### AI Agent Fleet (2026-06-12)

`lib/screens/superadmin/ai_agents_tab.dart` presents six named agents as a fleet (horizontal agent cards + per-agent detail panels), each with an on/off toggle, an in-depth action log (tap any row for the full record), and a stats deck. Master switches and settings live under `ai_agents/{id}` in RTDB (`enabled`, `settings/*`, `promptTemplate`, worker-written `stats/*` + `logs/*`); the AI worker honors them through a 60-second cached control plane (`_loadAgentControl` in `cloudflare_ai_worker.js`) that **fails open** — a control-plane read error never takes agents down. Rules: `ai_agents` is readable by any authed client (PM dashboards/learner read switches) but writable only by superadmin or the worker service token (enforced in `worker_test/database_rules_security.test.js`).

- **Shift Commander (`shift`)**: flattened `shift_ai_logs` activity with kind breakdown bars and health-pulse stats. Disabling gates `runAIAssignments`, `processShiftCollaborations`, `processShiftEnding`, and `runShiftPresenceCheck` in the cron and the manual trigger (escalation checks always run — platform safety, not an agent). Worker bumps `ai_agents/shift/stats` per cron with atomic increments.
- **Briefing Officer (`briefing`)**: latest dispatch view, archive/factory-scope counts, REGENERATE NOW button (GET `briefingEndpoint?force=1`). Disabling makes `/briefing` serve the cached latest (any date) and never spend a Llama run; generation bumps `ai_agents/briefing/stats` and logs a row.
- **AI Assist (`assist`)**: Prompt Lab — the exact Llama prompt template is editable and deployable to `ai_agents/assist/promptTemplate` (placeholders `{type} {description} {usine} {convoyeur} {poste} {history}`, filled by `_assistFillPrompt`; override is sanitized + capped at 8KB; revert deletes the node). Knowledge Base shows the validated resolutions the agent cites (query `alerts` by `status == validee` with `resolutionReason`). Service log + served counter come from worker writes in `handleAiSuggest`. Disabling returns the static fallback suggestion with `agentDisabled: true`.
- **Security Sentinel (`security`)**: Defense Grid toggles under `ai_agents/security/settings/{promptInjection,rateLimiting,sanitization,anomalyScan,siemExport}` — `_securityGuard` checks them per-request (rate limit / injection scan / sanitize each individually gated), the cron gates the anomaly scan and SIEM flush. Threat mix bars + enforcement log from `security/actions`.
- **Predictive Core (`predictive`)**: model identity card (reads `ai_forecast/model/*` metadata children individually — the weights blob never enters the screen; refreshes on `version` bumps), precision/recall/Brier ring gauges from `ai_forecast/accuracy/latest`, Brier-per-day trend chart from `accuracy/history`, adaptation-budget bar (adaptedRounds/60), graded-day log. Settings `ai_agents/predictive/settings/{adaptationEnabled,outcomeGrading}`: `adaptationEnabled` is honored by the Dart `ForecastContinuousLearner` (via `ForecastModelStore.predictiveAgentFlag`), `outcomeGrading` by the worker learner.
- **Guardian (`guardian`)**: under-maintenance placeholder with radar-scan animation; toggle disabled.

**Removed on 2026-06-27:** the fleet rail's trailing "+ DEPLOY AGENT" tile and the entire
operator-created custom-agent feature it opened — `_AgentEditorDialog` (create/edit form:
name, codename, description, tasks/skills text + file attach, icon palette, accent swatch,
LLM provider + API token), `_CustomAgentPanel` (generic detail view for a custom agent),
`_DeleteAgentDialog`, the `ai_agents/registry/{id}` + `ai_agent_secrets/{id}` read/write
plumbing, and `_AgentSpec.fromRegistry`. It was pure UI: no worker ever read
`ai_agents/registry` to actually run a custom agent's provider/model/token, so "deploying"
one created a cosmetic fleet card with zero behavior behind it. The six built-in agents
(`shift`, `briefing`, `assist`, `security`, `predictive`, `guardian`) and their toggle/log/
stats plumbing under `ai_agents/{id}` are unaffected. `database.rules.json`'s `ai_agents`
and `ai_agent_secrets` rules were left as-is (still needed by the six built-ins and by
Guardian's `ai_agent_secrets/guardian` credential).

### Worker-Side Forecast Outcome Learner (2026-06-12)

`_runForecastOutcomeCycle` in `cloudflare_ai_worker.js` (cron, every 30 min on the validation cadence, gated by the predictive agent + `outcomeGrading`) makes the GBDT continuous-learning loop survive with zero dashboards open: it (1) snapshots tomorrow's pending outcome from the latest `ai_predictions/forecast` publish into `ai_forecast/accuracy/pending/{yyyy-MM-dd}` (first write wins, same `usine~conv~poste` key scheme as the Dart learner), and (2) grades fully elapsed pending days against `alertsMap` using the tuned per-type decision thresholds the console mirrors to `ai_forecast/model/thresholds` at deploy/adapt time (added to `ForecastModelStore.saveModel`/`saveAdaptedModel`), folding hits/misses + Brier into the same `ai_forecast/accuracy/{latest,history}` ledger. Adaptation boosting itself stays on-device in Dart — the worker only grades.

### PM Predictive-Card Fix (2026-06-12)

The PM "not enough data" bug had three causes, all fixed in `forecast_overview_engine.dart`: (1) live inference fed **raw** `AlertModel.type` strings into features trained on canonical types — `updateAlerts` now routes through `AlertRecordParser.normalizeType`; (2) `overlayFor` discarded the whole AI overlay when no machine crossed the 0.2 failure floor, silently falling back to the often-absent statistical model — the overlay (risk curves are always real model output) is now kept, and when the plant is calm the failure list falls back to the top entries above a relaxed `kQuietFloor` (0.01) so the PM always sees ranked live forecasts; (3) the alert-stream change detector compared only list length — it now uses a length+newest-timestamp signature. Factory scoping is also case/whitespace-insensitive now.

### Pure-Dart Gradient-Boosted Forecaster (lib/services/forecast/)

The forecaster is a real second-order (Newton) gradient-boosting engine trained on-device — the same formulation XGBoost/LightGBM use, with no HuggingFace or external inference dependency:

- `forecast_types.dart`: default types (`kForecastAlertTypes`, the fallback/standard set), the base daily columns (`kDailyFeatureCols`) and 25 tabular columns (`kForecastFeatureCols`) for that default set, plus **type-dynamic** schema builders `dailyFeatureColsFor(types)`, `forecastFeatureColsFor(types)` and `forecastFeatureCountFor(N)` (= `3*N+13`). The forecaster is dynamic end-to-end: the active ordered type list is threaded in at train time (from `AlertTypeRegistry`) and every stage (feature engineer, booster, model, trainer, engine) sizes itself to it. `AlertRecord`/`DatasetSummary`/`FeatureSample`, `ForecastTrainingConfig` (auto-tuned; rounds/lr/depth/minLeaf/subsample/colsample/L2/patience/`posWeightCap` all visible+editable), `RoundStat` (round 0 = baseline), `MachineForecast`.
- Type-dynamic plumbing: `ForecastFeatureEngineer.buildDailyRows(records, {types})` carries `DailyRow.typeCount`; `GradientBoostModel` stores its `types` list (round-trips through JSON, defaults to `kForecastAlertTypes` for legacy models); `GbdtBooster`/`ForecastTrainer.train`/`diagnose` take a `types` param; `ForecastEngine.computeForecasts` uses `model.types` and **guards on feature width** (skips inference rather than mis-indexing a stale model); `ForecastModelStore.saveModel` writes `types` into `ai_forecast/model`; `ForecastOverviewEngine.modelStale` compares deployed `types` to the live registry and falls back to the statistical model when they differ; `ForecastTrainingController` captures the active registry types at upload, bakes them into the model, and re-adopts a resumed model's types.
- `alert_record_parser.dart`: ingests CSV/TSV, JSON (incl. Firebase RTDB exports), Excel (.xlsx), MySQL dumps (.sql INSERT parsing with CREATE TABLE fallback), and PDFs (table extraction via Syncfusion + heuristic line scan). Header-synonym mapping (EN/FR), flexible timestamps (ISO, epoch s/ms, dd/MM/yyyy, Excel serial). `normalizeType(raw, {types})` maps free-text type values onto the configured codes via each `AlertTypeDef.synonyms`; `types` defaults to `kDefaultAlertTypeDefs`, whose synonyms reproduce the historical substring behaviour so old history parses identically.
- `forecast_feature_engineer.dart`: per-machine gap-free daily rows (same `_buildDailyFeatures` schema as the worker), then tabular samples per machine-day: today's snapshot, tomorrow's calendar context, total lags (t-1/t-2), per-type 7d rolling counts, 7/14d totals, week-over-week trend, per-type recency (capped 30d), critical pressure. No scaler — trees are scale-invariant. `buildInferenceFeatures` pads quiet machines to today.
- `gradient_boost.dart`: `BoostTree` (flat-array regression tree), `GradientBoostModel` (per-type ensembles + prior log-odds base scores, per-type `thresholds` for "alert called" classification, `truncated()` best-round snapshots, JSON (de)serialization, `baseRounds`/`adaptedRounds` bookkeeping), and `GbdtBooster` (histogram split finding with ≤64 quantile bins, leaf weights `-G/(H+λ)`, gain pruning, row/feature subsampling, shrinkage folded into leaves, class-imbalance weighting via per-type pos-weights capped at `config.posWeightCap`, `bestValThresholds()` grid-searches per-type decision thresholds that maximize validation F1, weighted-BCE/accuracy/macro-F1 eval from cached margins using those thresholds instead of a fixed 0.5).
- `forecast_trainer.dart`: deterministic seeded train/val split, a round-0 baseline stat so curves show the real improvement over the prior, one tree per type per round with ~10ms cooperative yielding (UI stays smooth on web/mobile), early stopping with best-round truncation, a quantitative learning verdict (best val loss <= 97% of the round-0 baseline), `diagnose()` for NOT-LEARNING explanations, checkpoint resume (`resumeModel`/`startRound`/`resumeStats`), and `adapt()` — the continuous-learning entry point that boosts a few stiffly-regularized extra trees onto a deployed model. After training, the final model's `thresholds` are set from `bestValThresholds()` on the held-out validation set, and live `RoundStat.valF1` curves use those same tuned thresholds (not a fixed 0.5) so F1 reflects genuine probability separation under class imbalance.
- `forecast_training_controller.dart`: app-global `ChangeNotifier` singleton (`ForecastTrainingController.instance`) that *owns* the dataset + training run; the AI Training tab is only a view of it. Training survives tab switches, console navigation, and sign-out while the app stays open. It checkpoints trees + round stats + config to `ai_forecast/training/checkpoint` (every ~10s) and persists the uploaded dataset (compact row encoding) to `ai_forecast/training/dataset`, so a closed browser tab/app auto-resumes the run on the next console open (`ensureResumed()`, called from `SuperAdminDashboardScreen.initState`). If another live session owns the run it spectates via `ai_forecast/training/latest` telemetry and takes over when the owner's heartbeat goes stale (>150s). A finished-but-undeployed run is restored from the checkpoint for one-click deploy; deploying clears the checkpoint (the dataset blob is kept for retraining).
- `forecast_model_store.dart`: persists the ensemble/metadata to `ai_forecast/model`, run history to `ai_forecast/history`, live training telemetry to `ai_forecast/training/latest`, the resumable checkpoint to `ai_forecast/training/checkpoint`, the persisted dataset to `ai_forecast/training/dataset`, the self-evaluation ledger to `ai_forecast/accuracy/{latest,history,pending}`, and the cross-dashboard adaptation lock to `ai_forecast/learning/lock`. Deploying a fresh model resets the accuracy ledger.
- `forecast_engine.dart`: on-device inference over recent alerts; publishes throttled snapshots to `ai_predictions/forecast`.
- `forecast_learning_service.dart` (`ForecastContinuousLearner`): the continuous-learning loop, driven opportunistically from open PM dashboards (self-throttled to one cycle per 30 min, no server component). (1) **Self-evaluation** — each day the engine snapshots what the model predicts for tomorrow under `accuracy/pending/{yyyy-MM-dd}`; once that day elapses, any dashboard grades it against the alerts that actually happened (hit/miss at p>=0.5 + Brier score) and folds the result into the rolling `accuracy/latest` ledger shown in the console. (2) **Adaptation** — at most once per ~20h (lock + re-read after claim), it boosts 6 extra trees per type onto the deployed ensemble from the last 120 days of live alerts (small lr, stiff L2, capped at +60 adaptive rounds until the next full retrain), bumping the model `version` so every dashboard streams the update.

### Production Manager Dashboard Integration

The deployed forecaster feeds the two existing predictive cards on the admin Overview tab directly:

- `lib/services/forecast/forecast_overview_engine.dart` (`ForecastOverviewEngine`, a `ChangeNotifier` owned by `AdminOverviewTab`) streams `ai_forecast/model`, re-runs on-device inference whenever the alert stream changes (throttled to 15s), keeps `ai_predictions/forecast` fresh (one write per 10 minutes across all open dashboards), and drives the `ForecastContinuousLearner` cycle.
- Its `overlayFor(selectedUsine, statisticalModel)` adapter converts per-machine `MachineForecast`s into the `PredictiveModel` shape both cards already render: one `PredictedFailure` per machine-type above a 0.2 probability floor (confidence = model probability, ETA heuristic `(1-p)*24h`, past/critical counts and last-seen from local alert history), and per-type `RiskCurve`s where the plant-wide day probability `1-Π(1-p_machine)` is decomposed exactly over twelve 2h buckets along the statistical curve's intra-day shape (falling back to the hour-of-day histogram, then uniform).
- `PredictiveFailureCard` and `PredictiveRiskHeatmap` take a `forecastLive` flag: subtitle and badge switch to "AI · LIVE"/"AI", and the statistical validated-accuracy badge hides (it doesn't describe the forecaster). With no deployed model — or no machine forecasts in the selected scope — both cards keep the statistical edge model as fallback.
- Adapter math and the learning diagnosis are covered by `test/services/forecast_overview_engine_test.dart`.

### Bugs Pipeline

- `lib/services/bug_report_service.dart` hooks `AppLogger.onErrorEntry` (every ERROR-level log) and `PlatformDispatcher.onError`, dedupes by FNV-1a hash, rate-limits (5 min/hash), and writes `bugs/client/{hash}` with area inference (auth/notifications/database/locator/supervisors/voice/shifts/ai/app), counts, and timestamps. Wired in `main.dart` right after `ServiceLocator.init()`.
- `tool/autonomous_bugfix_agent.mjs` now records every run to `bugs/agent` (`clean` / `ai_fixed` + commit / `escalated` + issueUrl / `rejected`) and, when all fix attempts are rejected, opens a GitHub issue (label `autofix-escalation`) via `AUTOFIX_GITHUB_TOKEN`/`GITHUB_TOKEN` before failing the workflow.
- The SuperAdmin Logs tab renders both nodes with status chips and issue links.

### New Dependencies

- `file_picker` (dataset upload) and `syncfusion_flutter_pdf` (PDF text extraction). Both web-compatible.

### Cleanup Performed (2026-06-10)

- Deleted: `android_old/`, `android_backup/`, `.idea/`, `alertsysapp.iml`, `lib/screens/admin/developer_tab.dart` (orphaned; superseded by the SuperAdmin Logs tab), root duplicate `firebase_options.dart` (app uses `lib/firebase_options.dart`), `WORKER_UPDATE_FILTER_CLAIMED.js`, debug exports (`__*.json`, `temp_error.json`, mangled `C:Users…` file), one-off scripts (`boost.cjs`, `trigger_flood.cjs`, `cleanup_flood.cjs`, `reset_push_sent.cjs`), and stale `flutter_*.log` / `.codex-*.log` files.
- `.gitignore` rewritten as clean UTF-8 (it contained a corrupted UTF-16 line) and extended with `__*.json`, `temp_error.json`, `service-account.json`.

### Operational Sequence: Train And Serve The Forecaster

1. SuperAdmin signs in (role `SuperAdmin`) and lands on the console.
2. AI Training tab → upload an alert-history export (CSV/Excel/JSON/SQL/PDF). The parser reports rows/machines/span/type distribution and engineering yields N training samples. The dataset is also persisted to `ai_forecast/training/dataset` so it survives reloads.
3. Hyperparameters are auto-tuned from dataset size (and always displayed/editable); Start Training runs genuine second-order gradient boosting with live loss/accuracy curves and a learning verdict — typically seconds, not minutes. The run is owned by `ForecastTrainingController` (app-global): switching tabs, navigating the console, or signing out does not interrupt it, and mid-run checkpoints land in `ai_forecast/training/checkpoint`. A NOT-LEARNING verdict renders a "Why the model didn't learn" panel (`ForecastTrainer.diagnose`): dataset volume/span, label sparsity/missing types, and loss-trajectory reasons with concrete fixes.
4. If the browser tab/app is closed mid-run, the next console session auto-resumes the run from the checkpoint round (`ensureResumed()`); a finished-but-undeployed run is likewise restored for review/deploy.
5. Deploy to Production writes the ensemble to `ai_forecast/model`, an immediate live snapshot to `ai_predictions/forecast` computed from production alerts, clears the run checkpoint, and resets the self-evaluation ledger.
6. Every Production Manager dashboard picks the model up via stream (`ForecastOverviewEngine`): the Predictive Failure Alerts card and the Predictive Risk · Next 24h heatmap switch from the statistical edge model to live on-device forecasts (badged "AI · LIVE"), refreshing as alerts arrive.
7. From then on the model learns continuously: open dashboards snapshot tomorrow's forecast daily, grade elapsed snapshots against realized alerts (precision/recall/Brier in the console's CONTINUOUS LEARNING strip), and boost a few adaptation trees per ~day on recent production data behind a cross-dashboard lock — until the SuperAdmin runs a full retrain.


## Hybrid Industrial Connectors (SuperAdmin → Infrastructure, 2026-06-21)

Alerts can now arrive from an existing automation estate — SCADA / PLC / Historian /
MQTT / REST — configured self-service by the IT team, alongside the classic
microcontroller→Firebase path. SIAS sits *on top of* the estate (no control loops).

- **Two ingestion modes**, both through `cloudflare_ingest_worker.js` (a thin router
  that bundles `cloudflare_ingest_connectors.js`, where all logic + pure helpers live):
  - **Cloud-pull** (`rest`, `historian_pi`, `historian_ignition`): the per-minute cron
    polls each connector's HTTPS endpoint with the stored credential, extracts the
    value via a JSON path, applies thresholds, and creates alerts.
  - **Edge-push** (`opcua`, `modbus`, `microcontroller`, `custom`): a gateway POSTs to
    `POST /ingest/{connectorId}` with that connector's ingest key. The app generates a
    ready-to-run gateway snippet (node-opcua / modbus-serial / ESP32 / curl).
  - **MQTT** (`mqtt`): broker rule pushes in; `Verify` opens a real MQTT-over-WebSocket
    CONNECT and checks the CONNACK.
- **Endpoints** on the ingest worker: `POST /verify` (Bearer `WORKER_SHARED_SECRET`) is
  the "Verify link test" — live HTTP/MQTT handshake for pull/MQTT, first-packet check
  for push; `POST /control {action:'poll'}` forces a poll; `POST /ingest/{id}` is the
  per-connector push; legacy `POST /` global push is unchanged. Cron is `* * * * *`.
- **RTDB**: `connectors/{id}` (non-secret config + worker-written `runtime` status),
  `connector_secrets/{id}` (token/username/password/ingestKey — SuperAdmin + worker
  only). Both nodes are in `database.rules.json` (SuperAdmin r/w). The worker reads the
  vault + writes `runtime` via a service-account JWT (ported from the GitHub worker).
- **Flutter**: `lib/services/connector_service.dart` (`IndustrialConnector`,
  `ConnectorKind`, `ConnectorTag`, `ConnectorService.verify/pollNow/save/saveSecret`),
  UI in `lib/screens/superadmin/connectors_section.dart` (`ConnectorsSection` — catalog
  grid, live status cards, add/edit wizard with the Verify banner), embedded as the
  headline section of `infrastructure_tab.dart`. `AppConfig.ingestWorkerBase`
  (override `--dart-define=ALERTSYS_INGEST_WORKER_URL=...`) is the base URL.
- **Secrets** for `wrangler.ingest.toml`: `FIREBASE_SERVICE_ACCOUNT` + `WORKER_SHARED_SECRET`
  (new, required for verify/pull/vault), plus optional `INGEST_SHARED_SECRET`. Deploy:
  `npx wrangler deploy --config wrangler.ingest.toml` then `firebase deploy --only database`.
- **Tests**: `worker_test/connectors.test.js` (29 — JSON-path extraction, poll
  scheduling, per-connector auth, push-link status, MQTT CONNECT/CONNACK bytes) and
  `test/services/connector_service_test.dart` (model round-trips). See
  `docs/integrations/SCADA_INTEGRATION.md` for the full contract.

## Reference Edge Gateway (2026-07-20)

`gateway/` is a self-contained, packaged Node 20 ESM edge gateway — the
supported alternative to hand-writing inline connector snippets. It has
**zero required dependencies**; each protocol library (`node-opcua`,
`modbus-serial`, `nodes7`, `mqtt`, `sparkplug-payload`) is an optional peer,
lazy-imported (`gateway/src/lazy.mjs`) with a helpful install message if
missing. `gateway/bin/sias-gateway.mjs --config gateway.config.json` runs it
against a real connector; `--sim <N> [--fault-every 90s]` runs the built-in
**plant simulator** (`gateway/src/sources/sim.mjs` — deterministic seeded
telemetry with periodic fault injection) as a live demo engine; `--sim <N>
--dry-run` prints the exact mapped ingest payloads for two ticks and exits,
fully offline.

- **Sources** (`gateway/src/sources/`): `opcua.mjs` (subscribe to nodeIds),
  `modbus.mjs` (poll holding/input registers, uint16/int16/uint32/float32
  decode), `s7.mjs` (poll Siemens S7 DB addresses via `nodes7`), `mqtt.mjs`
  (topic subscribe + optional Sparkplug B decode via `gateway/src/sparkplug.mjs`),
  `sim.mjs` (built-in, no deps).
- **Mapping** (`gateway/src/mapping.mjs`): exact or MQTT-wildcard (`+`/`#`)
  rules bind a reading key to factory/line/station/machine, unit conversion
  (`scale`/`offset`), and warn/critical thresholds — output is exactly the
  SIAS ingest contract (`toIngestReading`). Contract subtlety: a threshold
  rule's `type` is attached only on an actual breach (`breachesThresholds`) —
  the ingest worker treats an explicit `type` as forced-alert, so idle
  telemetry with a typed rule must never flood the alert queue. Event rules
  (`alert: true`) and threshold-less typed rules keep their type always.
- **Reliability** (`gateway/src/batcher.mjs`, `queue.mjs`, `forwarder.mjs`):
  readings batch at ≤20 items / 2s; send failures (network error, 429, 5xx,
  401/403) land in an on-disk JSONL retry queue (`gateway/queue/`, git-ignored,
  capped at 10,000 readings, **oldest dropped** with a warning under a long
  outage) and retry with exponential backoff; other 4xx drop permanently
  (bad config, not worth retrying forever).
- **Packaging**: `gateway/Dockerfile` (node:20-slim, non-root `node` user,
  `PROTOCOL_DEPS` build-arg installs only the peers you need),
  `gateway/gateway.config.example.json` (one example source per protocol),
  `gateway/README.md` (60-second quickstart, air-gapped/firewall notes).
- **Tests**: `worker_test/gateway_mapping.test.js` (mapping/Sparkplug/protocol
  pure helpers/simulator/batcher/config), `worker_test/gateway_queue.test.js`
  (disk queue + forwarder retry/backoff, no sockets),
  `worker_test/gateway_contract.test.js` (**conformance** — runs gateway
  output through the real deployed `cloudflare_ingest_connectors.js`
  normalizer, so gateway and cloud cannot silently drift apart). Documented
  end-to-end in `docs/integrations/SCADA_INTEGRATION.md`'s "Reference edge
  gateway" section and used as the demo engine in `docs/sales/DEMO_SCRIPT.md`.

## n8n Commercial Workflows (2026-07-20)

The commercial/onboarding automation lives in n8n Cloud (`kubixdesiney.app.n8n.cloud`),
NOT in the repo — the workers only forward verified events to it. All published and
tested end to end. Base: `https://kubixdesiney.app.n8n.cloud/webhook/`.

| Workflow | ID | Webhook path | Purpose |
|---|---|---|---|
| WF1 Purchase Intake & Provisioning | `S7PiPrb3DWm2T7GN` | `sias-purchase-intake` | Routes `purchase_completed` / `quote_requested` / `payment_failed`; dedupes on `eventId`; records the customer or lead in `sias_customers`; branded Brevo emails to buyer + founder |
| WF2 Kubix Copilot Chat | `dI4h0nH3bAsjuzGJ` | `kubix-copilot-chat` | Gemini agent + per-session memory + RAG over the `sias_knowledge` Supabase vector store; logs to `sias_chats`; `[ESCALATE]` emails the founder |
| WF2b Kubix Knowledge Ingest | `fH7jUSm4rP0ga12H` | `sias-knowledge-ingest` | POST `{title, source, content}` → markdown chunking → `gemini-embedding-001` → `sias_knowledge` |
**Per-tenant knowledge (2026-07-21):** `sias_knowledge` chunks carry a `tenant`
metadata field. `"global"` = shared product knowledge every customer sees; a tenant
code (e.g. `NSW#7K2F`) = that customer's private uploads (machine register, SOPs,
escalation policy, their line naming). WF2b accepts an optional `tenant` on ingest
(defaults to `"global"`). Kubix (WF2) has TWO retrieval tools: `sias_knowledge_base`
hard-filtered to `tenant=global`, and `customer_private_knowledge` filtered to the
caller's `tenantCode` from the chat request. Both filters are enforced server-side in
the `match_sias_knowledge` RPC (`metadata @> filter`), so one customer can never
retrieve another's documents — verified by SQL: filtering as a different tenant returns
zero rows. **When adding a retrieval tool, always set the tenant metadata filter** — an
unfiltered tool would read every customer's private docs.

| WF3 Seat Activation Email | `71muihOAczOl4u2k` | `sias-activation` | Receives one PM or supervisor activation payload, sends the single-use activation link (never a password), and confirms delivery to the founder |
| WF5 Orders & Payment | `AnP16vyft2AwqegB` | order/confirmed/paid endpoints | Sends order-received, Accept/payment-contact, and Paid/provisioning-started messages; infrastructure provisioning belongs exclusively to the GitHub workflow |
| WF4 Kubix Feedback Intake | `9l2JzN5rvLbquDFP` | `kubix-feedback` | Logs thumbs up/down to `sias_chat_feedback`; a downvote pulls the transcript and emails the founder so bad answers get fixed in the knowledge base |

Wiring (secrets on `sias-store`, plus one env var on the provisioning CLI):

- `N8N_INTAKE_WEBHOOK_URL` → `.../webhook/sias-purchase-intake` (WF1)
- `N8N_CHAT_WEBHOOK_URL` → `.../webhook/kubix-copilot-chat` (WF2)
- `N8N_FEEDBACK_WEBHOOK_URL` → `.../webhook/kubix-feedback` (WF4)
- `N8N_ACTIVATION_WEBHOOK_URL` (env for `npm run provision:seats`) → `.../webhook/sias-activation` (WF3)
- `N8N_WEBHOOK_AUTH` — optional shared bearer; set it as a store-worker secret AND as
  Header Auth on each n8n webhook before taking real customers.

**Manual-payment B2B state machine (2026-07-26):** Orders live in private Supabase `public.sias_orders` (RLS on; Store Worker service role only). Buyer submission creates `under_review`. **Accept** is `under_review → confirmed` and emits `order_confirmed` so the buyer is told KubixDesiney will contact them shortly about payment. **Paid** may run from either review (direct virement flow) or confirmed and transitions through `provisioning_queued → provisioning`; it repository-dispatches only `orderId` + `tenantCode`. `.github/workflows/provision-paid-order.yml` fetches the private order, creates and verifies the dedicated instance, delivers PM + supervisor activation emails, then marks it `active`; failures become `provisioning_failed` and are retryable from the dashboard. Store secrets: `N8N_ORDER_WEBHOOK_URL`, `N8N_CONFIRMED_WEBHOOK_URL`, `N8N_PAID_WEBHOOK_URL`, `PROVISIONING_GITHUB_TOKEN`, `PROVISIONING_GITHUB_REPOSITORY`. Full runbook: `docs/ops/AUTOMATIC_ORDER_PROVISIONING.md`; schema migration: `docs/ops/sias_orders_schema.sql`.

n8n data tables: `sias_customers` (`ExqQw7LlJUTeFaNj`), `sias_chats`
(`ZDmZevIqzlKOBTU0`), `sias_chat_feedback` (`XbAfPUKF3horkC2v`). Lead/customer
status lifecycle: `quote_requested` → `provisioning` → `active` (quotes progress
`quote_requested` → `quote_sent` → `won`/`lost`, set manually).

Gemini runs on a FREE-TIER key today (`models/gemini-2.5-flash`, 20 requests/day) —
enable paid billing and bump the WF2 model node before real customers.

## Per-Customer Provisioning (updated 2026-07-26)

The production Paid flow is `tool/provision_paid_order.mjs` via
`.github/workflows/provision-paid-order.yml`. Lower-level/recovery CLIs:

- `npm run provision:owner -- --email <e> --name "F L" --company <c> --tenant <T#XXXX> [--db-url <rtdb>] [--dry-run]`
  (`tool/provision_owner.mjs`): seeds the customer's Owner seat — creates the Firebase Auth user (random password, never printed), writes `users/{uid}` (role SuperAdmin, NO email — PII split) + `users_private/{uid}` (email), and emits the ONE-TIME activation link via `generatePasswordResetLink()` (single-use, ~1h expiry — passwords are never emailed). Optional POST of the summary to `N8N_ACTIVATION_WEBHOOK_URL`. Auth via `FIREBASE_SERVICE_ACCOUNT` env or application-default credentials. Admin SDK bypasses RTDB rules; no rules changes involved.
- `npm run provision:instance -- --tenant <slug> --project-id <gcp-id> [--execute]`
  (`tool/provision_instance.mjs`): DRY-RUN BY DEFAULT (`--execute` for real). Deploys rules and the seven tenant data-plane Workers (store/app remain shared), seeds the day-one RTDB with `tool/seed_tenant.mjs`, publishes TENANTS KV, writes a secret-free summary, verifies Worker/app/RTDB/rules health, then invokes `tool/provision_seats.mjs --require-delivery-pair` so PM/supervisor links are emailed only after the instance is healthy. All deploy, secret, KV, notification, and verification failures are fatal/retryable.
- `npm run provision:seats` defaults to dry-run, enforces the exact PM (`admin`) + supervisor (`supervisor`) delivery pair for commercial automation, rejects duplicate emails, applies the `users`/`users_private` PII split, retries authenticated activation delivery, and redacts links/emails from artifacts.
- `npm run provision:seed` defaults to dry-run and only fills missing RTDB leaves, preserving buyer edits on retries.

### Provisioning lifecycle tooling (2026-07-20)

- `npm run verify:instance -- --tenant <slug> [--db-url <url>]` (`tool/verify_instance.mjs`): probes every tenant worker's `GET /config` (want 200), the shared app URL's `GET /__config` (want 200 JSON with `hasConfig: true`), the RTDB REST endpoint's reachability (any HTTP status counts — 401 means "reachable and correctly locked"), and proves rules are deployed (an **unauthenticated** read of `/users.json` must be denied — a 200 there is the critical failure: `RULES NOT DEPLOYED`). Prints a green/red table (`renderProbeTable`); exit code reflects health.
- `npm run teardown:instance -- --tenant <slug> [--execute]` (`tool/teardown_instance.mjs`): DRY-RUN BY DEFAULT. With `--execute`: deletes the tenant's Cloudflare workers (`wrangler delete` per generated config), archives `deploy/tenants/<tenant>/` → `deploy/tenants/_archived/<tenant>-<date>/`, marks the registry `deleted`. **Never** deletes the Firebase project or R2 backups — both are manual/deliberate and printed loudly as TODOs (Firebase project deletion is irreversible).
- **Tenant registry** (`tool/tenant_registry.mjs`): `deploy/tenants/registry.json` (git-ignored), maintained by provision/teardown (`upsertTenant`/`markStatus`). `npm run tenants` (`tool/list_tenants.mjs`) prints it as a table.
- `npm run backup:drill -- --tenant <slug> [--max-age-hours 36]` (`tool/backup_drill.mjs`): fetches the tenant's backup worker `GET /config` (new endpoint on `cloudflare_backup_worker.js` — reports `snapshots` count + `latest` R2 object metadata) and fails if the newest snapshot is stale. This is the "are backups actually happening" check.
- `.github/workflows/provision-tenant.yml`: `workflow_dispatch` (tenant/project-id/workers-subdomain inputs) gated behind the **`provisioning` GitHub environment** — configure required reviewers there so a stray click can never create infrastructure. Runs provision `--execute` then a standalone `verify_instance` re-check, uploads the summary as an artifact.
- `.github/workflows/provision-paid-order.yml`: automatic `repository_dispatch`
  path used by the authenticated Paid button. It has per-tenant concurrency,
  patches Supabase to `active`/`provisioning_failed`, alerts on failure, and
  uploads only non-secret bootstrap/provision evidence.
- Tests: `worker_test/verify_instance.test.js`, `worker_test/tenant_registry.test.js` (no live network — probe classification and table rendering are pure functions).

Both ship pure-helper Jest suites (`worker_test/provision_owner.test.js`, `worker_test/provision_instance.test.js`). `deploy/tenants/` and `*.env.tenant` are git-ignored.

## Legal Documents (2026-07-17)

`docs/legal/` holds DRAFT v1 of EULA, MSA, DPA (GDPR; sub-processors Google/Cloudflare/Supabase/Brevo/n8n), SLA (Enterprise 99.9%) and PRIVACY. Every file is bannered "requires review by qualified counsel"; jurisdiction-dependent choices are marked `[[PLACEHOLDER: ...]]`. They deliberately claim no certifications (SOC 2 / ISO 27001 = roadmap only). Do not link them from the storefront until counsel signs off — enforced in code, not just by convention: see "Legal pack gate (2026-07-20)" under Store Worker above (`LEGAL_PUBLISH` flag + `npm run legal:lint`). `docs/legal/COUNSEL_BRIEF.md` is the one-page handoff for the reviewing lawyer.

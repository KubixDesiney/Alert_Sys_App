# Changelog

All notable changes to SIAS - Smart Industrial Alert System are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

SIAS is a supervisory alert and operations platform that runs *on top of* a
plant's existing automation estate. It coordinates alerts and people; it does
not execute control loops and is not a safety-instrumented system. See
`RELEASE_NOTES.md` for the scope statement that accompanies each release.

## [Unreleased] - 2026-09-02 — Native Desktop App

### Added

- **Desktop app (`desktop/`) — Windows, macOS and Linux.** SIAS now ships as
  real native installers: `.exe` (NSIS) + `.msi` (WiX) on Windows, a universal
  `.dmg` on macOS (Apple silicon + Intel), and `.deb` / `.rpm` / `.AppImage` on
  Linux. Built with Tauri v2, so installers are ~10 MB and start natively
  instead of bundling a browser.

  The shell hosts the **already-deployed Flutter web app** at
  `https://<tenant>.kubixdesiney.com`, which keeps the UI byte-identical to the
  browser, preserves the `sias-app` worker's per-tenant `__SIAS_CONFIG__`
  injection, and means routine web deploys reach desktop users with **no new
  installer**. (A native `flutter build windows` is not viable: `firebase_database`
  ships android/ios/macos/web only, and 55 files under `lib/` import it.)

  Adds a first-run workspace picker that validates against the worker's
  `GET /__config` probe, a native menu (reload, zoom, full screen, switch
  workspace, about), remembered window geometry and zoom, single-instance
  focus, and an optional signed auto-updater.

### Security

- The desktop app's remote window has **zero IPC**: `capabilities/default.json`
  grants commands to the local picker window only, enforced by Tauri's ACL.
  Top-level navigation is allowlisted to product and identity-provider hosts —
  everything else (including `mailto:` and suffix-confusion lookalikes such as
  `kubixdesiney.com.evil.com`) is handed to the system browser. The remembered
  workspace is re-validated on every read, so a hand-edited settings file cannot
  repoint the window. Covered by unit tests in `desktop/src-tauri/src/tenant.rs`.

## [Unreleased] - 2026-07-20 — Commercial & Integration Max-Out

### Added

- **Reference edge gateway (`gateway/`).** Self-contained Node 20 package
  bridging OPC-UA / Modbus TCP / Siemens S7 / MQTT (incl. Sparkplug B) into
  the ingest worker: config-driven mapping rules (exact + wildcards, scale/
  offset, warn/critical thresholds), batching (≤20/2s), on-disk retry queue
  (10k cap, drop-oldest), exponential backoff, built-in **plant simulator**
  (`--sim 6 --fault-every 90s`, `--dry-run`), Dockerfile (non-root), zero
  required deps (protocol libraries are lazy-loaded optional peers).
  Contract-tested against the real ingest normalizer.
- **Invoice-led storefront (SALES_MODE=quote, default).** `/buy` becomes a
  quote request (`POST /api/quote` → `quote_requested` → n8n WF1, deduped
  `qr_` event ids); landing CTAs/FAQ switch to invoicing copy server-side;
  `SALES_MODE=card` restores checkout exactly. Prices extracted to
  `pricing.mjs`, shared with `tool/generate_quote.mjs` — a branded quote PDF
  generator (+ JSON sidecar) with discount/validity handling.
- **Kubix Copilot upgrades.** Per-reply thumbs feedback (`POST
  /api/kubix-feedback` → `N8N_FEEDBACK_WEBHOOK_URL`, verdicts persisted in the
  local transcript), French page chrome (`/copilot?lang=fr`), the `/welcome`
  onboarding checklist page, a SuperAdmin console "Kubix Copilot" card
  (`ALERTSYS_COPILOT_URL` dart-define, EN/FR), and
  `tool/kubix_chat_report.mjs` chat analytics.
- **Provisioning lifecycle tooling.** `verify_instance` (worker /config +
  RTDB reachability + rules-denial probes, green/red table, wired as
  provisioning step 9), `teardown_instance` (dry-run default, archives tenant
  dir, loud manual steps), tenant registry + `list_tenants`, `backup_drill`
  (fails if the newest R2 snapshot > 36h; backup worker gained `GET /config`),
  and a manual-approval `provision-tenant.yml` workflow gated by the
  `provisioning` environment.
- **Legal pack tooling.** `npm run legal:lint` (placeholder inventory, naming
  and forbidden-claim enforcement, MSA cross-references) + non-blocking CI
  job; store `/legal` routes hard-gated behind `LEGAL_PUBLISH`;
  `docs/legal/COUNSEL_BRIEF.md` for the reviewing lawyer.
- **Security hardening.** Strict nonce-based CSP + HSTS + Permissions-Policy
  on all store pages (inline handlers eliminated), RFC 9116
  `/.well-known/security.txt`, CycloneDX SBOM job in security CI, adversarial
  RTDB rules fuzz tests, `docs/SECURITY_WHITEPAPER.md`, threat-model
  boundaries for the store/n8n and plant-gateway surfaces.
- **Sales enablement.** Security one-pager, 44-question RFP answer bank,
  AFTER_YOU_BUY journey doc, demo script v2 (simulator-driven, persona
  branches), and a full docs index (`docs/README.md`).

## [1.2.1] - 2026-06-23 — Enterprise Pilot Readiness

This release consolidates the platform into a state suitable for **controlled
enterprise pilots**: dedicated per-customer instances, self-service
configuration, integration readiness, and the monitoring and trust
documentation a pilot sponsor expects.

### Added

- **Dedicated customer instances (white-label).** Each customer can run on their
  own Firebase project and Cloudflare account. A SuperAdmin **Infrastructure**
  console captures the non-secret instance configuration and triggers a
  `deploy_instance` GitHub Actions workflow that provisions the backend
  (workers, R2 backup bucket, database rules). Credentials are supplied from
  CI secrets, never from the client.
- **Branding & Theme studio.** Per-instance logo, colors, and light/dark theming
  applied at runtime across the supervisor, Production Manager, and SuperAdmin
  experiences, with live previews.
- **Industrial connector readiness (SCADA / PLC / Historian / MQTT / REST).** A
  dedicated ingestion worker supports cloud-pull (REST, PI, Ignition) and
  edge-push (OPC-UA, Modbus, microcontroller, MQTT, custom) modes, with a live
  "Verify link" handshake and per-connector ingest keys. Configured
  self-service from the SuperAdmin console.
- **Configurable AI models for the Assist and Briefing agents.** IT can point
  these agents at a chosen provider (OpenAI, Anthropic, Google, Mistral, xAI,
  DeepSeek, Cohere) by pasting an API key; the built-in Llama model remains the
  default and requires no key. Any failure degrades safely to the built-in model.
- **Model evaluation harness.** A "Test this model" head-to-head runs the
  candidate and the current champion on golden tasks, scores them on
  deterministic quality rubrics, and returns a better / similar / worse verdict
  before a swap is deployed.
- **Automatic model-drift alerting.** A daily re-evaluation grades each deployed
  agent model against its baseline; a quality regression raises an alert through
  the configured monitoring webhook and surfaces in the console.
- **SuperAdmin Overview Monitor.** A live, single-screen operations view that
  aggregates worker health, the AI agent fleet, database topology, security
  events, and active sessions from real platform state.
- **Hardware Lab.** A factory machinery binding map: binds controllers (ESP32,
  Arduino, …) and their sensors/actuators to real plant machines picked from
  live inventory. (An earlier Arduino simulation bench and connectivity tester
  were removed before this release — 2026-06-22 — and are not shipped.)
- **Reliability & monitoring.** A deadman monitor worker with configurable
  checks and webhook delivery (Slack, Discord, Teams, Telegram, generic), plus
  an in-app application performance signal (crash-free / error budget) with SLO
  breach alerting.
- **Trust documentation set** under `docs/` (trust center, dependency audit,
  penetration-test scope, secret-rotation runbook, branch-protection policy,
  compliance and ops material) and this release-readiness package
  (`RELEASE_NOTES.md`, `INSTALLATION.md`, `docs/PILOT_READINESS_CHECKLIST.md`).

### Changed

- **AI agent fleet matured to six agents** — Shift Commander (multi-factor
  assignment with reinforcement learning), Briefing Officer, AI Assist,
  Security Sentinel, Predictive Core (on-device gradient-boosted forecaster with
  continuous self-grading), and Guardian (CI / self-heal observability). Each
  agent has explicit reasons, confidence, and per-agent enable controls.
- **Notification delivery** moved to a targeted, queued fan-out with worker-to-
  worker fast triggers and a durable one-minute cron fallback.
- **Cloudflare worker split** into focused, independently deployed workers
  (AI/security, notifications, GitHub proxy, ingestion, monitor, SCIM, backup).
- Large UI and runtime files refactored into focused modules to improve
  maintainability.

### Security

- **Multi-factor authentication enforcement** with a hard gate at sign-in for
  required accounts.
- **SCIM 2.0 auto-provisioning / de-provisioning** worker for IdP-driven user
  lifecycle (Okta, Microsoft Entra, OneLogin), with constant-time token checks,
  rate limiting, and an audit trail.
- **Realtime Database security rules hardened** and validated by an automated
  rules policy test suite; `security/*` and `workers/*` reads restricted to the
  worker service token and SuperAdmin.
- **Personally identifiable information** separated into a private-profile node
  away from broadly readable records.
- **Immutable audit trail** for sensitive administrative actions.
- **Removed a hard-coded third-party credential** and the dead code path that
  carried it; push delivery is FCM-only. (Operators must still rotate any
  previously exposed credential at its provider — see `docs/SECRET_ROTATION.md`.)

### Fixed

- Predictive cards on the Production Manager dashboard now feed normalized alert
  types into the live forecaster and keep the AI overlay during quiet periods.
- Notification push-lock handling no longer tombstones alerts when no recipient
  is eligible, allowing later retries.
- Numerous test-harness and documentation drift corrections.

## [1.2.0] - 2026-06 — SuperAdmin tier & on-device forecasting

### Added

- SuperAdmin command console (role `superadmin`) with AI Training, AI Agents,
  Production Manager provisioning, and platform observability.
- On-device, pure-Dart gradient-boosted decision-tree forecaster that trains on
  uploaded alert history and serves next-24h machine risk on the Production
  Manager dashboard, grading and adapting itself over time.

## [1.1.0] - 2026-05 — Shifts, predictions & security agent

### Added

- Shift scheduling, AI Shift Commander, presence tracking, and PDF shift reports.
- Predictive intelligence (morning briefings, risk curves, assignee suggestions)
  and prediction-accuracy validation.
- Edge security agent (rate limiting, prompt-injection detection, anomaly scan,
  audit logging).

## [1.0.0] - Initial — Core alerting platform

### Added

- Real-time alert intake, claiming, resolution, escalation, and validation.
- Admin (Production Manager) and supervisor role flows on Firebase
  Authentication and Realtime Database.
- Firebase Cloud Messaging push with full-screen lock-screen alerts; Android
  voice-claim flow.
- Factory hierarchy, assets, custom plant maps, QR station scanning, and
  location-aware routing.
- Offline-aware startup, cached role data, and resilient worker trigger queue.

[1.2.1]: #121---2026-06-23--enterprise-pilot-readiness
[1.2.0]: #120---2026-06--superadmin-tier--on-device-forecasting
[1.1.0]: #110---2026-05--shifts-predictions--security-agent
[1.0.0]: #100---initial--core-alerting-platform

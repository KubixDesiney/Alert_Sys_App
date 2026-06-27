# Changelog

All notable changes to SIAS - Smart Industrial Alert System are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

SIAS is a supervisory alert and operations platform that runs *on top of* a
plant's existing automation estate. It coordinates alerts and people; it does
not execute control loops and is not a safety-instrumented system. See
`RELEASE_NOTES.md` for the scope statement that accompanies each release.

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
- **Hardware Lab.** A factory machinery binding map plus a pure-Dart Arduino
  simulation bench (lexer, parser, interpreter, circuit/netlist solver) and an
  honest ESP32-to-Firebase connectivity tester, with a broad automated test
  corpus.
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

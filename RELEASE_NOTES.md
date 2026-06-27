# SIAS - Smart Industrial Alert System — Release Notes

## Version 1.2.1 · "Enterprise Pilot Readiness" · 2026-06-23

### What SIAS is

SIAS - Smart Industrial Alert System is an enterprise industrial **alert and operations
platform**. It gives factory teams real-time mobile alerting, AI-assisted
supervisor assignment, predictive-maintenance forecasting, and shift and
collaboration coordination — administered through a SuperAdmin console and
deployed as a dedicated instance per customer.

SIAS sits **on top of** a plant's existing automation estate. It coordinates
alerts and people and surfaces operational intelligence; it does not run control
loops and is not a safety-instrumented system. It complements SCADA, PLCs, and
historians rather than replacing them.

### Who this release is for

This release is intended for **controlled enterprise pilots** and day-to-day
operational alert coordination — a sponsor running SIAS alongside existing
operations on a defined line, plant, or shift, with a named administrator and a
support channel. It is not yet positioned for unsupervised, safety-critical, or
regulated-control use (see "Honest scope" below).

### Highlights

- **Dedicated, white-label customer instances.** Run on the customer's own
  Firebase project and Cloudflare account. The SuperAdmin Infrastructure console
  captures the (non-secret) instance configuration and triggers an automated
  deploy that stands up the backend; all credentials come from CI secrets.
- **Real-time mobile alerting.** Targeted push fan-out with full-screen,
  lock-screen alerts and a one-minute durable fallback so a missed trigger still
  reaches the right supervisors.
- **AI-assisted operations.** A six-agent fleet — assignment (Shift Commander),
  morning briefings, resolution assistance, edge security, an on-device
  predictive-maintenance forecaster, and CI/self-heal observability — each with
  explicit reasoning, confidence, and an on/off control.
- **Bring-your-own AI model, measured.** Point the Assist and Briefing agents at
  your preferred provider with a pasted API key (Llama is the free, built-in
  default). Every model swap can be **A/B tested** against the current one before
  it ships, and a daily **drift check** alerts you if quality regresses.
- **SCADA / PLC / Historian / MQTT / REST integration readiness.** Configure
  cloud-pull or edge-push connectors self-service, with a live link-verification
  handshake.
- **Operations monitoring and trust documentation.** A live Overview Monitor, a
  deadman monitor with webhook alerting (Slack / Teams / Discord / Telegram),
  application crash-free/error-budget tracking, MFA enforcement, SCIM
  provisioning, hardened database rules, an audit trail, and a documented trust
  center.
- **Bilingual** English/French throughout, with instant runtime switching.

### Upgrade and deployment

See `INSTALLATION.md` for first-time setup and `docs/PILOT_READINESS_CHECKLIST.md`
to confirm a pilot instance is ready. Backend changes in this release require
re-deploying the Realtime Database rules and the affected Cloudflare workers; the
mobile/web client is rebuilt with the instance's worker URLs. No data migration
is required from 1.2.0.

### Honest scope and limitations

- **Supervisory, not control.** SIAS coordinates alerts and people. It does not
  actuate equipment, close control loops, or function as an emergency-shutdown
  or safety-instrumented system. Keep existing SCADA/PLC safety functions in
  place and authoritative.
- **Pilot maturity.** This release targets controlled pilots and operational
  alert coordination. Run it alongside — not in place of — existing alerting
  during the pilot, and validate behavior against your environment.
- **Primary platform is Android.** The full voice and lock-screen alerting stack
  is Android-native; web, iOS, and desktop have working support paths with a
  reduced feature set.
- **AI outputs are advisory.** Assignment, briefing, suggestion, and forecast
  outputs are decision support with stated confidence — they are not guarantees,
  and a human remains accountable for each action.
- **Customer-owned credentials and data.** In the dedicated-instance model the
  customer owns the Firebase project, Cloudflare account, and any AI provider
  keys; SIAS does not centralize customer data.

### Support

Pilot support is provided through the channel agreed with your SIAS
representative. Operational runbooks, the secret-rotation procedure, and the
trust center live under `docs/`.

# SIA — Installation & Deployment Guide

This guide stands up a **dedicated Smart Industrial Alert (SIA) instance** for a
controlled pilot. SIA is deployed per customer: the customer owns the Firebase
project, the Cloudflare account, and any AI-provider keys. SIA does not
centralize customer data.

> **Secrets policy.** This document lists the *names* of the secrets you must
> provide and *where* they go. It never contains secret values. Never commit
> secret values to the repository or paste them into workflow files — use GitHub
> Actions secrets, `wrangler secret put`, or the SuperAdmin console as noted
> below. See `docs/SECRET_ROTATION.md`.

## 1. Architecture at a glance

A SIA instance is four cooperating parts:

1. **Flutter client** (Android primary; web/iOS/desktop support paths) — the
   supervisor, Production Manager, and SuperAdmin apps.
2. **Firebase** — Authentication, Realtime Database (operational data store),
   and Cloud Messaging (push delivery).
3. **Cloudflare Workers** — edge orchestration, split into focused workers:
   AI/security, notifications, GitHub proxy (Guardian), industrial ingestion,
   reliability monitor, SCIM, and backup.
4. **Firebase Cloud Functions** — AI-assignment retry triggers.

## 2. Prerequisites

- Flutter SDK matching `pubspec.yaml` (`>=3.38.4`) and Dart `>=3.10.3`.
- Node.js 20+ and npm (for the workers and tests).
- A **Firebase project** for the customer (Authentication + Realtime Database +
  Cloud Messaging enabled) and the Firebase CLI.
- A **Cloudflare account** with Workers and R2, and the `wrangler` CLI.
- An Apple/Google developer account if distributing the mobile app.

## 3. Two ways to deploy

### Option A — Automated, per-customer (recommended)

The SuperAdmin **Infrastructure** console captures the instance's non-secret
configuration (Firebase project id, database URL, workers subdomain, R2 bucket,
brand color) and fires the `deploy_instance` GitHub Actions workflow
(`.github/workflows/deploy-instance.yml`). That workflow provisions the backend
end to end: it deploys the workers, sets their secrets from CI, creates the R2
backup bucket, and deploys the database rules.

All credentials are read from the repository's GitHub Actions secrets — never
from the trigger payload. Set these **secret names** once
(Settings → Secrets and variables → Actions):

- `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`
- `FIREBASE_SERVICE_ACCOUNT` (full service-account JSON), `FB_DB_URL`, `FB_API_KEY`
- `WORKER_SHARED_SECRET`
- `SCIM_TOKEN` (if SCIM provisioning is used)

The provisioning step also prints the exact client build command for the
instance (with that instance's worker URLs).

### Option B — Manual deployment

Use this for the reference/development instance or to understand the moving
parts.

**Database rules and functions:**

```bash
firebase deploy --only database
firebase deploy --only functions
```

**Cloudflare workers** (deploy each with its config; set secrets per worker with
`wrangler secret put <NAME>`, supplying the value interactively):

```bash
npm install
npx wrangler deploy --config wrangler.ai.toml       # AI / security
npx wrangler deploy --config wrangler.notify.toml    # notifications
npx wrangler deploy --config wrangler.github.toml    # Guardian / GitHub proxy
npx wrangler deploy --config wrangler.ingest.toml    # SCADA / PLC ingestion
npx wrangler deploy --config wrangler.monitor.toml   # reliability monitor
npx wrangler deploy --config wrangler.scim.toml      # SCIM provisioning
npx wrangler deploy --config wrangler.backup.toml    # RTDB backup
```

Worker secrets are referenced by name only; set the values with `wrangler secret
put`. Typical names per worker include `FB_DB_URL`, `FB_API_KEY`,
`FIREBASE_SERVICE_ACCOUNT`, `WORKER_SHARED_SECRET`, and (where applicable)
`SCIM_TOKEN`, `INGEST_SHARED_SECRET`, and optional AI-provider keys. The exact
required set is documented at the top of each worker source file.

**Client build** (substitute your instance's worker URLs and secret — these are
placeholders, not real values):

```bash
flutter pub get
flutter build apk --release \
  --dart-define=ALERTSYS_AI_WORKER_URL=https://<ai-worker>.<subdomain>.workers.dev \
  --dart-define=ALERTSYS_NOTIFY_WORKER_URL=https://<notify-worker>.<subdomain>.workers.dev \
  --dart-define=ALERTSYS_WORKER_SHARED_SECRET=<WORKER_SHARED_SECRET>
# Web build is analogous with `flutter build web --release`.
```

Optional `--dart-define` overrides exist for the GitHub proxy and ingestion
worker base URLs; see `lib/config/app_config.dart`.

## 4. First-run configuration

1. **Create the SuperAdmin account.** Create a user in Firebase Authentication,
   then set `users/{uid}/role = "SuperAdmin"` in the Realtime Database. Sign in
   to reach the SuperAdmin console.
2. **Enforce MFA.** Confirm the MFA gate is on for required roles
   (see `auth_config/mfaRequired`).
3. **Provision Production Managers** from the SuperAdmin → Production Managers
   tab (accounts are created via a secondary Firebase app so your session is
   preserved). Optionally connect an IdP via SCIM for automatic user lifecycle.
4. **Branding.** Set the logo, colors, and default theme in SuperAdmin → Theme.
5. **Monitoring.** In SuperAdmin → Reliability, enable the checks you want and
   set the alert webhook (Slack / Teams / Discord / Telegram / generic).
6. **AI agents (optional).** Enable the agents you want. To use a non-default
   model for Assist/Briefing/Shift, pick a provider and paste its API key in the
   agent's Model Engine panel, then use **Test this model** before saving.
7. **Industrial connectors (optional).** In SuperAdmin → Infrastructure, add
   SCADA/PLC/Historian/MQTT/REST connectors and use **Verify link** to confirm
   connectivity before enabling ingestion.
8. **Backups.** Confirm the backup worker is running and writing to R2.

## 5. Verify the instance

- Run the test suites: `flutter test` and `npm test`.
- Create a test alert and confirm push delivery to a supervisor device within a
  few seconds.
- Confirm the SuperAdmin Overview Monitor shows live worker health and sessions.
- Walk `docs/PILOT_READINESS_CHECKLIST.md` before going live with a sponsor.

## 6. Notes

- **Package identifiers are intentionally stable.** The Dart package is
  `alertsysapp`; do not rename it.
- **Rotate any previously exposed credentials** at their provider before a pilot
  (see `docs/SECRET_ROTATION.md`).
- The autonomous CI/self-heal (Guardian) capabilities are optional and gated;
  review `docs/` before enabling automatic deploy modes.

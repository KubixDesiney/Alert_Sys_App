# Security policy

## Supported versions
The latest released version (see `pubspec.yaml`) receives security updates.

## Reporting a vulnerability
Report suspected vulnerabilities **privately** to <chefbriotemendez@gmail.com>.
Please do not open public GitHub issues for security reports. We aim to acknowledge
within 3 business days and to share a remediation timeline after triage.

## Scope
- Flutter app (`lib/`)
- Cloudflare Workers (`cloudflare_*_worker.js`, `worker/`)
- Realtime Database rules (`database.rules.json`)
- Firebase Cloud Functions (`functions/`)

## How secrets are handled
- No secrets are committed to source. Worker secrets are injected via Cloudflare
  secrets; the Firebase service-account credential is provided at runtime only.
- Firebase **client** API keys in `lib/firebase_options.dart` are public by design and
  are locked down with Google Cloud **API key restrictions** (app + API allow-lists),
  plus enforcement in `database.rules.json`.
- RTDB data exports (`backups/`) are git-ignored and never committed.
- CI runs blocking current-tree `gitleaks` secret scanning and blocking `npm audit`
  on every push and weekly. Full-history gitleaks output is retained as legacy
  remediation evidence until the owner completes history purge.
- Dependency audit gate scope and the current Wrangler dev-tool advisory note are
  documented in `docs/DEPENDENCY_AUDIT.md`.

## Hardening checklist (operational)
1. Rotate the legacy third-party push credential at its provider and purge it from git
   history (`tool/purge_leaked_secret.sh`).
2. Apply Google Cloud API key restrictions to every Firebase API key.
3. Keep `database.rules.json` least-privilege; review broad `auth != null` grants.
4. Enforce MFA/SSO for admin and superadmin accounts (see `MFA_SSO.md`).
5. Verify provider-side secret rotation evidence and history-purge status with
   `docs/SECRET_ROTATION.md`.
6. Verify protected `main` branch settings with `docs/BRANCH_PROTECTION.md`.

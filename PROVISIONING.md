# Provisioning a new company (dedicated-instance model)

Smart Industrial Alert is sold **one isolated instance per company**. Each customer
gets their own Firebase project and their own Cloudflare workers. Isolation comes
from *separate deployments*, so there is **no shared data path** and no way for one
company's data to leak into another's — the strongest possible guarantee, and the
easiest to defend in a security review.

One codebase produces every customer's app; only **build-time config** differs.

---

## What is per-company vs shared

| Concern | Per-company | How it's set |
| --- | --- | --- |
| Firebase project (Auth, RTDB, data) | yes | `flutterfire configure --project=<proj>` |
| Database security rules | shared file, deployed per project | `firebase deploy --only database -P <proj>` |
| Cloudflare workers (AI + notify) | yes (own names + secrets) | per-company `wrangler.*.toml` + `wrangler secret put` |
| Worker URLs in the app | yes | `--dart-define=ALERTSYS_AI_WORKER_URL=…` etc. |
| Company identity / branding | yes | `--dart-define=COMPANY_*` (see `lib/config/company_config.dart`) |
| App / worker source code | **shared** | one repo, one `main` |

---

## Prerequisites (once)

- Firebase CLI (`npm i -g firebase-tools`) + FlutterFire (`dart pub global activate flutterfire_cli`)
- Cloudflare Wrangler (`npm i -g wrangler`) and access to the Cloudflare account
- Flutter SDK matching `pubspec.yaml`
- A clean `git status` (you'll regenerate `firebase_options.dart` per build)

---

## Provision company `acme` (worked example)

### 1. Firebase project
```bash
firebase projects:create acme-alerts --display-name "ACME Manufacturing"
```
In the console: enable **Authentication → Email/Password**, and create a
**Realtime Database** — choose the region that matches the customer's data-residency
requirement (e.g. `europe-west1`).

### 2. Wire the app to that project
```bash
flutterfire configure --project=acme-alerts
```
This regenerates `lib/firebase_options.dart` and the native config
(`android/app/google-services.json`, `ios/.../GoogleService-Info.plist`).

> Keep each company's generated files out of `main`. Use a per-company branch,
> a build directory, or CI that runs `flutterfire configure` fresh per build —
> never commit one company's `firebase_options.dart` as the default.

Also update `web/firebase-messaging-sw.js` with the new project's web config
(the web push SW can't read `--dart-define`).

### 3. Deploy the security rules to this project
```bash
firebase deploy --only database --project acme-alerts
```
(Same `database.rules.json` for everyone — it's hardened and tenant-agnostic.)

### 4. Stand up the company's workers
```bash
# copy the templates and rename the worker per company
cp wrangler.ai.toml      wrangler.acme.ai.toml      # set name = "acme-ai"
cp wrangler.notify.toml  wrangler.acme.notify.toml  # set name = "acme-notify"

# per-company secrets (NEVER commit these)
wrangler secret put FB_DB_URL            --config wrangler.acme.ai.toml   # https://acme-alerts-default-rtdb.firebaseio.com
wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.acme.ai.toml   # acme's service-account JSON
wrangler secret put WORKER_SHARED_SECRET --config wrangler.acme.ai.toml
# repeat the relevant secrets for the notify worker config

wrangler deploy --config wrangler.acme.ai.toml
wrangler deploy --config wrangler.acme.notify.toml
```
Note the deployed URLs (e.g. `https://acme-ai.<acct>.workers.dev`).

### 5. Seed the SuperAdmin
Create the first auth user (console or app), then set their role:
`users/<uid>/role = "SuperAdmin"` in the acme RTDB. They can provision Production
Managers from the console after that.

### 6. Build the company's app
```bash
flutter build apk --release \
  --dart-define=COMPANY_ID=acme \
  --dart-define=COMPANY_NAME="ACME Manufacturing" \
  --dart-define=COMPANY_APP_TITLE="ACME Alerts" \
  --dart-define=COMPANY_BRAND_COLOR=0xFFB71C1C \
  --dart-define=COMPANY_FIREBASE_PROJECT=acme-alerts \
  --dart-define=ALERTSYS_AI_WORKER_URL=https://acme-ai.<acct>.workers.dev \
  --dart-define=ALERTSYS_NOTIFY_WORKER_URL=https://acme-notify.<acct>.workers.dev \
  --dart-define=ALERTSYS_WORKER_SHARED_SECRET=<secret>
```

### 7. Verify isolation before shipping
- `COMPANY_FIREBASE_PROJECT` matches the project `flutterfire configure` wired
  (the in-app guard in `CompanyConfig.verifyFirebaseProject` checks this at
  startup — see wiring below).
- Sign in on the acme build → you only see acme data.
- The acme workers' `/config` returns the acme DB URL, not another company's.

---

## Recommended: wire the isolation guard in `main.dart`

Right after Firebase initializes, assert the build is pointed at the right project:

```dart
import 'config/company_config.dart';
import 'firebase_options.dart';
// ...after Firebase.initializeApp(...):
final mismatch = CompanyConfig.verifyFirebaseProject(
  DefaultFirebaseOptions.currentPlatform.projectId,
);
if (mismatch != null) {
  ServiceLocator.instance.logger.error(mismatch); // surfaces to the bugs pipeline
  // In release, prefer to halt rather than risk wrong-company data:
  // runApp(const _MisconfiguredApp()); return;
}
```

This catches the one catastrophic mistake in this model: shipping Company A's app
accidentally wired to Company B's Firebase project.

---

## Decommissioning a company

1. Disable the workers (`wrangler delete --config wrangler.<co>.ai.toml`, same for notify).
2. Export their RTDB if contractually required, then delete the Firebase project.
3. Rotate/delete the company's service-account key and worker secrets.
4. Revoke the build/distribution.

Because nothing is shared, decommissioning one company never touches another.

---

## Isolation checklist (per company)

- [ ] Own Firebase project (Auth + RTDB), region set for data residency
- [ ] Rules deployed to that project
- [ ] Own AI + notify workers, uniquely named, with their own secrets
- [ ] Own service-account key (never reused across companies)
- [ ] App built with that company's `COMPANY_*` + worker `--dart-define`s
- [ ] Startup project-match guard passes
- [ ] Smoke test: only that company's data is visible

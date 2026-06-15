# Release & deployment runbook

## Environments
Run a separate **staging** Firebase project + Cloudflare workers, isolated from
production. Never load-test or trial-deploy against production.

| Concern          | Staging (example)        | Production            |
|------------------|--------------------------|-----------------------|
| Firebase project | alertappsys-staging      | alertappsys           |
| AI worker        | alert-notifier-staging   | alert-notifier        |
| Notify worker    | alertsys-staging         | alertsys              |
| Secrets          | staging CF / GH secrets  | production secrets     |

(Adjust names to your accounts; keep a `wrangler.*.staging.toml` per worker.)

## Versioning
- App version is the source of truth in `pubspec.yaml`.
- Tag each release `vMAJOR.MINOR.PATCH`; build production artifacts from tags.
- Bump the worker `package.json` version on worker changes.

## Pre-release gates (all must be green)
1. `flutter analyze` clean + `flutter test --coverage` (Flutter coverage job).
2. `npm run test:coverage` (worker coverage gate, see jest.config.js threshold).
3. `npm run bench:ci` (assignment performance guard - fails on latency regression).
4. Security workflow green (`gitleaks` + `npm audit`).

## Deploy order (staging first, then repeat for production)
1. Database rules: `firebase deploy --only database`.
2. Workers: `npm run deploy:ai && npm run deploy:notify`.
3. Hosting: `firebase deploy --only hosting`.
4. Smoke-test staging against the SLOs in LOAD_TESTING.md before promoting.

## Rollback
- Hosting: `firebase hosting:rollback` (or redeploy the previous `web-build` artifact).
- Workers: `wrangler rollback --config wrangler.ai.toml` / `wrangler.notify.toml`,
  or redeploy the previous commit.
- Database rules: previous `database.rules.json` is in git - redeploy it.
- Mobile app: Shorebird code push for hotfixes; otherwise store rollback.
- Tag the last-known-good commit before every production deploy.

## Signed Android builds
- Store the upload keystore as a CI secret; never commit it (`.gitignore` covers
  `*.jks` / `*.keystore`).
- Generate `android/key.properties` from secrets at build time.

## Post-deploy verification
- `workers/health` freshness is green in the SuperAdmin console.
- A test alert delivers within the push SLO (LOAD_TESTING.md).
- `bugs/client` error rate is flat for 30 minutes after deploy.

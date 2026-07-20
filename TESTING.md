# Testing & CI/CD Guide

This document explains how to run, extend, and ship the SIAS - Smart Industrial Alert System test
suite. Two separate harnesses live in this repo:

| Harness | Tooling | Scope |
|---|---|---|
| Flutter app | `flutter test` | Dart code under [lib/](lib/) — parser, models, services, widgets |
| Cloudflare Workers + tools | Jest | Pure helpers across all 8 workers (`worker/`, `cloudflare_*_worker.js`, `cloudflare_ingest_connectors.js`, `cloudflare_store_worker.js`, `pricing.mjs`), every `tool/*.mjs` CLI, and `gateway/` |

GitHub Actions wires both together in [.github/workflows/ci.yml](.github/workflows/ci.yml).

---

## Quick start

```bash
# Flutter side
flutter pub get
flutter test                 # 450+ tests
flutter analyze --no-fatal-infos --no-fatal-warnings

# Worker side
npm install
npm test                     # 65+ suites, 900+ tests, a few seconds
npm run test:coverage        # same suite + v8 coverage report and threshold gate
```

Both suites are hermetic — no Firebase emulator, no Cloudflare account, no
network access required. `worker_test/integration/` goes one step further:
it drives `default.fetch` on the real `cloudflare_ingest_worker.js` and
`cloudflare_store_worker.js` end to end against an in-memory fake RTDB and a
mocked `fetch`, rather than importing pure helpers in isolation.

---

## Flutter test layout

```
test/
├── voice_command_parser_test.dart        # every parser path
├── widget_test.dart                       # smoke
├── theme_test.dart / theme_brand_test.dart / theme_contrast_test.dart
├── accessibility_bottom_nav_test.dart
├── models/          # alert, user, collaboration, shift, predictive
├── services/        # AI scoring, forecaster, offline cache, PDF, data-layer backends...
├── utils/           # factory_id, alert_meta, notification_eligibility,
│                     # alert_claim_error, user_friendly_error
└── widgets/         # admin_dashboard_screen, locator_painter,
                      # factory_location_picker, overview_stat_card
```

### Adding a new test

For pure-Dart logic (parser, models, utils), prefer plain unit tests with
`flutter_test`:

```dart
import 'package:alertsysapp/models/alert_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AlertModel parses minimum payload', () {
    final m = AlertModel.fromMap('a1', {'type': 'qualite'});
    expect(m.type, 'qualite');
  });
}
```

For widget tests, use `testWidgets` and `pumpWidget` â€” see
[`test/theme_test.dart`](test/theme_test.dart) for an example that captures
context state without touching Firebase.

### Mocking Firebase / HTTP / SharedPreferences

`mocktail` is in `dev_dependencies`. Typical patterns:

```dart
// SharedPreferences
import 'package:shared_preferences/shared_preferences.dart';
SharedPreferences.setMockInitialValues({});

// HTTP (mocktail)
import 'package:mocktail/mocktail.dart';
class _MockClient extends Mock implements http.Client {}

// FirebaseAuth â€” override the singleton in your service via a
// constructor-injected `FirebaseAuth` parameter (preferred), or wrap the
// service in a thin abstraction layer for tests.
```

> Firebase/Realtime Database singletons (`FirebaseAuth.instance`,
> `FirebaseDatabase.instance`) cannot be mocked safely without a refactor.
> Tests that depend on them either inject a fake or skip â€” see
> `voice_command_dispatcher.dart` for the singleton pattern that needs
> wrapping before it can be unit tested.

### Golden tests (visual snapshots)

The `golden_toolkit` package is **not** wired in by default â€” adding goldens
is opt-in because they bloat the diff and need careful regeneration. To add:

```yaml
# pubspec.yaml
dev_dependencies:
  golden_toolkit: ^0.15.0
```

Then create `test/flutter_test_config.dart`:

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  return GoldenToolkit.runWithConfiguration(
    () async => testMain(),
    config: GoldenToolkitConfiguration(
      enableRealShadows: true,
    ),
  );
}
```

Golden files live next to the test:

```
test/widgets/voice_command_button_golden_test.dart
test/widgets/__goldens__/voice_command_button.png
```

Regenerate them with `flutter test --update-goldens`.

---

## Cloudflare Worker test layout

`worker_test/` holds 65+ files — a few highlights, one per split worker plus
the shared/tooling layers:

```
worker_test/
├── scoring.test.js / score_supervisor.test.js   # AI worker: buildSupStats, scoreSupervisor
├── predictive_model.test.js                      # AI worker: buildPredictiveModel + _toMs
├── briefing_helpers.test.js                       # AI worker: _aggregateWeek, notifTitle, FCM routing
├── alerts_module.test.js / escalation_module.test.js / auth_module.test.js / utils_module.test.js
│                                                   # worker/*.js modular helpers (direct, mocked-fetch)
├── notification_fanout.test.js                    # notify worker
├── github_worker.test.js                          # GitHub proxy worker
├── connectors.test.js / ingest.test.js            # ingest worker + connector engine
├── gateway_mapping.test.js / gateway_queue.test.js / gateway_contract.test.js
│                                                   # gateway/ reference edge gateway
├── store_worker.test.js / store_quote.test.js / kubix_copilot.test.js / legal_lint.test.js
│                                                   # sias-store worker (checkout, quotes, Kubix, legal gate)
├── provision_instance.test.js / verify_instance.test.js / tenant_registry.test.js
│                                                   # per-tenant provisioning lifecycle tools
├── database_rules_security.test.js                # RTDB rules, incl. adversarial fuzz cases
└── integration/                                   # route-level: real default.fetch, mocked network
```

### How the worker exposes pure functions

Every Cloudflare Worker ships ESM with a `default` export (`{ fetch, scheduled }`).
Jest needs named exports too, so each worker file ends with a named-export
block (look for `export {`/`export function` near the bottom of
`cloudflare_ai_worker.js`, `cloudflare_notify_worker.js`,
`cloudflare_ingest_connectors.js`, `cloudflare_store_worker.js`, etc., or any
file under `worker/`). The named exports are inert in production — Cloudflare
only consumes the default export.

To test a new pure helper:

1. Make sure the function is `function name(...)` at module scope (not
   nested inside another function or behind a side-effecting top-level
   `await`).
2. Add it to that file's named-export block.
3. Import it in a `worker_test/foo.test.js` file:

   ```js
   import { describe, test, expect } from '@jest/globals';
   import { newHelper } from '../worker/scoring.js'; // or the relevant cloudflare_*_worker.js

   describe('newHelper', () => {
     test('does the thing', () => {
       expect(newHelper(42)).toBe('forty-two');
     });
   });
   ```

   For route-level behavior (the full `request → default.fetch → Response`
   path), prefer the pattern in `worker_test/integration/`: call
   `worker.fetch(new Request(...), env)` with a mocked `global.fetch` standing
   in for Firebase/upstream network calls — see
   `worker_test/integration/ingest_routes.test.js` for an in-memory fake RTDB.

### Running

```bash
npm test               # one-shot
npm run test:watch     # rebuild on change
npm run test:rules     # Firebase RTDB rules/configuration behavior only
npm run test:coverage  # v8 coverage report + coverageThreshold gate (jest.config.js)
npm run legal:lint     # legal-pack consistency check (warning-only in CI)
```

Jest is run with `--experimental-vm-modules` (configured in `package.json`)
so it can load the worker as ESM without transformation.

### Firebase rules/configuration tests

Realtime Database rule coverage lives in:

- [`worker_test/database_rules_security.test.js`](worker_test/database_rules_security.test.js)
- [`worker_test/firebase_rules_configuration.test.js`](worker_test/firebase_rules_configuration.test.js)

These tests are hermetic: they do not use real Firebase projects, service
accounts, customer data, or an emulator. The behavior test evaluates
`database.rules.json` expressions against synthetic company database roots to
validate the SIAS deployment model:

- each customer gets its own configured database/runtime through Superadmin;
- role checks are evaluated inside the active company database root;
- Superadmin-only configuration paths are writable only by company superadmins;
- service-token writes are limited to worker/security paths where expected;
- dangerous writes such as credential-vault edits, audit overwrites, invalid
  push-lock values, and oversized agent prompts are denied.

They run as part of `npm test` in CI.

---

## Continuous integration

[.github/workflows/ci.yml](.github/workflows/ci.yml) runs on every push to
`main` and every pull request, with three jobs (`flutter`, `worker`,
`legal-lint`), plus a separate [security.yml](.github/workflows/security.yml)
(secret scan, dependency audit, SBOM) and an on-demand, environment-gated
[provision-tenant.yml](.github/workflows/provision-tenant.yml).

### `flutter` job

1. Sets up JDK 17 (required by AGP 8) and Flutter `3.41.6` (stable).
2. Caches `~/.pub-cache` and `.dart_tool`.
3. `flutter pub get`.
4. `flutter analyze --no-fatal-infos --no-fatal-warnings` — fails on real
   errors only; pre-existing style `info`s don't block CI.
5. `flutter test --reporter expanded` (blocking).
6. `flutter build apk --debug` and `flutter build web --release`, both with
   the split worker URLs baked in via `--dart-define`.
7. Uploads the web build as a CI artefact (`web-build`, 7-day retention).

### `worker` job

1. Sets up Node 20 with the `npm` cache.
2. `npm ci`.
3. `npm test` — runs the full Jest suite (all 8 workers, `tool/`, `gateway/`).
4. **Deploys all 8 workers** (`wrangler deploy` per `wrangler.*.toml`) — only
   on direct pushes to `main` and only when `CLOUDFLARE_API_TOKEN` and
   `CLOUDFLARE_ACCOUNT_ID` are present. Deploying all 8 together (never a
   subset) is deliberate — it's how config drift gets introduced.
5. Pushes the `alertsys-github` worker's bootstrap secrets (idempotent) on
   the same protected pushes.

### `legal-lint` job

Runs `node tool/legal_lint.mjs` with `continue-on-error: true` — the legal
drafts carry `[[PLACEHOLDER]]` markers until counsel resolves them, so this
job surfaces naming/claim violations loudly without ever blocking a deploy.

### Required GitHub repository secrets

See CLAUDE.md's "CI And Deploy" section for the authoritative, current list
(`WORKER_SHARED_SECRET`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
`FIREBASE_TOKEN`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
`FIREBASE_SERVICE_ACCOUNT_ALERTAPPSYS`, plus the `FB_DB_URL` repo variable).
Set them under **Settings → Secrets and variables → Actions**. Without them,
the `worker` job still runs the Jest suite — only the deploy step is skipped
(with a warning annotation).

### Worker secrets (separate from GitHub secrets)

Each of the 8 workers reads its own runtime secrets from the Cloudflare
environment via its `wrangler.*.toml`, e.g.:

```bash
wrangler secret put FB_DB_URL --config wrangler.ai.toml
wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler.ai.toml
wrangler secret put WORKER_SHARED_SECRET --config wrangler.ai.toml
```

These never go through GitHub — they live in Cloudflare's secret store and
are visible to each worker at runtime as `env.FB_DB_URL`, etc. See
CLAUDE.md's "Worker Secrets And Runtime Config" for the full per-worker list.

---

## Troubleshooting

**`flutter test` hangs at the first test.**
Run `flutter clean && flutter pub get`. The `.dart_tool/` cache key
referenced in `analysis_options.yaml` includes generated files that can
desync after a Flutter SDK upgrade.

**Jest fails with `SyntaxError: Cannot use import statement outside a
module`.**
Make sure `package.json` has `"type": "module"` and you're running tests
via `npm test` (which adds `--experimental-vm-modules`). Direct `npx jest`
won't work without the flag.

**Wrangler deploy step fails with `Authentication error`.**
Re-create the API token at [Cloudflare â†’ My Profile â†’ API Tokens] with the
"Edit Cloudflare Workers" template. Update the GitHub secret.

**Analyzer fails locally but passes in CI.**
You probably don't have `flutter_lints` resolved. Run `flutter pub get`.
The package is declared in `dev_dependencies` (added to `pubspec.yaml` for
this reason).


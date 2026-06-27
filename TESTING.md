# Testing & CI/CD Guide

This document explains how to run, extend, and ship the SIAS - Smart Industrial Alert System test
suite. Two separate harnesses live in this repo:

| Harness | Tooling | Scope |
|---|---|---|
| Flutter app | `flutter test` | Dart code under [lib/](lib/) â€” parser, models, services, widgets |
| Cloudflare Worker | Jest | The pure helpers in [cloudflare_worker.js](cloudflare_worker.js) |

GitHub Actions wires both together in [.github/workflows/ci.yml](.github/workflows/ci.yml).

---

## Quick start

```bash
# Flutter side
flutter pub get
flutter test                 # 198 tests
flutter analyze --no-fatal-infos --no-fatal-warnings

# Worker side
npm install
npm test                     # 123 tests, <2s
```

Both suites are hermetic â€” no Firebase emulator, no Cloudflare account, no
network access required.

---

## Flutter test layout

```
test/
â”œâ”€â”€ voice_command_parser_test.dart        # 117 cases â€” every parser path
â”œâ”€â”€ widget_test.dart                       # smoke
â”œâ”€â”€ theme_test.dart                        # AppTheme tokens + extension
â”œâ”€â”€ models/
â”‚   â”œâ”€â”€ alert_model_test.dart              # fromMap/toMap/copyWith
â”‚   â”œâ”€â”€ user_model_test.dart
â”‚   â”œâ”€â”€ collaboration_model_test.dart
â”‚   â””â”€â”€ predictive_models_test.dart
â”œâ”€â”€ services/
â”‚   â””â”€â”€ offline_account_cache_test.dart    # SharedPreferences-backed
â”œâ”€â”€ utils/
â”‚   â”œâ”€â”€ factory_id_test.dart
â”‚   â””â”€â”€ alert_meta_test.dart
â””â”€â”€ widgets/
    â””â”€â”€ locator_painter_test.dart
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

```
worker_test/
â”œâ”€â”€ factory_id.test.js          # aiSanitizeFactoryId, aiResolveFactory
â”œâ”€â”€ score_supervisor.test.js    # buildSupStats, scoreSupervisor
â”œâ”€â”€ predictive_model.test.js    # buildPredictiveModel + _toMs
â””â”€â”€ briefing_helpers.test.js    # _aggregateWeek, notifTitle, FCM routing
```

### How the worker exposes pure functions

Cloudflare Workers ships ESM with a `default` export. Jest needs named
exports, so the worker file ends with a named-export block (look for the
`Test-only named exports` comment in
[cloudflare_worker.js](cloudflare_worker.js)). The named exports are inert
in production â€” Cloudflare only consumes the default export.

To test a new helper:

1. Make sure the function is `function name(...)` at module scope (not
   nested inside another function or behind a side-effecting top-level
   `await`).
2. Add it to the named-export block at the bottom of `cloudflare_worker.js`.
3. Import it in a `worker_test/foo.test.js` file:

   ```js
   import { describe, test, expect } from '@jest/globals';
   import { newHelper } from '../cloudflare_worker.js';

   describe('newHelper', () => {
     test('does the thing', () => {
       expect(newHelper(42)).toBe('forty-two');
     });
   });
   ```

### Running

```bash
npm test               # one-shot
npm run test:watch     # rebuild on change
npm run test:rules     # Firebase RTDB rules/configuration behavior only
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
`main` and every pull request, with two parallel jobs:

### `flutter` job

1. Sets up JDK 17 (required by AGP 8) and Flutter `3.27.4` (stable).
2. Caches `~/.pub-cache` and `.dart_tool`.
3. `flutter pub get`.
4. `flutter analyze --no-fatal-infos --no-fatal-warnings` â€” fails on real
   errors only. The codebase has pre-existing `withOpacity` deprecation
   infos that don't block CI.
5. `flutter test --reporter expanded` (blocking; no auto-fix bypass).
6. `flutter build apk --debug` and `flutter build web --release`.
7. Uploads the web build as a CI artefact (`web-build`, 7-day retention).

### `worker` job

1. Sets up Node 20 with the `npm` cache.
2. `npm ci`.
3. `npm test` â€” runs the Jest suite.
4. **`wrangler deploy`** â€” only on direct pushes to `main` and only when
   `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are present. Forks
   and pull requests skip the deploy step automatically.

### Required GitHub repository secrets

| Secret | Purpose |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Wrangler auth token (scope: `User Details:Read`, `Workers Scripts:Edit`) |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account id |
| `FIREBASE_TOKEN` | (Already used by `deploy.yml` for Firebase Hosting.) |

Set these under **Settings â†’ Secrets and variables â†’ Actions** in your
GitHub repo. Without them, the `worker` job still runs the Jest suite â€”
only the deploy step is skipped (with a warning annotation).

### Worker secrets (separate from GitHub secrets)

The worker itself reads runtime secrets via the Cloudflare environment:

```bash
wrangler secret put FB_DB_URL
wrangler secret put FB_CLIENT_EMAIL
wrangler secret put FB_PRIVATE_KEY
wrangler secret put ANTHROPIC_API_KEY
wrangler secret put GEMINI_API_KEY
```

These never go through GitHub â€” they live in Cloudflare's secret store and
are visible to the worker at runtime as `env.FB_DB_URL`, etc.

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


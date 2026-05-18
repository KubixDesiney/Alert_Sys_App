# Smart Industrial Alert - SIA App Handoff Notes

Last verified: 2026-05-15 from the local repository.

This file is the working context for future coding agents. Keep it updated when the
app structure, worker deployment, Firebase schema, or CI behavior changes.

## Product Summary

Smart Industrial Alert - SIA is a Flutter industrial supervision app for factory alerts. It combines:

- Live alert intake, assignment, claiming, resolution, escalation, and validation.
- Admin and supervisor role flows backed by Firebase Authentication and Realtime Database.
- AI supervisor assignment, shift commander actions, collaboration decisions, predictive risk, and morning briefings.
- Firebase Cloud Messaging plus local full-screen notifications for alert buzz and voice claim actions.
- Offline-aware startup, cached account role data, queued worker triggers, and background sync.
- Voice command and voice claim flows with Android-native lock-screen capture, Sherpa ONNX STT, TFLite speaker verification, and fallback stubs for non-Android platforms.
- Factory hierarchy, assets, custom plant maps, station QR scanning, location tracking, and locator routing.

## Current Versions

- Flutter app package: `Smart Industrial Alert - SIAapp`
- Flutter app version: `1.1.2+6`
- Dart SDK constraint: `>=3.10.3 <4.0.0`
- Flutter SDK constraint: `>=3.38.4`
- CI Flutter version: `3.41.6`
- Worker npm package: `Smart Industrial Alert - SIA-worker@1.1.0`
- CI Node version: `20`
- Firebase project alias: `alertappsys`
- Primary target platform: Android. Web, iOS, Windows, Linux, and macOS have support paths, but Android has the full voice/lock-screen stack.

## Repository Map

- `lib/`: Flutter application code. There are currently 127 Dart files.
- `lib/main.dart`: Firebase init, service init, providers, localization, auth gate, role router, offline account fallback.
- `lib/config/app_config.dart`: Single source for worker URLs, Dart defines, worker endpoints, and request timeouts.
- `lib/models/`: Alert, user, collaboration, hierarchy, factory map, shift, and predictive data models.
- `lib/providers/alert_provider.dart`: Main app state facade for alert streams, per-supervisor alert buckets, actions, comments, critical flags, help, and assistance.
- `lib/services/`: Firebase, alerts, auth, FCM, voice, AI, predictions, shifts, hierarchy, location, offline, PDF, and worker queue services.
- `lib/services/ai/`: Dart AI scoring engine, state manager, feedback repository, and score adjuster.
- `lib/screens/`: Admin, supervisor, alert tree, detail, scan, mapping, locator, collaboration, voice, dashboard, hierarchy, and escalation screens.
- `lib/widgets/`: Shared UI widgets for dashboard, overview, shifts, admin header/tabs, loading/empty/offline states, locator painter, voice command button, and AI logs.
- `android/app/src/main/kotlin/com/example/Smart Industrial Alert - SIAapp/`: Native Android method channels and lock-screen voice capture.
- `assets/models/conformer_tisid_small.tflite`: Speaker embedding model used by voice auth.
- `worker/`: Modular Cloudflare worker source and helper modules. This is also re-exported by `cloudflare_worker.js` for tests and compatibility.
- `worker_test/`: Jest worker test suite. There are currently 11 worker test files.
- `test/`: Flutter unit/widget tests. There are currently 20 Dart test files.
- `functions/`: Firebase Cloud Functions. Includes legacy OneSignal push and AI retry triggers.
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
flutter build apk --debug --dart-define=Smart Industrial Alert - SIA_WORKER_SHARED_SECRET=... --dart-define=Smart Industrial Alert - SIA_AI_WORKER_URL=https://alert-notifier.aziz-nagati01.workers.dev --dart-define=Smart Industrial Alert - SIA_NOTIFY_WORKER_URL=https://Smart Industrial Alert - SIA.aziz-nagati01.workers.dev
flutter build web --release --no-wasm-dry-run --dart-define=Smart Industrial Alert - SIA_AI_WORKER_URL=https://alert-notifier.aziz-nagati01.workers.dev --dart-define=Smart Industrial Alert - SIA_NOTIFY_WORKER_URL=https://Smart Industrial Alert - SIA.aziz-nagati01.workers.dev
```

Workers:

```bash
npm install
npm test
npm run test:watch
npx wrangler deploy --config wrangler.ai.toml
npx wrangler deploy --config wrangler.notify.toml
```

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

Smart Industrial Alert - SIA uses two active Cloudflare Workers so notification delivery does not compete with AI/security work inside one invocation.

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
- Optional LSTM forecast integration through `https://kubixdesiney-Smart Industrial Alert - SIA-lstm.hf.space/predict`.
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
- LSTM cron is currently gated by `LSTM_CRON_ENABLED = false`.
- Runs security anomaly scan every 30 minutes.
- Writes health with assignment, collaboration, handover, security, LSTM, and error metrics.

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
- `POST /predict-lstm`
- `GET /security-status`
- `POST /ai-retry`
- `/` default manual trigger for AI/security work only.

### Notifications Worker

- Worker name: `Smart Industrial Alert - SIA`
- URL: `https://Smart Industrial Alert - SIA.aziz-nagati01.workers.dev`
- Main file: `cloudflare_notify_worker.js`
- Config: `wrangler.notify.toml`
- Cron: every minute (`* * * * *`)

Responsibilities:

- New-alert push fan-out through `processAlerts`.
- Queued in-app notification fan-out through `fanOutPendingNotifications`.
- Single alert push shortcut through `pushSingleAlert`.
- FCM token cleanup for unregistered tokens.
- Basic request rate limiting.
- Notification worker health under `workers/health/notifyLastRun`.

HTTP routes:

- `GET /config`: notification worker status.
- `POST /notify`: queues a notification cycle; if a POST body has `alertId`, it tries that alert first.
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

No-recipient push behavior:

- `processAlerts` and `pushSingleAlert` now call `skipAlertPush(alertUrl, 'no_recipients')`.
- That writes `push_sent: true`, clears `push_sending`, clears `push_last_error_at`, and records `push_skip_reason`.
- Retryable FCM failures still keep `push_sent: false` through `finishAlertPush(alertUrl, false)`.

### Compatibility And Deprecated Worker Files

- `cloudflare_worker.js` re-exports `./worker/index.js`. Worker tests import it for modular helper coverage.
- `worker/index.js` is a modular worker implementation with AI, assignment, predictions, fanout, and helper exports.
- `cloudflare_workerV2.js` is the deprecated monolithic fallback. Some tests still import unique helpers from it.
- `wrangler.toml` is retained as legacy fallback config and points at `cloudflare_workerV2.js`.
- `worker/wrangler.toml` also points at the deprecated monolith from the worker folder.
- Active production deployments should use `wrangler.ai.toml` and `wrangler.notify.toml`.

## Worker Secrets And Runtime Config

Set Cloudflare secrets per worker. Do not commit secret values.

- `FB_DB_URL`
- `FB_API_KEY`
- `FIREBASE_SERVICE_ACCOUNT`
- `FB_DB_Secret` if still needed by operational scripts.
- Optional AI/provider secrets used by AI endpoints.
- `WORKER_SHARED_SECRET` / `Smart Industrial Alert - SIA_WORKER_SHARED_SECRET` when protected worker requests are enabled.

`FIREBASE_SERVICE_ACCOUNT` is parsed by the workers to mint Firebase custom auth JWTs and FCM OAuth tokens at the edge.

## Flutter Config

`lib/config/app_config.dart` owns cross-cutting constants:

- `Smart Industrial Alert - SIA_WORKER_URL`: legacy fallback URL.
- `Smart Industrial Alert - SIA_AI_WORKER_URL`: AI/security worker base URL.
- `Smart Industrial Alert - SIA_NOTIFY_WORKER_URL`: notification worker base URL.
- `Smart Industrial Alert - SIA_WORKER_SHARED_SECRET`: optional request secret.
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
- Runs `Smart Industrial Alert - SIAApp`.

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

Alert fields used across app and workers:

- Identity/location: `id`, `alertNumber`, `type`, `usine`, `factoryId`, `convoyeur`, `poste`, `adresse`, `assetId`.
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
- `onesignalId` in legacy Cloud Functions path
- `currentLocation`
- `aiOptOut`
- `aiCooldownUntil`

Role conventions:

- `admin`: admin dashboard, broad database access, can manage hierarchy, supervisors, settings, shifts, collaborations.
- `supervisor`: dashboard, alert handling, collaboration/help, voice claim, location tracking.
- Other roles can log in if role is valid, but non-admin routing currently lands on supervisor dashboard.

## Alert Lifecycle

Typical app path:

1. Admin or integration creates an alert under `alerts`.
2. Alert creation reserves `alertCounter`.
3. Alert includes `push_sent: false` for the notification worker.
4. `WorkerTriggerQueue.enqueueAlertTrigger(alertId)` can POST to the notification worker.
5. Notification worker claims the alert push lock using Firebase ETag and writes `push_sending: true`.
6. FCM data-only alert push is sent to eligible recipients.
7. Worker marks the alert `push_sent: true`, or leaves it `false` only for retryable FCM failures.
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

Notification worker recipient logic:

- Supervisors are eligible by factory unless `allFactories` is set.
- Busy supervisors are excluded unless `allSupervisors` is true.
- Busy means active `en_cours` ownership/assistance or a valid `supervisor_active_alerts` entry for an in-progress alert.
- Optional active status gate accepts `active`, `available`, `online`, `ready`, `active: true`, or `isActive: true`.
- Admin inclusion is controlled per notification type.
- Unregistered FCM tokens are cleared from RTDB only if the stored token still matches the failed token.

Queued notification fan-out:

- Reads `notifications/{uid}`.
- Skips legacy `new_alert` queue types.
- Supports collaboration, assistant, cross-factory, help, critical update, AI recommendation, AI rejection, and alert suspended types.
- Writes notification fan-out status fields after FCM send attempts.

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
- `_runLstmForecast` is available but cron-disabled.

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

- `sendAlertPush`: legacy OneSignal push on alert creation.
- `retryAIAssignmentOnAlertAvailable`: retries AI when an alert becomes available/unassigned.
- `retryAIAssignmentOnSupervisorAvailable`: retries AI when a supervisor becomes active.
- `retryAIAssignmentOnCooldownSignal`: sleeps until cooldown signal expiry, then retries one factory.
- `retryAIAssignmentOnUserCooldown`: fallback cooldown expiry watcher.
- `retryAIAssignmentOnAlertResolved`: retries AI when an alert is validated/resolved.

Operational warning:

- The legacy OneSignal path contains hard-coded OneSignal credentials in source. Do not copy those values into docs or new code. Prefer Cloudflare/FCM paths and rotate/remove legacy secrets when possible.

## Testing Inventory

Worker Jest tests:

- `auth_gate.test.js`
- `briefing_helpers.test.js`
- `factory_id.test.js`
- `notification_fanout.test.js`
- `predictive_model.test.js`
- `proximity.test.js`
- `reliability.test.js`
- `score_supervisor.test.js`
- `scoring.test.js`
- `security_prompt_injection.test.js`
- `validation.test.js`

Flutter tests:

- `theme_test.dart`
- `voice_command_parser_test.dart`
- `widget_test.dart`
- Model tests for alert, collaboration, predictive, and user models.
- Service tests for AI scoring, alert actions, alert stream, collaboration, offline account cache, predictive scope, AI score adjuster, and reinforcement.
- Utility tests for alert metadata and factory ids.
- Widget tests for admin dashboard, factory location picker, and locator painter.

Current verified worker result:

- `npm test`: 11 suites passed, 154 tests passed.

## CI And Deploy

`.github/workflows/ci.yml`:

- Runs on pushes to `main`, pull requests to `main`, and manual dispatch.
- Flutter job:
  - Checkout.
  - Java 17.
  - Flutter 3.41.6 stable.
  - Pub cache.
  - `flutter pub get`.
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`.
  - `flutter test --reporter expanded`.
  - Optional AI auto-fix flow for failing Flutter tests through `/auto-fix-full`.
  - Builds Android debug APK and Flutter web release with split worker URLs.
  - Uploads `build/web`.
- Worker job:
  - Node 20.
  - `npm ci || npm install`.
  - `npm test`.
  - On direct non-AI-fix pushes to `main`, deploys both split workers.

`.github/workflows/deploy.yml`:

- Builds Flutter web release with split worker URLs.
- Installs Firebase CLI.
- Deploys Firebase Hosting from `build/web`.

Required GitHub Actions secrets:

- `WORKER_SHARED_SECRET`
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `FIREBASE_TOKEN`

## Important Gotchas

- Do not write strings to `alerts/{id}/push_sent`; database rules require boolean.
- Keep `cloudflare_notify_worker.js` and `worker/alerts.js` behavior aligned when changing notification fan-out.
- Keep `database.rules.json` validation aligned with any new alert fields written by workers or Flutter.
- `cloudflare_workerV2.js` is deprecated but still test-covered for some helpers; avoid deploying it as normal production.
- `README.md` still references older monolithic-worker concepts in places. The active deployment truth is the split worker configs.
- `TESTING.md` has some stale CI version text. Check `.github/workflows/ci.yml` for current CI versions.
- `cloudflare_ai_worker.js` and `cloudflare_workerV2.js` contain null bytes/mojibake in places; use `rg -a` if normal search treats them as binary.
- `lib/screens/overview_tab.dart` may have local uncommitted changes in this workspace; do not revert user changes.
- Generated Flutter localization files live under `lib/l10n/generated`; update ARB files and regenerate instead of hand-editing generated files when possible.
- `firebase_options.dart` is generated by FlutterFire; avoid manual edits unless intentionally updating Firebase config.
- `node_modules`, `.dart_tool`, `build`, `.wrangler`, and Firebase/Flutter generated caches should not be committed.

## Recent Local Fix

On 2026-05-15, the notification push lock behavior was fixed:

- No-recipient new alert pushes now close with `skipAlertPush(..., 'no_recipients')`.
- `push_sent` remains boolean-safe and is set to `true` for no-send skip completion.
- `push_sending` and `push_sending_at` are cleared.
- `push_skip_reason` validation was added to `database.rules.json`.
- `worker/alerts.js` was kept in sync with the deployed notification worker.
- `npm test` passes all worker tests after the change.


# Smart Industrial Alert - SIA App Handoff Notes

Last verified: 2026-06-10 from the local repository.

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
- SuperAdmin command console (role `superadmin`/`SuperAdmin`) with on-device forecaster training/deployment, an AI Agent Fleet console (per-agent on/off toggles, action logs, stats decks, AI-assist prompt editing, security defense toggles, predictive learning telemetry), Production Manager account provisioning, platform-wide logs/bugs/security/cron/database observability, and a reserved hardware tab.
- Pure-Dart gradient-boosted decision tree (GBDT) forecaster (no external inference service) that trains in seconds on uploaded company alert history (CSV/Excel/JSON/SQL dump/PDF), serves live next-24h machine risk on every Production Manager dashboard, grades its own forecasts against realized alerts, and adapts daily on fresh production data.

## Current Versions

- Flutter app package: `Smart Industrial Alert - SIAapp`
- Flutter app version: `1.2.1` (source of truth: pubspec.yaml)
- Dart SDK constraint: `>=3.10.3 <4.0.0`
- Flutter SDK constraint: `>=3.38.4`
- CI Flutter version: `3.41.6`
- Worker npm package: `Smart Industrial Alert - SIA-worker@1.1.0`
- CI Node version: `20`
- Firebase project alias: `alertappsys`
- Primary target platform: Android. Web, iOS, Windows, Linux, and macOS have support paths, but Android has the full voice/lock-screen stack.

## Repository Map

- `lib/`: Flutter application code. There are currently 140 Dart files.
- `lib/main.dart`: Firebase init, service init, providers, localization, auth gate, role router, offline account fallback.
- `lib/config/app_config.dart`: Single source for worker URLs, Dart defines, worker endpoints, and request timeouts.
- `lib/models/`: Alert, user, collaboration, hierarchy, factory map, shift, and predictive data models.
- `lib/providers/alert_provider.dart`: Main app state facade for alert streams, per-supervisor alert buckets, actions, comments, critical flags, help, and assistance.
- `lib/services/`: Firebase, alerts, auth, FCM, voice, AI, predictions, shifts, hierarchy, location, offline, PDF, and worker queue services.
- `lib/services/ai/`: Dart AI scoring engine, state manager, feedback repository, and score adjuster.
- `lib/services/forecast/`: Pure-Dart GBDT forecaster stack — multi-format dataset parser, tabular feature engineer, histogram gradient-boosting engine, resumable trainer (+ learning diagnosis), app-global training controller (background runs + checkpoint auto-resume), RTDB model store, forecast engine, continuous-learning service (outcome grading + adaptation boosting), and the overview engine that adapts forecasts into the PM dashboard's predictive cards.
- `lib/services/superadmin_service.dart`: Production Manager account provisioning via a secondary Firebase app.
- `lib/services/bug_report_service.dart`: Deduplicated client error reporting into `bugs/client`.
- `lib/screens/`: Admin, supervisor, alert tree, detail, scan, mapping, locator, collaboration, voice, dashboard, hierarchy, and escalation screens.
- `lib/screens/superadmin/`: SuperAdmin command console (theme, shell, AI Training, AI Agents, Production Managers, Logs, Hardware tabs).
- `lib/widgets/`: Shared UI widgets for dashboard, overview, shifts, admin header/tabs, loading/empty/offline states, locator painter, voice command button, and AI logs.
- `android/app/src/main/kotlin/com/example/Smart Industrial Alert - SIAapp/`: Native Android method channels and lock-screen voice capture.
- `assets/models/conformer_tisid_small.tflite`: Speaker embedding model used by voice auth.
- `worker/`: Modular Cloudflare worker source and helper modules. This is also re-exported by `cloudflare_worker.js` for tests and compatibility.
- `worker_test/`: Jest worker test suite. There are currently 14 worker test files.
- `test/`: Flutter unit/widget tests. There are currently 27 Dart test files.
- `tool/autonomous_bugfix_agent.mjs`: Autonomous bug-fix runner for UI/worker/log/RTDB health checks, Claude fix generation, OpenAI review gating, direct `main` push, Firebase Hosting deploy, optional worker deploy, `bugs/agent` RTDB run records, and GitHub issue escalation on rejection.
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

Autonomous bug-fix agent:

```bash
npm run agent:bugfix:dry-run
npm run agent:bugfix
```

Active agent runs require `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, git credentials that can push to `main`, and any runtime context secrets needed for Firebase/worker health.

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
- URL: `https://alertsys.aziz-nagati01.workers.dev`
- Main file: `cloudflare_notify_worker.js`
- Config: `wrangler.notify.toml`
- Cron: every minute (`* * * * *`)

Responsibilities:

- New-alert push fan-out through queued `/notifications/{uid}/{notifId}` rows.
- Legacy `/alerts` push fallback through `processAlerts`.
- Queued in-app notification fan-out through `fanOutPendingNotifications`.
- Single alert push shortcut through `pushSingleAlert`.
- Single queued notification shortcut through `pushSingleNotification`.
- FCM token cleanup for unregistered tokens.
- Basic request rate limiting.
- Notification worker health under `workers/health/notifyLastRun`.

HTTP routes:

- `GET /config`: notification worker status.
- `POST /notify`: queues a notification cycle. Fast-path payloads:
  - `{ "alertId": "<alertId>" }` tries one alert first.
  - `{ "notification": { "uid": "<uid>", "notifId": "<notifId>" } }` tries one queued notification first.
  - `{ "notifications": [{ "uid": "<uid>", "notifId": "<notifId>" }] }` tries a bounded batch of queued notifications first.
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

Push lock fields on queued notifications:

- `pushSent`: boolean completion flag.
- `pushSentAt`: ISO completion timestamp.
- `pushSending`: boolean lock flag.
- `pushSendingAt`: ISO lock timestamp.
- `pushLastErrorAt`: ISO retryable failure timestamp.
- Stale notification locks are retried after `NOTIFICATION_LOCK_TTL_MS = 2 minutes`.

No-recipient push behavior:

- `processAlerts` and `pushSingleAlert` now call `skipAlertPush(alertUrl, 'no_recipients')`.
- That writes `push_sent: true`, clears `push_sending`, clears `push_last_error_at`, and records `push_skip_reason`.
- Retryable FCM failures still keep `push_sent: false` through `finishAlertPush(alertUrl, false)`.

Real-time delivery behavior:

- Producers call `POST /notify` immediately after Firebase writes commit.
- The worker still reads RTDB and claims ETag locks before sending, so duplicate producer triggers are safe.
- The one-minute cron remains the durable fallback for missed producer triggers, offline clients, worker errors, and retryable FCM failures.
- New-alert FCM delivery uses the same targeted queue path as collaboration/help/AI notifications: producers write supervisor-only `new_alert` rows under `/notifications`, then call `POST /notify` with exact refs.
- The `/alerts/{alertId}` push path remains only as a fallback when queued `new_alert` rows cannot be created. It targets supervisors, not admins/Production Managers.
- App-created queued `new_alert` rows use `pushDeliveryMode: notification_queue`; the alert record is marked with `push_delivery_mode: notification_queue` so cron does not send a duplicate `/alerts` fan-out.
- WebSockets/Durable Objects are not the primary wake-up mechanism because Firebase writes do not wake a Worker WebSocket, and mobile background sockets are not reliable; FCM remains the background/offline delivery path.

### Compatibility And Deprecated Worker Files

- `cloudflare_worker.js` re-exports `./worker/index.js`. Worker tests import it for modular helper coverage.
- `worker/index.js` is a modular worker implementation with AI, assignment, predictions, fanout, and helper exports.
- `cloudflare_workerV2.js` (the deprecated monolith) was DELETED on 2026-06-14. The four test files that imported unique helpers from it (`predictive_model`, `proximity`, `reliability`, `security_prompt_injection`) were repointed to the deployed `cloudflare_ai_worker.js`, which already exports every symbol they need. All 15 worker suites (188 tests) pass against the deployed worker.
- The legacy `wrangler.toml` and `worker/wrangler.toml` (both pointed at the deleted monolith) were also DELETED on 2026-06-14. The old `wrangler.toml` was named `alert-notifier`, so a bare `wrangler deploy` would have overwritten the live AI worker with dead code — removing it closes that footgun.
- Active production deployments use `wrangler.ai.toml` and `wrangler.notify.toml` only (`npm run deploy:ai` / `deploy:notify`; CI deploys with the same `--config` flags). There is no longer any bare-`wrangler.toml` deploy path.

## Worker Secrets And Runtime Config

Set Cloudflare secrets per worker. Do not commit secret values.

- `FB_DB_URL`
- `FB_API_KEY`
- `FIREBASE_SERVICE_ACCOUNT`
- `FB_DB_Secret` if still needed by operational scripts.
- Optional AI/provider secrets used by AI endpoints.
- `WORKER_SHARED_SECRET` / `Smart Industrial Alert - SIA_WORKER_SHARED_SECRET` when protected worker requests are enabled.
- Optional `NOTIFY_WORKER_URL` / `ALERTSYS_NOTIFY_WORKER_URL` for AI-worker-to-notification-worker fast triggers; defaults to `https://alertsys.aziz-nagati01.workers.dev/notify`.

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
- `ai_forecast` (GBDT model trees/metadata, training telemetry, resumable run checkpoint and persisted training dataset under `ai_forecast/training/*`, run history, self-evaluation ledger under `ai_forecast/accuracy/*`, adaptation lock under `ai_forecast/learning/lock`)
- `bugs/client` (deduplicated app error reports) and `bugs/agent` (autonomous agent run outcomes)

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

- `superadmin` (also accepted as `SuperAdmin` — role matching is case-insensitive in the app): SuperAdmin command console with forecaster training, Production Manager provisioning, and platform observability. Database rules check both literal spellings.
- `admin`: Production Manager — admin dashboard, broad database access, can manage hierarchy, supervisors, settings, shifts, collaborations.
- `supervisor`: dashboard, alert handling, collaboration/help, voice claim, location tracking.
- Other roles can log in if role is valid, but non-admin routing currently lands on supervisor dashboard.
- `security/*` and `workers/*` reads are limited to the worker service token and `superadmin`; plain `admin` accounts are deliberately excluded (enforced by `worker_test/database_rules_security.test.js`).

## Alert Lifecycle

Typical app path:

1. Admin or integration creates an alert under `alerts`.
2. Alert creation reserves `alertCounter`.
3. Alert initially includes `push_sent: false`.
4. The producer creates supervisor-only `new_alert` rows under `/notifications/{uid}/{notifId}` with `pushSent: false`.
5. `WorkerTriggerQueue.enqueueNotificationTriggers(...)` POSTs exact `{ uid, notifId }` refs to the notification worker fast path.
6. Notification worker claims each queued notification with `pushSending: true`, sends FCM with `notifType: new_alert`, then marks `pushSent: true`.
7. The alert record is marked `push_sent: true` / `push_delivery_mode: notification_queue` once queued rows are durable; if queuing fails, `WorkerTriggerQueue.enqueueAlertTrigger(alertId)` uses the legacy `/alerts` fallback.
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
- Supports supervisor-only `new_alert`, collaboration, assistant, cross-factory, help, critical update, AI recommendation, AI rejection, alert suspended, confirm-presence, and handover types.
- Fast-path FCM data includes `notifType`, `notificationId`, `recipientId`, and available `alertId`, `collabRequestId`, `helpRequestId`, `shiftId`, `factoryId`, and factory/name fields.
- Writes notification fan-out status fields after FCM send attempts.
- New-alert/collaboration/help/AI direct-notification types bypass busy-supervisor and factory gates because they are addressed to specific users.

AI-to-notification handoff:

- AI/Security worker keeps making decisions and writing alert/shift/collaboration state.
- User-visible AI Commander events are persisted under `notifications/{uid}/{notifId}` with `pushSent: false`.
- The AI worker then calls the Notifications worker with the exact `{ uid, notifId }` reference.
- If that worker-to-worker trigger fails, the queued notification stays pending and the notification cron sweeps it later.

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
  - queued-notification trigger with POST body `{ notification: { uid, notifId } }`.
  - queued-notification batch trigger with POST body `{ notifications: [{ uid, notifId }] }`.

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
- `database_rules_security.test.js` (security/workers/bugs/ai_forecast rule policy)
- `haversine.test.js`

Flutter tests:

- `theme_test.dart`
- `voice_command_parser_test.dart`
- `widget_test.dart`
- Model tests for alert, collaboration, predictive, shift, and user models.
- Service tests for AI scoring, alert actions, alert stream, collaboration, offline account cache, predictive scope, AI score adjuster, and reinforcement.
- Forecaster tests: `gradient_boost_test.dart` (loss beats the prior baseline on a separable task, learned rules hold, serialization round-trip, truncation, clone), `forecast_feature_engineer_test.dart` (daily rows, tabular samples, lags/trend/recency, padded inference features), `forecast_trainer_test.dart` (end-to-end learning verdict, cancel, small-dataset rejection, checkpoint resume, adaptation boosting), `alert_record_parser_test.dart` (CSV/JSON/SQL/PDF/timestamps/type normalization), `forecast_overview_engine_test.dart` (forecast→PredictiveModel adapter math, bucket decomposition, learning diagnosis, learning-verdict rule).
- Utility tests for alert metadata and factory ids.
- Widget tests for admin dashboard, factory location picker, and locator painter.

Current verified results (2026-06-12, after the AI Agent Fleet console, worker agent control plane, and PM predictive-card fix):

- `npm test`: 15 suites passed, 187 tests passed (new: `agent_control.test.js`).
- `flutter test`: 278 tests passed.
- `flutter analyze --no-fatal-infos --no-fatal-warnings`: clean (style infos only).
- `flutter build web --release --no-wasm-dry-run`: succeeds.

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

`.github/workflows/autonomous-bugfix-agent.yml`:

- Runs hourly and by manual dispatch.
- Probes deployed UI, Cloudflare worker config/security endpoints, recent logs, RTDB worker health, and configured detection commands.
- Builds structured context from `CLAUDE.md`, source files, logs, DB state, and worker responses.
- Sends the fix request to Claude using `CLAUDE_FIX_MODEL` (default `claude-opus-4-8`), applies safe text-file updates, then validates with Jest, Flutter analysis, and Flutter tests.
- Sends the resulting diff to the OpenAI review gate using `OPENAI_REVIEW_MODEL` (default `o3`).
- Retries up to three times with validation/review feedback.
- If approved, commits on `main`, pushes `HEAD:main`, builds Flutter web, and deploys Firebase Hosting directly.
- If rejected after all attempts, writes the rejection context under `.dart_tool/autofix-agent` and fails the workflow. There is no Slack/email human escalation path.

Required GitHub Actions secrets:

- `WORKER_SHARED_SECRET`
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `FIREBASE_TOKEN`
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- Optional but recommended: `AUTOFIX_GITHUB_TOKEN`
- Optional worker deploy: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` when `AGENT_DEPLOY_WORKERS=1`.

## Important Gotchas

- Do not write strings to `alerts/{id}/push_sent`; database rules require boolean.
- Keep `cloudflare_notify_worker.js` and `worker/alerts.js` behavior aligned when changing notification fan-out.
- Keep `database.rules.json` validation aligned with any new alert fields written by workers or Flutter.
- `cloudflare_workerV2.js` was deleted (2026-06-14); its helper test coverage now runs against the deployed `cloudflare_ai_worker.js`. Do not reintroduce a monolithic worker.
- `README.md` still references older monolithic-worker concepts in places. The active deployment truth is the split worker configs.
- `TESTING.md` has some stale CI version text. Check `.github/workflows/ci.yml` for current CI versions.
- A repo-wide scan on 2026-06-14 found no NUL bytes in any source file. `functions/index.js` previously carried a 767-byte NUL tail (now fixed; `node --check` passes). `cloudflare_ai_worker.js` parses cleanly (0 NUL bytes) but may still contain mojibake in string/comment literals; use `rg -a` if normal search treats it as binary.
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


## SuperAdmin Console And On-Device Gradient-Boosted Forecaster (2026-06-10, GBDT swap 2026-06-11)

A full SuperAdmin tier was added on top of the existing admin/supervisor roles, together with a working, trainable machine-learning forecaster and a platform-wide observability surface. On 2026-06-11 the original pure-Dart LSTM was replaced end-to-end by an XGBoost-class gradient-boosted decision tree (GBDT) engine with continuous learning — better accuracy on tabular alert history, trains in seconds instead of minutes, no scaler/window fragility, and it grades its own forecasts against reality.

### Role And Routing

- New role `superadmin` (case-insensitive in the app; rules accept both `superadmin` and `SuperAdmin` literals). Create the account record manually in Firebase: `users/{uid}/role = "SuperAdmin"`.
- `RoleRouter` (lib/main.dart) normalizes the role and routes superadmin to `SuperAdminDashboardScreen`; `OfflineAccountCache.normalizeRole` persists the canonical lowercase form for offline startup.
- Database rules: superadmin can read/write `users/{uid}` (for Production Manager provisioning), read `security/*`, `workers/*`, `bugs`, and write `ai_forecast`. Plain `admin` (Production Manager) accounts remain excluded from `security/*` and `workers/*` reads — enforced by `worker_test/database_rules_security.test.js`.
- Deploy rules after pulling: `firebase deploy --only database`.

### SuperAdmin Console (lib/screens/superadmin/)

Futuristic "Command Center" design with an animated neural-mesh vector background (`superadmin_theme.dart`: `SaPalette`, `NeuralBackground`, `GlassPanel`, `GlowChip`, `PulseDot`, `SaButton`, …). Since 2026-06-11 the console follows the app-wide `ThemeProvider` (light/dark): the dashboard build calls `Sa.setDark(...)` and a sun/moon toggle sits in the console header. `Sa` color tokens are palette *getters* (deep-space dark + arctic light), so never capture `Sa.*` colors inside `const` expressions. Terminal-style surfaces (console viewer, raw JSON blocks, DB schema map) intentionally stay dark in both themes via the fixed `Sa.term*` constants. Decorative painters (neural mesh, DB map) are throttled to ~25–30fps behind RepaintBoundaries, the header clock/status chips are isolated self-refreshing widgets, and `PulseDot` paints its ripple outside a fixed-size box so status chips never shift layout. Five tabs:

1. **AI Training** (`ai_training_tab.dart`): upload company alert history, watch deployed-model status plus the live continuous-learning ledger (forecasts graded, precision/recall, Brier score, last adaptation), auto-tuned but always-visible/editable hyperparameters (boosting rounds, learning rate, max depth, min leaf samples, subsample, L2 — AUTO-TUNE recomputes them from the dataset shape), live training monitor (gradient progress bar, train/val loss curves, accuracy/F1 curves, LEARNING/NOT-LEARNING verdict), next-24h forecast preview, one-click deploy.
2. **AI Agents** (`ai_agents_tab.dart`, added 2026-06-12): the AI Agent Fleet console — see "AI Agent Fleet" section below.
3. **Production Managers** (`production_managers_tab.dart`): provision/revoke Production Manager (`role: admin`) accounts and send password resets. Account creation runs through a secondary Firebase app (`superadmin_service.dart`) so the SuperAdmin session is never replaced.
4. **Logs** (`logs_tab.dart`): five live sections — Bugs (client errors only since 2026-06-12; the autonomous-agent run feed moved out of this tab — `bugs/agent` is still written by the bugfix workflow but no longer rendered), Console (AppLogBuffer live viewer with level filters), Security (enforcement actions + anomaly observations from `security/*`), Cron Health (both workers' pulses with freshness/staleness states and raw pulse view), Database (animated live topology map of RTDB roots with shallow-count probing via the REST API and per-node health).
5. **Hardware** (`hardware_tab.dart`): reserved placeholder with radar-sweep animation.

### AI Agent Fleet (2026-06-12)

`lib/screens/superadmin/ai_agents_tab.dart` presents six named agents as a fleet (horizontal agent cards + per-agent detail panels), each with an on/off toggle, an in-depth action log (tap any row for the full record), and a stats deck. Master switches and settings live under `ai_agents/{id}` in RTDB (`enabled`, `settings/*`, `promptTemplate`, worker-written `stats/*` + `logs/*`); the AI worker honors them through a 60-second cached control plane (`_loadAgentControl` in `cloudflare_ai_worker.js`) that **fails open** — a control-plane read error never takes agents down. Rules: `ai_agents` is readable by any authed client (PM dashboards/learner read switches) but writable only by superadmin or the worker service token (enforced in `worker_test/database_rules_security.test.js`).

- **Shift Commander (`shift`)**: flattened `shift_ai_logs` activity with kind breakdown bars and health-pulse stats. Disabling gates `runAIAssignments`, `processShiftCollaborations`, `processShiftEnding`, and `runShiftPresenceCheck` in the cron and the manual trigger (escalation checks always run — platform safety, not an agent). Worker bumps `ai_agents/shift/stats` per cron with atomic increments.
- **Briefing Officer (`briefing`)**: latest dispatch view, archive/factory-scope counts, REGENERATE NOW button (GET `briefingEndpoint?force=1`). Disabling makes `/briefing` serve the cached latest (any date) and never spend a Llama run; generation bumps `ai_agents/briefing/stats` and logs a row.
- **AI Assist (`assist`)**: Prompt Lab — the exact Llama prompt template is editable and deployable to `ai_agents/assist/promptTemplate` (placeholders `{type} {description} {usine} {convoyeur} {poste} {history}`, filled by `_assistFillPrompt`; override is sanitized + capped at 8KB; revert deletes the node). Knowledge Base shows the validated resolutions the agent cites (query `alerts` by `status == validee` with `resolutionReason`). Service log + served counter come from worker writes in `handleAiSuggest`. Disabling returns the static fallback suggestion with `agentDisabled: true`.
- **Security Sentinel (`security`)**: Defense Grid toggles under `ai_agents/security/settings/{promptInjection,rateLimiting,sanitization,anomalyScan,siemExport}` — `_securityGuard` checks them per-request (rate limit / injection scan / sanitize each individually gated), the cron gates the anomaly scan and SIEM flush. Threat mix bars + enforcement log from `security/actions`.
- **Predictive Core (`predictive`)**: model identity card (reads `ai_forecast/model/*` metadata children individually — the weights blob never enters the screen; refreshes on `version` bumps), precision/recall/Brier ring gauges from `ai_forecast/accuracy/latest`, Brier-per-day trend chart from `accuracy/history`, adaptation-budget bar (adaptedRounds/60), graded-day log. Settings `ai_agents/predictive/settings/{adaptationEnabled,outcomeGrading}`: `adaptationEnabled` is honored by the Dart `ForecastContinuousLearner` (via `ForecastModelStore.predictiveAgentFlag`), `outcomeGrading` by the worker learner.
- **Guardian (`guardian`)**: under-maintenance placeholder with radar-scan animation; toggle disabled.

### Worker-Side Forecast Outcome Learner (2026-06-12)

`_runForecastOutcomeCycle` in `cloudflare_ai_worker.js` (cron, every 30 min on the validation cadence, gated by the predictive agent + `outcomeGrading`) makes the GBDT continuous-learning loop survive with zero dashboards open: it (1) snapshots tomorrow's pending outcome from the latest `ai_predictions/forecast` publish into `ai_forecast/accuracy/pending/{yyyy-MM-dd}` (first write wins, same `usine~conv~poste` key scheme as the Dart learner), and (2) grades fully elapsed pending days against `alertsMap` using the tuned per-type decision thresholds the console mirrors to `ai_forecast/model/thresholds` at deploy/adapt time (added to `ForecastModelStore.saveModel`/`saveAdaptedModel`), folding hits/misses + Brier into the same `ai_forecast/accuracy/{latest,history}` ledger. Adaptation boosting itself stays on-device in Dart — the worker only grades.

### PM Predictive-Card Fix (2026-06-12)

The PM "not enough data" bug had three causes, all fixed in `forecast_overview_engine.dart`: (1) live inference fed **raw** `AlertModel.type` strings into features trained on canonical types — `updateAlerts` now routes through `AlertRecordParser.normalizeType`; (2) `overlayFor` discarded the whole AI overlay when no machine crossed the 0.2 failure floor, silently falling back to the often-absent statistical model — the overlay (risk curves are always real model output) is now kept, and when the plant is calm the failure list falls back to the top entries above a relaxed `kQuietFloor` (0.01) so the PM always sees ranked live forecasts; (3) the alert-stream change detector compared only list length — it now uses a length+newest-timestamp signature. Factory scoping is also case/whitespace-insensitive now.

### Pure-Dart Gradient-Boosted Forecaster (lib/services/forecast/)

The forecaster is a real second-order (Newton) gradient-boosting engine trained on-device — the same formulation XGBoost/LightGBM use, with no HuggingFace or external inference dependency:

- `forecast_types.dart`: canonical types (`kForecastAlertTypes`), the 8 base daily columns (`kDailyFeatureCols`, mirrors the worker's daily schema), the 25 engineered tabular columns (`kForecastFeatureCols`), `AlertRecord`/`DatasetSummary`/`FeatureSample`, `ForecastTrainingConfig` (auto-tuned from sample count; rounds/lr/depth/minLeaf/subsample/colsample/L2/patience/`posWeightCap` all visible+editable), `RoundStat` (round 0 = pre-boosting baseline), `MachineForecast`.
- `alert_record_parser.dart`: ingests CSV/TSV, JSON (incl. Firebase RTDB exports), Excel (.xlsx), MySQL dumps (.sql INSERT parsing with CREATE TABLE fallback), and PDFs (table extraction via Syncfusion + heuristic line scan). Header-synonym mapping (EN/FR), flexible timestamps (ISO, epoch s/ms, dd/MM/yyyy, Excel serial), type normalization onto the four canonical types.
- `forecast_feature_engineer.dart`: per-machine gap-free daily rows (same `_buildDailyFeatures` schema as the worker), then tabular samples per machine-day: today's snapshot, tomorrow's calendar context, total lags (t-1/t-2), per-type 7d rolling counts, 7/14d totals, week-over-week trend, per-type recency (capped 30d), critical pressure. No scaler — trees are scale-invariant. `buildInferenceFeatures` pads quiet machines to today.
- `gradient_boost.dart`: `BoostTree` (flat-array regression tree), `GradientBoostModel` (per-type ensembles + prior log-odds base scores, per-type `thresholds` for "alert called" classification, `truncated()` best-round snapshots, JSON (de)serialization, `baseRounds`/`adaptedRounds` bookkeeping), and `GbdtBooster` (histogram split finding with ≤64 quantile bins, leaf weights `-G/(H+λ)`, gain pruning, row/feature subsampling, shrinkage folded into leaves, class-imbalance weighting via per-type pos-weights capped at `config.posWeightCap`, `bestValThresholds()` grid-searches per-type decision thresholds that maximize validation F1, weighted-BCE/accuracy/macro-F1 eval from cached margins using those thresholds instead of a fixed 0.5).
- `forecast_trainer.dart`: deterministic seeded train/val split, a round-0 baseline stat so curves show the real improvement over the prior, one tree per type per round with ~10ms cooperative yielding (UI stays smooth on web/mobile), early stopping with best-round truncation, a quantitative learning verdict (best val loss <= 97% of the round-0 baseline), `diagnose()` for NOT-LEARNING explanations, checkpoint resume (`resumeModel`/`startRound`/`resumeStats`), and `adapt()` — the continuous-learning entry point that boosts a few stiffly-regularized extra trees onto a deployed model. After training, the final model's `thresholds` are set from `bestValThresholds()` on the held-out validation set, and live `RoundStat.valF1` curves use those same tuned thresholds (not a fixed 0.5) so F1 reflects genuine probability separation under class imbalance.
- `forecast_training_controller.dart`: app-global `ChangeNotifier` singleton (`ForecastTrainingController.instance`) that *owns* the dataset + training run; the AI Training tab is only a view of it. Training survives tab switches, console navigation, and sign-out while the app stays open. It checkpoints trees + round stats + config to `ai_forecast/training/checkpoint` (every ~10s) and persists the uploaded dataset (compact row encoding) to `ai_forecast/training/dataset`, so a closed browser tab/app auto-resumes the run on the next console open (`ensureResumed()`, called from `SuperAdminDashboardScreen.initState`). If another live session owns the run it spectates via `ai_forecast/training/latest` telemetry and takes over when the owner's heartbeat goes stale (>150s). A finished-but-undeployed run is restored from the checkpoint for one-click deploy; deploying clears the checkpoint (the dataset blob is kept for retraining).
- `forecast_model_store.dart`: persists the ensemble/metadata to `ai_forecast/model`, run history to `ai_forecast/history`, live training telemetry to `ai_forecast/training/latest`, the resumable checkpoint to `ai_forecast/training/checkpoint`, the persisted dataset to `ai_forecast/training/dataset`, the self-evaluation ledger to `ai_forecast/accuracy/{latest,history,pending}`, and the cross-dashboard adaptation lock to `ai_forecast/learning/lock`. Deploying a fresh model resets the accuracy ledger.
- `forecast_engine.dart`: on-device inference over recent alerts; publishes throttled snapshots to `ai_predictions/forecast`.
- `forecast_learning_service.dart` (`ForecastContinuousLearner`): the continuous-learning loop, driven opportunistically from open PM dashboards (self-throttled to one cycle per 30 min, no server component). (1) **Self-evaluation** — each day the engine snapshots what the model predicts for tomorrow under `accuracy/pending/{yyyy-MM-dd}`; once that day elapses, any dashboard grades it against the alerts that actually happened (hit/miss at p>=0.5 + Brier score) and folds the result into the rolling `accuracy/latest` ledger shown in the console. (2) **Adaptation** — at most once per ~20h (lock + re-read after claim), it boosts 6 extra trees per type onto the deployed ensemble from the last 120 days of live alerts (small lr, stiff L2, capped at +60 adaptive rounds until the next full retrain), bumping the model `version` so every dashboard streams the update.

### Production Manager Dashboard Integration

The deployed forecaster feeds the two existing predictive cards on the admin Overview tab directly:

- `lib/services/forecast/forecast_overview_engine.dart` (`ForecastOverviewEngine`, a `ChangeNotifier` owned by `AdminOverviewTab`) streams `ai_forecast/model`, re-runs on-device inference whenever the alert stream changes (throttled to 15s), keeps `ai_predictions/forecast` fresh (one write per 10 minutes across all open dashboards), and drives the `ForecastContinuousLearner` cycle.
- Its `overlayFor(selectedUsine, statisticalModel)` adapter converts per-machine `MachineForecast`s into the `PredictiveModel` shape both cards already render: one `PredictedFailure` per machine-type above a 0.2 probability floor (confidence = model probability, ETA heuristic `(1-p)*24h`, past/critical counts and last-seen from local alert history), and per-type `RiskCurve`s where the plant-wide day probability `1-Π(1-p_machine)` is decomposed exactly over twelve 2h buckets along the statistical curve's intra-day shape (falling back to the hour-of-day histogram, then uniform).
- `PredictiveFailureCard` and `PredictiveRiskHeatmap` take a `forecastLive` flag: subtitle and badge switch to "AI · LIVE"/"AI", and the statistical validated-accuracy badge hides (it doesn't describe the forecaster). With no deployed model — or no machine forecasts in the selected scope — both cards keep the statistical edge model as fallback.
- Adapter math and the learning diagnosis are covered by `test/services/forecast_overview_engine_test.dart`.

### Bugs Pipeline

- `lib/services/bug_report_service.dart` hooks `AppLogger.onErrorEntry` (every ERROR-level log) and `PlatformDispatcher.onError`, dedupes by FNV-1a hash, rate-limits (5 min/hash), and writes `bugs/client/{hash}` with area inference (auth/notifications/database/locator/supervisors/voice/shifts/ai/app), counts, and timestamps. Wired in `main.dart` right after `ServiceLocator.init()`.
- `tool/autonomous_bugfix_agent.mjs` now records every run to `bugs/agent` (`clean` / `ai_fixed` + commit / `escalated` + issueUrl / `rejected`) and, when all fix attempts are rejected, opens a GitHub issue (label `autofix-escalation`) via `AUTOFIX_GITHUB_TOKEN`/`GITHUB_TOKEN` before failing the workflow.
- The SuperAdmin Logs tab renders both nodes with status chips and issue links.

### New Dependencies

- `file_picker` (dataset upload) and `syncfusion_flutter_pdf` (PDF text extraction). Both web-compatible.

### Cleanup Performed (2026-06-10)

- Deleted: `android_old/`, `android_backup/`, `.idea/`, `alertsysapp.iml`, `lib/screens/admin/developer_tab.dart` (orphaned; superseded by the SuperAdmin Logs tab), root duplicate `firebase_options.dart` (app uses `lib/firebase_options.dart`), `WORKER_UPDATE_FILTER_CLAIMED.js`, debug exports (`__*.json`, `temp_error.json`, mangled `C:Users…` file), one-off scripts (`boost.cjs`, `trigger_flood.cjs`, `cleanup_flood.cjs`, `reset_push_sent.cjs`), and stale `flutter_*.log` / `.codex-*.log` files.
- `.gitignore` rewritten as clean UTF-8 (it contained a corrupted UTF-16 line) and extended with `__*.json`, `temp_error.json`, `service-account.json`.

### Operational Sequence: Train And Serve The Forecaster

1. SuperAdmin signs in (role `SuperAdmin`) and lands on the console.
2. AI Training tab → upload an alert-history export (CSV/Excel/JSON/SQL/PDF). The parser reports rows/machines/span/type distribution and engineering yields N training samples. The dataset is also persisted to `ai_forecast/training/dataset` so it survives reloads.
3. Hyperparameters are auto-tuned from dataset size (and always displayed/editable); Start Training runs genuine second-order gradient boosting with live loss/accuracy curves and a learning verdict — typically seconds, not minutes. The run is owned by `ForecastTrainingController` (app-global): switching tabs, navigating the console, or signing out does not interrupt it, and mid-run checkpoints land in `ai_forecast/training/checkpoint`. A NOT-LEARNING verdict renders a "Why the model didn't learn" panel (`ForecastTrainer.diagnose`): dataset volume/span, label sparsity/missing types, and loss-trajectory reasons with concrete fixes.
4. If the browser tab/app is closed mid-run, the next console session auto-resumes the run from the checkpoint round (`ensureResumed()`); a finished-but-undeployed run is likewise restored for review/deploy.
5. Deploy to Production writes the ensemble to `ai_forecast/model`, an immediate live snapshot to `ai_predictions/forecast` computed from production alerts, clears the run checkpoint, and resets the self-evaluation ledger.
6. Every Production Manager dashboard picks the model up via stream (`ForecastOverviewEngine`): the Predictive Failure Alerts card and the Predictive Risk · Next 24h heatmap switch from the statistical edge model to live on-device forecasts (badged "AI · LIVE"), refreshing as alerts arrive.
7. From then on the model learns continuously: open dashboards snapshot tomorrow's forecast daily, grade elapsed snapshots against realized alerts (precision/recall/Brier in the console's CONTINUOUS LEARNING strip), and boost a few adaptation trees per ~day on recent production data behind a cross-dashboard lock — until the SuperAdmin runs a full retrain.

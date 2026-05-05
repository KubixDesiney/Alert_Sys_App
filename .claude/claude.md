# AlertSys Architecture and Operating Guide (A to Z)

This document is the full technical map of the AlertSys project.
It explains what exists, why it exists, and how data and control flow from the first user action to final persistence and notifications.

## A. System Purpose

AlertSys is a multi-platform industrial alert management system built for factory environments.

Primary goals:
- Receive and track production alerts in real time.
- Assign and coordinate supervisors intelligently.
- Support voice-first operation, including lock-screen claim flows.
- Operate with offline resilience.
- Provide predictive and AI assistance for faster, safer operations.

## B. High-Level Architecture

The project is a hybrid stack:

1. Flutter client app
- Main app under lib/ with Provider state, screens, services, and models.
- Runs on Android, iOS, web, desktop targets.

2. Firebase platform
- Firebase Auth for authentication.
- Realtime Database as primary operational data store.
- Firebase Messaging for push delivery.

3. Cloudflare Worker
- Edge orchestration for alert fan-out, AI assignment, escalation checks, predictions, and briefing generation.
- Runs on cron every minute and via explicit HTTP triggers.

4. Optional Firebase Functions codebase
- Additional server-side automation and retry logic in functions/index.js.

5. On-device ML and speech stack
- sherpa_onnx for offline ASR on supported platforms.
- speech_to_text as fast capture path and fallback.
- tflite_flutter voice embedding model for speaker verification.

6. Test infrastructure
- Flutter tests in test/.
- Worker tests in worker_test/ using Jest.

## C. Repository Layout and Responsibilities

Top-level core files:
- lib/main.dart: app bootstrap, Firebase init, providers, role router.
- pubspec.yaml: Flutter dependencies and assets.
- cloudflare_worker.js: edge worker logic.
- wrangler.toml: worker deploy and cron configuration.
- database.rules.json: Realtime Database authorization and validation.
- firebase.json: hosting/functions/db project config.
- functions/index.js: Firebase Functions retry and notification flow.
- TESTING.md: full test and CI guidance.

Main source tree:
- lib/models/: data entities and mapping.
- lib/providers/: app state containers.
- lib/screens/: UI flows (dashboard, admin, voice, AR, scanning).
- lib/services/: business logic, integration logic, IO, notifications, AI/voice.
- lib/utils/: shared helpers and error formatting.
- lib/widgets/: reusable UI building blocks.

Backend and worker support:
- cloudflare_worker.js: main edge endpoint and cron execution.
- WORKER_UPDATE_FILTER_CLAIMED.js: reference patch for filtering already-engaged supervisors.
- worker_test/: tests for worker pure functions.
- functions/: Firebase Functions codebase.
- codebasedelta/: secondary functions codebase from firebase.json configuration.

Platform folders:
- android/, ios/, web/, windows/, linux/, macos/: platform integration.

## D. Bootstrap and App Lifecycle

App startup sequence (lib/main.dart):

1. WidgetsFlutterBinding.ensureInitialized.
2. AppLifecycleObserver attached to handle foreground/background transitions.
3. Global FlutterError handler wired to ServiceLocator logger.
4. Firebase initialization via _safeInitFirebase.
5. ServiceLocator initialized once (all core services registered).
6. OfflineDatabaseService.configure enables RTDB persistence and sync paths.
7. BackgroundSyncService.initialize starts reconnection and periodic sync.
8. WorkerTriggerQueue starts and begins reconnection-aware queue flush.
9. FirebaseMessaging background handler registered.
10. FcmService.init attempted with timeout guard.
11. Shorebird code push runtime instantiated.
12. VoiceService warmup triggered after first frame delay.
13. runApp(AlertSysApp).

Auth and role routing:
- AuthGate listens to FirebaseAuth authStateChanges.
- Unauthenticated users go to LoginScreen.
- Authenticated users go to RoleRouter.
- RoleRouter loads user record from RTDB users/{uid} with timeout.
- Falls back to OfflineAccountCache when network unavailable and cache exists.
- Routes admin to AdminDashboardScreen, others to DashboardScreen.

## E. Dependency and Service Wiring

ServiceLocator (lib/services/service_locator.dart) owns singleton-like service instances:
- AppLogger
- AuthService
- HierarchyService
- CollaborationService
- AlertService
- AIService
- AlertStreamService
- NotificationService
- AlertActionsService

Provider layer:
- AlertProvider: central operational state and user actions.
- ThemeProvider: theme mode state.

FcmService.alertProvider is injected from AlertProvider at app boot so notification-triggered voice actions can execute without BuildContext.

## F. Data Model Overview

Main operational entity is AlertModel (lib/models/alert_model.dart), with key fields including:
- id
- alertNumber (human-readable number)
- type
- usine, convoyeur, poste
- status (disponible, en_cours, validee)
- superviseurId/superviseurName
- assistantId/assistantName
- isCritical
- comments
- resolution metadata and elapsed times
- optional assistance tracking and collaboration metadata

Other major models:
- UserModel: user identity, role, usine, activity.
- CollaborationRequest and related collaboration entities.
- Hierarchy model: factory, conveyor, station structures.
- Factory map model: layout and visualization data.
- WorkInstructions model.
- Predictive model set: MorningBriefing, PredictiveModel, RiskCurve, PredictedFailure, AssigneeSuggestion.

## G. Realtime Database Structure

Core paths used by app and worker:
- alerts
- users
- notifications
- help_requests
- collaboration_requests
- supervisor_active_alerts
- hierarchy
- assets
- work_instructions
- ai_decisions
- ai_feedback
- ai_master
- ai_runtime
- factories/{factoryId}/aiConfig
- ai_predictions
- ai_briefing
- alertCounter
- assetCounter

Operational pattern:
- Client reads and writes directly where allowed by security rules.
- Worker and/or functions enrich data and trigger fan-out.
- UI consumes streams and local caches.

## H. Security and Access Control

database.rules.json enforces:
- Auth-required reads for most operational nodes.
- Strict write boundaries by role (admin/supervisor).
- Users node guarded by self-or-admin semantics.
- Critical AI nodes (ai_master, ai_feedback, ai_decisions writes) limited to admin contexts.
- Indexed fields for query efficiency on alerts, users, and collaboration structures.

Special allowances:
- alerts/$alertId write allows authenticated users and a constrained unauthenticated create path with required fields.
- supervisor_active_alerts scoped so users can write only own node unless admin.

## I. Alert Lifecycle and Command Flow

Lifecycle states:
- disponible: unclaimed and pending.
- en_cours: claimed.
- validee: resolved.

Main actions:
1. Create alert
- AlertService.createAlertWithHierarchy validates location via HierarchyService.
- Reserves alert number via alertCounter transaction.
- Writes alert node.
- Triggers worker endpoint for push fan-out.

2. Claim alert
- AlertService.takeAlert first cleans stale claim state.
- Transaction on supervisor_active_alerts/{uid} to enforce one active claim.
- Transaction on alert ensures still disponible and unassigned.
- On failure, clears active claim if needed and raises clear error.

3. Return to queue
- Clears supervisor assignment fields and taken timestamp.
- Optionally writes suspension reason.
- Clears supervisor_active_alerts mapping.

4. Resolve
- Writes resolution reason, elapsed time, resolvedAt, status validee.
- Can record assistance contributor metadata.
- Updates local state through provider callbacks.

5. Critical toggling
- AlertProvider.toggleCritical delegates write to actions service.
- NotificationService broadcasts critical update notification payloads.

## J. AlertProvider Responsibilities

AlertProvider handles:
- Stream initialization for supervisor or production manager mode.
- Loading flags and current time ticker for elapsed clock UI.
- Incremental pagination using loadOlderAlerts.
	- Derived lists: pending, claimed, fixed, assisted.
- Unified methods for take, resolve, comments, help, assistance, critical flags.
- Local optimistic updates via _updateLocal callback.

It is the central integration point between UI widgets and service layer.

## K. Stream Aggregation and Notification Detection

AlertStreamService combines multiple RTDB streams with RxDart:
- usine stream
- alerts where assistantId == current user
- alerts where superviseurId == current user

It:
- Deduplicates alerts by id.
- Sorts descending by timestamp.
- Detects newly added alert ids and calls AlertService.sendNewAlertNotification.
- Supports fallback to simpler stream if combined stream fails.

## L. Voice Pipeline

Voice architecture spans several services:

1. VoiceService
- Entry point for listening, capture, and TTS.
- Primary capture path uses speech_to_text for low-latency start.
- Lock-screen force path uses native voice lock activity channel on Android.
- TTS configured for factory audibility, with engine and voice selection best effort.

2. SherpaSttService (IO implementation)
- One-time model download and extract into app documents directory.
- Streaming Zipformer transducer decoding via sherpa_onnx.
- Used for lock-screen audio transcription and optional offline capabilities.

3. VoiceCommandParser
- Pure logic parser for intents and alert number extraction.
- Supports canonical command parsing and best-of-alternatives parsing.
- Handles number words to integer conversion and resolve reason extraction.
- Includes yes/no confirmation parsing.

4. VoiceAuthService
- Loads TFLite conformer speaker embedding model asset.
- Enrollment requires multiple samples, stores normalized embedding in users/{uid}/voiceprint.
- Verification computes cosine similarity against enrollment embedding.
- Includes quality gates: minimum speech duration and SNR threshold.

5. VoiceCommandDispatcher
- Executes parsed intents against AlertProvider.
- Applies voice verification unless caller already verified.
- Supports claim/resolve/escalate and feedback by speech.

## M. Lock-Screen Voice Claim Flow

Path driven by FCM action:

1. Notification contains action id voice_claim.
2. User taps action from lock screen.
3. FcmService routes to VoiceLockService/native flow on Android.
4. Audio captured and optionally transcribed by sherpa.
5. Command parsed with alternatives.
6. VoiceCommandDispatcher executes against provider with biometric check.
7. Result spoken to user via TTS.

Fallback behavior:
- If navigator is unavailable, pending state and timer defer navigation.
- If native flow unavailable, fallback to VoiceClaimScreen route.

## N. Notifications and Messaging

FCM and local notifications are coordinated by FcmService:
- Registers FirebaseMessaging handlers for foreground/background/opened-app.
- Creates high-importance Android channel for critical alerts.
- Shows local notifications with payloads tied to alert id.
- Supports full-screen intent permissions and lock-screen behavior.

Background handler:
- firebaseMessagingBackgroundHandler initializes Firebase in isolate and issues voice-action local notification.

In-app handling:
- Foreground messages also show snackbars and local notifs.
- Tap opens AlertDetailScreen for direct action.

## O. Collaboration and Assistance

CollaborationService supports multi-supervisor workflows:
- Build and validate collaboration requests.
- Compute approval plans for cross-factory transfers and existing active claims.
- Track per-target assistant decision states.
- PM approval workflow integration.
- Create internal notifications for involved users.
- Trigger worker notify queue for immediate push fan-out.

NotificationService handles:
- assistance requests
- help request accept/refuse
- critical-flag broadcasts

## P. Hierarchy, Assets, and Location Integrity

HierarchyService manages factory topology and asset mapping:
- Factory -> conveyors -> stations structure in hierarchy/factories.
- Validates alert location before creation.
- Generates and reserves asset IDs via assetCounter.
- Maintains asset records and movement history in assets path.
- Supports station add/update and asset assignment uniqueness cleanup.

WorkInstructionService provides location-aware context:
- Reads work instructions by alert type.
- Locates active alert at usine/convoyeur/poste and optional asset id.
- Offers live streams for active and historical location alerts.

## Q. Offline-First Strategy

OfflineDatabaseService:
- Enables RTDB persistence (non-web).
- Sets cache size.
- keepSynced on key operational paths.

OfflineAccountCache:
- Stores role/usine cache to allow offline role routing after prior online login.

WorkerTriggerQueue:
- Queues POST requests to worker endpoints locally in SharedPreferences.
- Replays queue when connection returns.
- Supports enqueue for notify, ai-retry, and alert-trigger endpoints.

BackgroundSyncService:
- Monitors .info/connected.
- Triggers AI history synchronization on reconnect.
- Runs periodic sync while connected.

## R. AI Assignment Architecture

AIAssignmentService features:
- Global enable state via ai_master.
- Per-factory enable and TTL settings via factories/{id}/aiConfig.
- Candidate scoring with workload/experience/location/feedback inputs.
- Cooldown and debounce controls.
- Rejection and feedback capture for iterative quality.
- Realtime history sync from aiHistory and ai_decisions nodes.

Operational outputs:
- Assignment decisions with reasons.
- Confidence labels.
- Considered candidates and skip reasons.
- Admin-facing logs.

## S. AI Suggestions and Predictive Intelligence

AIService:
- Calls worker /ai-suggest endpoint for resolution suggestions.

Predictive stack:
- PredictiveRepository fetches /briefing, /predict, /suggest-assignee endpoints.
- PredictiveIntelStreamService provides live RTDB streams from ai_briefing/latest and ai_predictions/latest.
- PredictiveIntelService is a facade that keeps API stable for screens.

Data products:
- Morning briefing summaries.
- Type-level risk curves and hourly probabilities.
- Predicted failures with confidence and ETA.
- Factory risk rankings.
- Assignee recommendation details.

## T. Cloudflare Worker Responsibilities

cloudflare_worker.js provides:
- CORS-enabled HTTP endpoints.
- Cron-triggered periodic processing every minute.
- Firebase token generation and caching.
- Push fan-out controls with internal max limits.
- Escalation checks.
- Supervisor scoring and assignment support helpers.
- Predictive model computation.
- Briefing aggregation.

Deployment:
- Configured in wrangler.toml.
- Main script cloudflare_worker.js.
- Cron trigger configured to * * * * *.

Local/CI worker package:
- package.json at root defines worker test and deploy scripts.

## U. Firebase Functions Responsibilities

functions/index.js includes retry-oriented assignment logic:
- Factory lock acquisition and release to avoid race assignments.
- Debounce guard per factory.
- AI enabled check per factory.
- Selection of oldest unassigned alert.
- Candidate supervisor filtering by availability/opt-out/cooldown/factory.
- Transactional assignment with notification and aiHistory writes.

This complements edge worker orchestration and can recover assignment opportunities after activity/state changes.

## V. Push Fan-Out and Filtering Behavior

Push routing principles across worker/functions/docs:
- Notify admins and relevant supervisors.
- Skip users with no token.
- Avoid over-notifying supervisors already carrying in-progress claims (documented update pattern in WORKER_UPDATE_FILTER_CLAIMED.js and PUSH_NOTIFICATION_UPDATE.md).
- Use pending notification records in RTDB and worker flush for actual FCM fan-out.

## W. Testing Strategy

Flutter tests (test/):
- Heavy parser coverage (voice_command_parser_test.dart).
- Model serialization and mapping tests.
- Utility tests.
- Widget and theme smoke/behavior tests.

Worker tests (worker_test/):
- factory id sanitation/resolution.
- supervisor scoring.
- predictive model helpers.
- briefing and notification helpers.

Tooling:
- flutter test for Dart side.
- npm test (Jest, vm modules) for worker side.

## X. Build, Deploy, and Runtime Environments

Flutter app:
- Standard multi-platform Flutter build targets.
- Shorebird code push support initialized at runtime.

Firebase:
- Realtime Database rules from database.rules.json.
- Hosting points to build/web with SPA rewrite.
- Multiple functions codebases listed in firebase.json.

Cloudflare Worker:
- Deployed by wrangler deploy.
- Secrets injected via wrangler secret put.

CI expectations (from TESTING.md):
- Flutter analyze and test.
- Worker npm test.
- Conditional worker deployment on main with secrets.

## Y. Operational Sequences (End-to-End)

Sequence 1: New alert created
1. User creates alert in app.
2. HierarchyService validates location.
3. AlertService writes alert with reserved alertNumber.
4. WorkerTriggerQueue enqueues trigger if needed.
5. Worker/functions fan-out notifications.
6. Alert streams update provider and all relevant UIs.

Sequence 2: Voice claim from lock screen
1. Push arrives with voice action.
2. User taps action.
3. Native capture runs.
4. Transcript produced (sherpa where available).
5. Parser extracts claim intent and alert number.
6. VoiceAuthService verifies speaker.
7. Dispatcher calls provider.takeAlert.
8. Transaction secures claim and TTS confirms result.

Sequence 3: Offline period and reconnect
1. Device loses connectivity.
2. RTDB cache serves local state where available.
3. Worker requests are queued in local storage.
4. Reconnect event triggers queue flush and background sync.
5. AI history and notifications catch up.

Sequence 4: AI assignment run
1. Worker/function scans eligible alerts and supervisors.
2. Applies scoring/cooldown/debounce rules.
3. Writes assignment transactionally.
4. Emits aiHistory/ai_decisions records.
5. Sends notification to selected supervisor.
6. Client syncs and displays assignment rationale/logs.

## Z. Extension Guide and Engineering Rules

When adding new features, follow these patterns:

1. Keep state transitions transactional
- For claim-like exclusivity use RTDB transactions, not blind update.

2. Keep provider methods thin
- Put persistence/business rules into services.

3. Use existing queue for worker side effects
- Do not add direct fire-and-forget network calls where offline matters.

4. Preserve role and rules alignment
- Any new DB node must be represented in database.rules.json and index strategy.

5. Add tests for parser/logic helpers
- Keep pure logic in testable files without UI or platform coupling.

6. Respect platform abstraction
- Keep io/stub split for platform-specific services.

7. Keep AI and predictive outputs explainable
- Include reason fields and confidence interpretation where possible.

8. Keep docs synchronized
- Update this file, TESTING.md, and worker/function notes when behavior changes.

---

## Quick File-to-Responsibility Index

- lib/main.dart: bootstrap, providers, role routing.
- lib/providers/alert_provider.dart: alert state and action entry points.
- lib/services/alert_service.dart: CRUD and transactional alert operations.
- lib/services/alert_stream_service.dart: merged streaming and new-alert detection.
- lib/services/fcm_service.dart: FCM + local notification + lock-screen action handling.
- lib/services/voice_service_io.dart: capture, TTS, lock-flow integration.
- lib/services/voice_command_parser.dart: intent and number parsing logic.
- lib/services/voice_command_dispatcher.dart: command execution and spoken feedback.
- lib/services/voice_auth_service_io.dart: enrollment and speaker verification.
- lib/services/ai_assignment_service.dart: assignment policy and logs.
- lib/services/predictive_repository.dart: worker predictive endpoint client.
- lib/services/hierarchy_service.dart: topology and asset mapping.
- lib/services/collaboration_service.dart: collaboration request and PM approval.
- lib/services/offline_database_service.dart: RTDB offline config.
- lib/services/worker_trigger_queue.dart: resilient worker trigger queue.
- cloudflare_worker.js: edge orchestration and predictive/briefing logic.
- functions/index.js: assignment retry and additional backend automation.
- database.rules.json: data authorization and validation rules.
- TESTING.md: testing and CI execution details.

This is the current architecture baseline for AlertSys.

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

## T. Cloudflare Worker Architecture

The worker codebase has been refactored into 15 modular ES6 modules under `/worker` directory. The root-level `cloudflare_worker.js` is a re-export shim that delegates to `worker/index.js`.

**Modular Worker Structure:**

**Core Entry Point:**
- `worker/index.js` — Orchestrates scheduled (cron) and fetch handlers, imports all modules, exports public APIs.

**Functional Modules:**

1. **auth.js** — Firebase service account auth, token generation and caching.
2. **alerts.js** — Alert state processing, timestamp updates, status transitions.
3. **ai_suggest.js** — AI suggestion proxy and insight endpoint handlers.
4. **auto_fix.js** — Automatic remediation logic (partial and full modes).
5. **briefing.js** — Morning briefing generation with factory-scoped aggregation via Llama 3.2.
6. **config.js** — CORS headers and configuration metadata endpoints.
7. **escalation.js** — Escalation policy checking and enforcement.
8. **fcm.js** — Firebase Cloud Messaging fan-out, token fetching, notification formatting.
9. **health.js** — Cron execution health monitoring and reporting to RTDB.
10. **load_core.js** — Parallel data loading: alerts, users, shifts, hierarchy, factories.
11. **predictive.js** — Predictive model computation, validation, history snapshot writes.
12. **scoring.js** — Supervisor scoring engine, workload calculations, candidate ranking.
13. **shift_commander.js** — Shift management, AI assignments during active shifts, handover generation.
14. **suggest_assignee.js** — Assignee recommendation endpoint.
15. **utils.js** — Shared utilities: factory ID sanitization, time handling, briefing slugs, shift window helpers.

**Scheduled Handler (Cron: every minute):**

1. Distributed lock acquisition via cron_lock RTDB node (prevents concurrent runs).
2. Load core data in parallel (loadCoreData).
3. Process alerts (state transitions, timestamps).
4. Check escalations.
5. Run AI assignments with shift override support.
6. Process shift collaborations (auto-approve when conditions met).
7. Process shift ending (generate handover summaries).
8. Validate predictions (cross-check historical forecasts against realized alerts).
9. Write cron health metrics to database.
10. Release lock.

**HTTP Fetch Handler Endpoints:**

- `/config` — Configuration metadata.
- `/ai-proxy` — AI integration proxy (Gemini, Claude, Llama).
- `/ai-suggest` — Alert resolution suggestions.
- `/predict` — Predictive model computation.
- `/briefing` — Morning briefing (supports `?factory=` query parameter for scoped briefings).
- `/suggest-assignee` — Assignee recommendation.
- `/auto-fix` — Partial automatic remediation.
- `/auto-fix-full` — Full automatic remediation.
- `/shift-ai-action` — Shift-specific AI operations (evaluate, handover, created, updated).
- `/validate-predictions` — Manual trigger for prediction validation run.
- `/ai-retry` — Trigger AI assignment retry.
- `/notify` — Fan-out pending notifications from RTDB queue.
- Default (all other fetch) — Unified manual trigger: runs assignments, alerts, escalations, collaborations.

**Deployment Status:**

- **Active deployment:** wrangler.toml points to `cloudflare_workerV2.js` (legacy monolithic version, 118KB).
- **Modular ready:** `/worker` directory contains fully refactored and tested 15-module version.
- **Transition path:** Once modular version is validated in staging, update wrangler.toml `main` field to `cloudflare_worker.js` (which re-exports `worker/index.js`).
- **Configuration:** wrangler.toml specifies cron trigger `* * * * *`, secrets management via `wrangler secret put`, and worker name "alert-notifier".
- **Testing:** worker_test/ includes Jest tests for pure functions; npm test runs all tests.
- **Package.json:** scripts for `npm test` and `npm run deploy`.

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

## AA. Shifts Module: Scheduling and Coordination

The Shifts module enables factory shift scheduling with AI-assisted supervisor assignment and handover coordination.

**Purpose:**
- Define and manage factory shift schedules (morning, afternoon, night).
- Track supervisor readiness and availability within shifts.
- Support AI Shift Commander for autonomous cross-factory assignment during active shifts.
- Generate handover summaries via Workers AI when shifts end.
- Provide voice-first shift enrollment and readiness commands.

**Data Model:**

ShiftModel (lib/models/shift_model.dart):
- id: unique shift identifier.
- name: display name (e.g., "Morning Shift 1").
- startMinutes, endMinutes: time representation as minutes from midnight (0-1439), supporting overnight wrap-around.
- kind: enum (morning, afternoon, night) derived from start hour (5-12, 12-20, 20-5).
- maxSupervisors: capacity limit for the shift.
- aiCommander: boolean enabling AI-driven cross-factory assignment override.
- aiModel: model choice for AI decisions (defaults to llama).
- aiConfidence: confidence floor (0-1) for accepting AI assignments.
- randomize: boolean to shuffle candidate ordering when assigning.
- supervisors: list of AssignedSupervisor objects with id, name, factory.
- lastHandoverSummary, lastHandoverAt: cached handover metadata.

Helper methods:
- containsTime(DateTime): checks if a given time falls within the shift window, handling overnight wrap.
- progress(): returns 0-1 fraction of shift elapsed.
- minutesRemaining(): time remaining in shift.
- formatMinutes(int): converts 0-1439 to "HH:MM" string.
- timeRangeLabel(): returns human-readable "HH:MM - HH:MM" with next-day label if overnight.
- ShiftKind detection based on start hour for consistent categorization.

**Services:**

ShiftService (lib/services/shift_service.dart):
- streamShifts(): returns live RTDB stream of shifts from /shifts path.
- fetchShiftsOnce(): one-time fetch for initialization (used by worker).
- createShift(ShiftModel): writes new shift to database.
- updateShift(ShiftModel): transactional update of existing shift.
- deleteShift(String shiftId): removes a shift (admin-only via rules).
- markCurrentUserReady(List<ShiftModel> shifts, bool ready): toggles current user's ready flag in the active shift's supervisors list.
- requestHandoverSummary(ShiftModel shift): POST to /shift-ai-action with handover action, returns structured summary.
- randomizePool(List<UserModel> supervisors, int count, List<ShiftModel> shifts): factory-balanced randomization. Buckets supervisors by factory first, then rounds through buckets to select evenly distributed candidates. Ensures no single factory dominates shift assignment.
- activeShift(List<ShiftModel> shifts, DateTime now): static method returning the currently active shift, or null.

Integration with ServiceLocator:
- ShiftService is registered in ServiceLocator.init() for app-wide access.

**UI Architecture:**

AdminShiftsTab (lib/screens/admin/shifts_tab.dart) is a three-tabbed interface:

1. _ScheduleView: Grid layout of shift cards (1-3 per row depending on width).
   - ShiftCard widget with hover animations, gradient background, supervisor avatars.
   - Tap opens shift editing dialog.
   - Empty state when no shifts.

2. _LiveView: Active shift monitoring with countdown timer and readiness tracking.
   - _LiveShiftPanel: shows active shift progress, "I'm ready" button, readiness grid.
   - _CountdownText: formatted hours/minutes to shift end.
   - _HandoverBanner: appears when shift ending in ≤30 min, with AI handover trigger.
   - _ReadinessGrid: live supervisor readiness chips with ready/not-ready states.
   - _UpcomingShiftsList: queue of shifts scheduled later today.
   - Empty state for no active shifts.

3. _TimelineView: 24-hour visual timeline of shift coverage.
   - _TimelineStrip and _TimelinePainter: custom painter rendering timeline blocks and now-marker.
   - Shift blocks color-coded by kind.
   - Shows supervisor count per shift.
   - Empty state for no shifts.

Shared UI components (lib/widgets/shifts/):

ShiftCard: hover-scale animation, displays:
- _ShiftKindChip: shift type badge with icon.
- _AiBadge: pulsing gradient badge when AI Commander is enabled.
- _LivePulseBadge: pulsing green "LIVE" indicator when shift is active.
- _SupervisorAvatars: stacked avatar circles with initials, +N overflow indicator.
- _AvatarChip: individual supervisor avatar with ready-state glow effect.

ShiftAnimatedBackground (lib/widgets/shifts/shift_backgrounds.dart):
- Three CustomPainter implementations (morning, afternoon, night) with smooth animations.
- _MorningPainter: animated sunrise with moving sun, rays, flying birds, drifting clouds.
- _AfternoonPainter: animated sunset with orange/pink gradients, factory silhouette with puffing smoke stacks.
- _NightPainter: animated night sky with twinkling stars, crescent moon with craters, 3-band aurora borealis ribbons.
- Dark mode support: reduces saturation and brightness on all painters.
- Helper methods: _drawCloud(), _drawGround(), _drawFactorySilhouette(), _drawAurora().

ShiftCreationDialog (lib/screens/admin/shift_creation_dialog.dart):
- Full-screen modal for creating or editing shifts.
- Fields: shift name, start/end time pickers (minute selection), max supervisors stepper.
- AI Shift Commander toggle with nested settings:
  - Model dropdown (llama selected by default).
  - Confidence slider (0-1 range).
- Randomize Shift Assignment toggle with re-randomize button.
- Supervisor search bar and multi-select checkboxes.
- Batch fetches supervisors on init with loading/error states.
- Validates form before save.

**Realtime Database Structure:**

/shifts path added to database.rules.json:
- Indexed on startMinutes and aiCommander for efficient queries.
- Admin-only read/write at root and {shiftId} level.
- Validators enforce:
  - name: string.
  - startMinutes, endMinutes: 0-1439 integers.
  - maxSupervisors: 1-50 integer.
  - aiCommander, randomize: boolean.
  - aiConfidence: 0-1 float.
  - supervisors.{supervisorId}.ready: boolean, writable by self or admin.
- Nested ai_decisions writes when assignment occurs.
- lastHandoverSummary and lastHandoverAt fields cached after handover generation.

**Cloudflare Worker Integration:**

cloudflare_worker.js includes shift-aware orchestration:

Shift helper functions:
- _shiftContainsTime(shift, DateTime): checks if time falls within shift window, handles overnight wrap.
- pickActiveShift(shiftsMap, DateTime): returns currently active shift, or null.

Enhanced core functions:
- loadCoreData(): now fetches /shifts.json in parallel with alerts/users, returns shiftsMap and activeShift in context.
- runAIAssignments(): extended with shift parameters:
  - Extracts aiCommander, confidence floor, randomize flag, maxSupervisors from active shift.
  - Overrides per-factory AI enable gate when AI Commander is active.
  - Allows cross-factory candidates from shift supervisor roster when AI Commander enabled.
  - Applies confidence floor check before assignment decision.
  - Randomizes candidate ordering when shift.randomize is true.
  - Prefixes assignment reason with shift name for traceability.

New functions:
- processShiftCollaborations(): runs within cron.
  - Auto-approves pending collaboration requests when all assistant candidates have accepted.
  - Skips PM approval step under AI Commander authority.
  - Sends notifications to requester on approval.

- processShiftEnding(): runs within 3 minutes of shift end time.
  - Triggers handover summary generation via generateShiftHandoverSummary().
  - Persists summary to shift node (lastHandoverSummary, lastHandoverAt).
  - Fans out shift_handover notifications to all supervisors in shift roster.

- generateShiftHandoverSummary(activeShift, alertsMap, usersMap): workers AI integration.
  - Aggregates shift performance metrics: resolved count, pending count, critical count.
  - Builds JSON context of recent alerts with status, type, supervisor.
  - Calls env.AI.run() with Llama 3.2 3B model and system prompt.
  - System prompt instructs: brief summary, key metrics, action items for next shift, factory-aware context.
  - Returns structured summary object with stats and text.

- handleShiftAiAction(): POST /shift-ai-action endpoint.
  - Supports four action types: evaluate, created, updated, handover.
  - evaluate/created/updated: re-runs AI assignments and collaboration approval.
  - handover: generates summary and persists to shift, notifies supervisors.

Cron and trigger updates:
- scheduled() handler calls processShiftCollaborations() and processShiftEnding() during every minute cron.
- default fetch trigger calls processShiftCollaborations().

**Voice Command Integration:**

VoiceCommandParser extended intents:
- joinShift: "assign me to the morning shift", "join evening shift", etc.
- shiftReady: "I am ready for shift", "mark me ready".
- shiftHandover: "start shift handover", "generate handover report".

VoiceCommandDispatcher handlers (lib/services/voice_command_dispatcher.dart):
- _handleShiftReady(): marks current user as ready in active shift via ShiftService.markCurrentUserReady().
- _handleJoinShift(String rawText): parses shift kind from raw text (morning, afternoon, evening, night).
  - Fetches shifts from ShiftService.
  - Adds current user to matching shift roster if not at capacity and not already joined.
  - Confirms action via TTS.
- _handleShiftHandover(): fetches active shift, calls ShiftService.requestHandoverSummary().
  - Returns generated summary text to user via TTS.
- _userFactory(String uid): helper to fetch user's factory affiliation from RTDB users/{uid}.

**Operational Sequences:**

Sequence 1: Shift creation
1. Admin opens AdminShiftsTab, taps create button.
2. ShiftCreationDialog opens with form.
3. Admin configures name, time, AI settings, selects supervisors.
4. Dialog validates and calls ShiftService.createShift().
5. RTDB write persists shift under /shifts/{newId}.
6. UI stream updates and card appears in _ScheduleView.

Sequence 2: AI Commander assignment during active shift
1. Worker runs scheduled cron.
2. loadCoreData() fetches shifts and identifies activeShift.
3. Alert requiring assignment triggers runAIAssignments().
4. AI Commander flag is true, so per-factory enable check skipped.
5. Candidates filtered from shift.supervisors (cross-factory allowed).
6. Confidence floor and randomize applied.
7. Best candidate assigned transactionally with aiHistory write.
8. shift_ai_assignment notification sent to selected supervisor.

Sequence 3: Shift handover
1. Shift nears end time (≤30 min remaining).
2. _HandoverBanner appears in _LiveView with trigger button.
3. User taps "Generate Handover Report" or voice says "start shift handover".
4. VoiceCommandDispatcher calls ShiftService.requestHandoverSummary().
5. POST to /shift-ai-action with handover action.
6. Worker generates summary via generateShiftHandoverSummary() with Workers AI.
7. Summary persisted to shift node (lastHandoverSummary, lastHandoverAt).
8. shift_handover notifications sent to all supervisors.
9. Summary displayed in UI or spoken to user.

Sequence 4: Supervisor shift enrollment via voice
1. Supervisor says "assign me to the morning shift".
2. VoiceCommandDispatcher._handleJoinShift() parses intent.
3. Fetches shifts and finds morning shift not at capacity.
4. Adds supervisor to shift.supervisors roster.
5. Transactional update persists to RTDB.
6. TTS confirms "You have been added to the morning shift."

**Integration Points:**

- AlertProvider: unchanged, shifts are orthogonal to alert lifecycle.
- NotificationService: receives shift_handover and shift_ai_assignment payloads.
- FcmService: routes shift-related notifications to UI or voice.
- AIService: remains separate, shift AI Commander is a worker-side override.
- Voice system: VoiceCommandParser and VoiceCommandDispatcher extended with shift intents.

**Design Patterns Applied:**

1. Factory-balanced randomization: ensures fair cross-factory assignment under AI Commander.
2. Minutes-from-midnight time representation: allows simple numeric comparisons and overnight wrap-around.
3. Transactional shift updates: supervisor roster adds via RTDB transaction for consistency.
4. Theme-aware animations: CustomPaint uses isDark flag to reduce saturation in dark mode.
5. Offline resilience: ShiftService fetches once at startup, shift state streamed via RTDB cache.
6. Workers AI binding: Llama 3.2 3B model for concise, action-oriented handover summaries.

---

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

## AB. Shift Reporting and PDF Export

The Shifts module includes comprehensive reporting capabilities that capture all activity during a shift window, including AI Shift Commander decisions, supervisor actions, and performance metrics.

**ShiftPdfService** (lib/services/shift_pdf_service.dart):
- Exports a beautiful, audit-ready PDF report for any shift.
- Loads all alerts created/claimed/resolved/escalated within the shift time window.
- Tracks supervisor readiness, AI commander actions, and handover summaries.
- Generates metrics: total alerts, created, claimed, resolved, escalated counts.
- Includes factory and supervisor performance breakdowns (bar charts).
- Timeline view with chronological action log (created, claimed, resolved, ai_assigned, escalated, handover).
- AI actions section highlighting all assignments with confidence scores.
- Handover card displays AI-generated summary if available.
- Theme-aligned colors and responsive layout for landscape A4 PDF.
- Supports web download and mobile share-sheet export.

ShiftAction model captures single events:
- at: timestamp when action occurred.
- kind: event type (created, claimed, resolved, ai_assigned, escalated, handover).
- alertLabel, alertType, factory: context.
- detail: human-readable description.
- actor: supervisor or system responsible.
- aiConfidence: optional ML confidence if AI action.

**Shift Report UI Integration**:

_ReportButton widget (in shifts_tab.dart):
- Appears in _LiveView below readiness section when shift is active.
- "Generate Shift Report" button with file-download icon and orange accent.
- Shows progress spinner during PDF generation.
- Launches ShiftPdfService.exportAndShare() for the current day.
- Error snackbar on failure.

**Rejection Dialog for Double Assignment**:

_DoubleAssignmentDialog (in shift_creation_dialog.dart):
- Blocks supervisor assignment to two simultaneous shifts.
- Checks _conflictingShiftFor() during supervisor selection.
- Beautiful modal with:
  - Red block icon and "Double Assignment Blocked" header.
  - Supervisor name and conflict details.
  - Existing shift card showing kind icon, name, and time range.
  - Guidance text on how to resolve (remove from conflicting shift first).
- Non-blocking interaction; supervisor can try another assignment after closing.

**Integration with AlertProvider**:
- _loadActions() queries all alerts in RTDB under /alerts path.
- Filters by shift time window using _windowFor() which handles overnight wrap.
- Detects actions from alert fields: timestamp, takenAtTimestamp, resolvedAt, escalatedAt, aiAssignedAt.
- Includes shift.lastHandoverSummary if set (written by worker handover endpoint).
- Sorts all actions chronologically for timeline view.

**Design Patterns**:
- Window helper: _windowFor() computes [start, end) datetimes, accounting for overnight shifts.
- Safe text: _safe() escapes special characters for PDF rendering.
- Color mapping: _kindColor() returns PdfColor by action type; matches UI theme.
- Date formatting: _fmtDateTime(), _fmtTime(), _fmtDateFile() for readability and file safety.
- Slug generation: _slug() sanitizes shift names for filenames.

---

## AC. Phase 6 Continuation: Modular AI Architecture & Build Stability (May 2026)

Completed extraction of AI assignment subsystem into pure, testable modules with comprehensive test coverage and resolved all Flutter SDK version pinning conflicts for stable CI/CD deployments.

**Modules Extracted:**

1. **AIScoringEngine** (lib/services/ai/ai_scoring_engine.dart)
   - Pure function scoring logic: 7 scoring factors, 4 disqualifier checks.
   - No Firebase, singletons, or time mutation — fully testable with explicit `now` parameter.
   - Scoring factors: same factory (+30/-25), type experience, resolution speed, workstation/conveyor familiarity, load balancing, critical history, feedback adjustment.
   - Clamps score to 0-1000 range.
   - Test coverage: 16 test cases covering all paths (test/services/ai_scoring_engine_test.dart).

2. **AIStateManager** (lib/services/ai/ai_state_manager.dart)
   - In-memory bookkeeping for transient state: in-flight set, skipped alerts map, supervisor cooldown map, processed history set.
   - No Firebase — fully unit-testable with optional `now` parameter for deterministic tests.
   - Methods: isInFlight/markInFlight/clearInFlight, isSkipped/markSkipped/clearExpiredSkipped, cooldownStart/recordCooldown, isHistoryProcessed/markHistoryProcessed.
   - clearAll() for logout/test reset.

3. **AIDecisionRepository** (lib/services/ai/ai_decision_repository.dart)
   - Firebase persistence abstraction: owns ai_feedback/events and ai_feedback/summary/{supervisorId} writes.
   - FeedbackSummary DTO: calculates rankAdjustment (±20 clamp) from accepted/rejected/aborted/resolved counts.
   - Permission-denied handling: flips isAvailable flag on rules denial, short-circuits subsequent calls.
   - Constructor accepts optional FirebaseDatabase for testing.

4. **ConnectivityService** (lib/services/connectivity_service.dart)
   - App-wide connectivity signal via ChangeNotifier (Provider-integrated).
   - Exposes isOnline/isOffline getters, broadcast stream, init() method.
   - Properly disposes subscription and StreamController in dispose().
   - No singleton — injected via Provider for clean testability.

**Dependency & Build Fixes:**

- **intl version pinning:** Removed explicit intl dependency from pubspec.yaml. Intl is now provided transitively by flutter_localizations. This eliminates version conflicts across Flutter SDK versions and works in both local and CI environments.
- **pdf/vector_math conflict:** Downgraded pdf to ^3.11.3 (compatible with Flutter SDK's pinned vector_math 2.1.4).
- **Flutter API compatibility:** Fixed deprecated Switch.adaptive `activeThumbColor` → `activeColor`, DropdownButtonFormField `initialValue` → `value`.
- **Unused imports cleanup:** Removed unused imports from lib/widgets/admin/header.dart.

**StreamSubscription Disposal Audit:**

- ConnectivityService: ✅ Disposes subscription and StreamController.
- AIAssignmentService: ✅ Disposes all 4 subscriptions.
- BackgroundSyncService: ✅ Disposes subscription and timer.
- AlertStreamService: ✅ Added dispose() method.
- DashboardScreen._HeaderState: ✅ Disposes notifications and PM subscriptions.
- FcmService/PushNotificationService: FirebaseMessaging listeners are app-level.

**Painter RepaintBoundary Wrapping:**

- shift_backgrounds.dart: CustomPaint wrapped in RepaintBoundary.
- ai_morning_briefing_hero.dart: CustomPaint wrapped in RepaintBoundary.

**Test Infrastructure:**

- Created comprehensive AIScoringEngine test suite: 16 test cases covering disqualifiers, scoring factors, edge cases.
- All tests passing: `flutter test test/services/ai_scoring_engine_test.dart`.

**Build & Deployment Status:**

- ✅ `flutter pub get` succeeds (all Flutter SDK versions).
- ✅ `flutter build web --release` succeeds.
- ✅ All tests passing.
- ✅ Ready for CI/GitHub Actions deployment.

---

## AD. Phase 3: Predictive Model Validation & Reinforcement Learning Integration (May 2026)

Implemented comprehensive predictive model validation system that measures forecast accuracy by cross-referencing historical predictions against actual alerts, plus reinforcement learning adjustment layer for dynamic score refinement.

**Architecture Overview:**

The system operates in three layers:

1. **History Snapshot Layer** (cloudflare_worker.js: handlePredictions)
   - When predictions are computed, a timestamped immutable copy is written to `ai_predictions/history/{key}.json` before the latest write.
   - Key format: `_historyKey(iso)` escapes Firebase-unsafe characters by replacing `:` and `.` with `-` (e.g., `2026-05-07T14:00:00.000Z` → `2026-05-07T14-00-00-000Z`).
   - Snapshot includes: generatedAt, predictions[], validated (false initially).
   - Fire-and-forget write ensures history is immutable regardless of latest-write latency.

2. **Validation Engine** (cloudflare_worker.js: validatePredictions)
   - Runs as part of scheduled() cron handler (after processShiftEnding).
   - Processes snapshots aged ≥MIN_VALIDATION_AGE_HOURS (24h), capped at MAX_VALIDATION_PER_RUN (10 per cron).
   - Skips already-validated entries (validated: true).
   - For each eligible snapshot:
     - Fetches all alerts and indexes by timestamp for O(1) lookup.
     - For each prediction in snapshot, matches alerts if:
       - Alert timestamp within prediction.etaHours window (after generatedAt).
       - Same factory (case-insensitive), convoyeur, poste, type.
     - Computes accuracy = truePositives / totalPredicted (0.0–1.0).
     - Writes validation object to snapshot with totalPredicted, truePositives, accuracy (4 decimals), validatedAt.
   - Aggregates macro-average across all validated snapshots.
   - Writes performance aggregate to `ai_predictions/performance/latest.json` (totalSnapshots, averageAccuracy, lastValidatedUtc).
   - Returns processed count for HTTP response and logging.

3. **Reinforcement Adjustment Layer** (cloudflare_worker.js: scoreSupervisor)
   - Reads reinforcement adjustments from `ai_feedback/adjustments.json` (keyed by supervisorId).
   - Applies ±15% clamped adjustment to raw score before final return.
   - Calculation: maxAdj = score * 0.15; clamped = clamp(adjustment, -maxAdj, +maxAdj).
   - Only applies adjustment if |clamped| ≥ 0.01 (avoids noise).
   - Appends reason string if adjustment was applied (e.g., "Reinforcement adjustment (+5)").
   - Maintains 100% backward compatibility: missing adjustments default to 0 (no change).

**Flutter Integration:**

1. **PredictiveAccuracy Model** (lib/services/predictive_intel_stream_service.dart)
   - DTO: totalSnapshots (int), averageAccuracy (0.0–1.0), lastValidatedUtc (string?).
   - Factory method fromMap() deserializes Firebase data safely.

2. **Stream Service** (lib/services/predictive_intel_stream_service.dart)
   - Added _accuracySub, _accuracyController, _lastAccuracy fields.
   - _ensureAccuracySubscription() subscribes to `ai_predictions/performance/latest`.
   - accuracyStream() getter returns broadcast stream.
   - lastAccuracy getter for snapshot access (used by widgets).
   - dispose() cancels subscription and closes controller.

3. **Facade & Export** (lib/services/predictive_intel_service.dart)
   - Re-exports PredictiveAccuracy for public API.
   - accuracyStream() facade method delegates to streams service.

4. **UI Integration** (lib/widgets/overview/overview_predictive_failure_card.dart)
   - PredictiveFailureCard accepts optional accuracy parameter.
   - Renders accuracy badge before LIVE badge when accuracy != null && totalSnapshots > 0.
   - Badge displays: "Accuracy: X%" with purple background and tooltip.
   - Tooltip text: "Based on the last N validated predictions."

5. **Screen Binding** (lib/screens/overview_tab.dart)
   - _bindPredictiveStreams() subscribes to accuracy stream and updates _accuracy field.
   - dispose() cancels _accSub.
   - Passes accuracy to PredictiveFailureCard widget.

**Firebase Persistence:**

- `/ai_predictions/history/{key}.json`: immutable prediction snapshots with validation metadata.
- `/ai_predictions/performance/latest.json`: rolling macro-average accuracy and snapshot count.
- `/ai_feedback/adjustments.json`: supervisor-keyed reinforcement adjustments (±15% clamp).
- database.rules.json: read-protected (admin access), no client writes.

**Test Coverage:**

Worker test suite (worker_test/validation.test.js) includes 6 new test cases:
1. Matching alerts yield TP > 0 and accuracy > 0.
2. No matching alerts yield TP = 0 and accuracy = 0.
3. Already-validated snapshots are skipped.
4. Snapshots younger than 24h are not processed.
5. /validate-predictions HTTP endpoint returns 200 + processed count.
6. _historyKey escapes colons and dots in ISO timestamps.

All 117 tests passing (111 prior + 6 new).

**HTTP Endpoints:**

- `POST /validate-predictions`: Triggers validation run immediately. Returns `{ ok: true, processed: N }`.
- Called via WorkerTriggerQueue for explicit runs; also embedded in scheduled() cron.

**Design Decisions:**

1. **Idempotent validation:** validated flag prevents reprocessing same snapshot.
2. **Immutable history:** fire-and-forget snapshot write before latest write ensures no data loss on worker crash.
3. **Macro-average aggregation:** fairness across all snapshots regardless of individual sizes.
4. **Lazy accuracy reads:** accuracy badge only renders when data available (no placeholder flickering).
5. **Symmetric clamping:** ±15% adjustment ensures bidirectional feedback (positive reinforcement, negative correction).
6. **Path safety:** ISO timestamp escaping handled automatically by _historyKey; no manual escaping in Firebase rules.

**Operational Sequences:**

Sequence 1: Prediction snapshot and validation
1. Alert stream triggers predictive computation in worker.
2. handlePredictions() writes timestamped snapshot to ai_predictions/history/{key}.json with validated: false.
3. handlePredictions() writes latest to ai_predictions/latest.json.
4. Next cron run: validatePredictions() finds eligible snapshot (≥24h old).
5. Matches predictions against alerts within etaHours window.
6. Writes validation object with accuracy.
7. Aggregates macro-average to performance/latest.json.
8. Flutter accuracy stream updates UI badge.

Sequence 2: Reinforcement adjustment application
1. Worker loads adjustments from ai_feedback/adjustments.json (keyed by supervisorId).
2. During AI assignment scoring, scoreSupervisor() applies clamped adjustment.
3. Final score = base score + adjustment (if |adjustment| ≥ 0.01).
4. Reason appended to decision log for traceability.
5. No adjustment present → defaults to 0 (no change from prior behavior).

---

## AE. Briefing Personalization and Predictive Insights (May 2026)

Implemented comprehensive personalization of morning briefings with three integrated features: factory scope selection, validated predictive accuracy injection, and supervisor reinforcement ranking.

**Factory-Scoped Briefing:**

The briefing system now supports per-factory data aggregation alongside global briefings.

Worker side (cloudflare_worker.js):
- `_briefingFactorySlug(factory)`: Sanitizes factory name to Firebase-safe path segment by converting to lowercase, replacing spaces with underscores, and removing special characters (e.g., "Quality Line 1" → "quality_line_1").
- `handleBriefing()`: Accepts optional `?factory` query parameter. If present, worker aggregates statistics scoped to only that factory's alerts.
  - Fetches validated accuracy from `ai_predictions/performance/latest.json`.
  - Fetches latest predictions from `ai_predictions/latest.json` and filters predictions by factory.
  - Selects top prediction by confidence score (highest first, factory-scoped).
  - Calls `_topSupervisorWeek(alertsMap, usersMap, factory)` to rank supervisors.
  - Writes briefing to factory-scoped Firebase path: `ai_briefing/factory/{slug}/latest.json`.
- Null or "all" factory parameter → writes to global path: `ai_briefing/latest.json`.

**Predictive Accuracy Injection:**

Each briefing includes validated model accuracy metrics and top predicted failure details.

Worker integration (cloudflare_worker.js):
- `_topSupervisorWeek(alertsMap, usersMap, factoryFilter)`: Ranks supervisors by resolved alert count in past 7 days.
  - Filters alerts by factory if factoryFilter provided.
  - Computes resolved count per supervisor.
  - Extracts topType: most common alert type resolved by that supervisor.
  - Calculates avgMin: average resolution time in minutes.
  - Returns: { name: firstName + lastName (or UID fallback), count: totalResolved, topType: typeString, avgMin: minutes }.
- Injected into Llama prompt as three distinct context lines:
  - Factory line (if factory-scoped): "Factory scope: {factory name}."
  - Accuracy line: "Validated model accuracy: {accuracyPct}% based on {totalSnapshots} predictions."
  - Prediction line: "Alert prediction: expecting {topType} issue on {topConvoyeur} Line {topPoste}, confidence {confidenceScore}%."
  - Supervisor line: "Top performer: {supervisorName} resolved {count} alerts last week, fastest for {topType} issues."

Flutter side (lib/services/predictive_models.dart):
- MorningBriefing model extended with new fields:
  - `factoryScope`: null for global, string for factory name.
  - `accuracyPct`: 0-100 integer, validated model accuracy.
  - `predictiveType`, `predictiveConvoyeur`, `predictiveConfidence`: Top predicted failure details.
  - `topSupervisorName`, `topSupervisorCount`, `topSupervisorType`: Supervisor ranking.
- fromMap() deserializes all fields, with safe defaults for missing data (null checks).

**Per-Factory Caching and Streaming:**

HTTP and stream services refactored for per-factory state management.

PredictiveRepository (lib/services/predictive_repository.dart):
- `_briefingCache`, `_briefingCachedAt`: Changed from single values to `Map<String?, ...>` for per-factory caching.
- `_briefingPath(String? factory)`: Returns correct Firebase path (null/'all' → 'ai_briefing/latest', string → 'ai_briefing/factory/{slug}/latest').
- `getBriefing({bool force, String? factory})`: Caches per factory key. URL-encodes factory query parameter for HTTP transport.
- `briefingStream({String? factory})`: Reads from factory-specific path via _briefingPath.

PredictiveIntelStreamService (lib/services/predictive_intel_stream_service.dart):
- Refactored single briefing subscription to multi-subscription map:
  - `_briefingSubs`: Map<String?, StreamSubscription> for active subscriptions.
  - `_briefingControllers`: Map<String?, StreamController> for broadcast streams.
  - `_lastBriefings`: Map<String?, MorningBriefing?> for snapshot access.
- `_ensureBriefingSubscription(String? key)`: Lazily creates subscription for each unique factory key on first call. Idempotent: subsequent calls return existing subscription.
- `dispose()`: Cancels all subscriptions and closes all controllers, ensuring no resource leaks on logout or screen disposal.
- `briefingStream({String? factory})`: Accepts factory parameter, delegates to per-factory subscription map.

PredictiveIntelService (lib/services/predictive_intel_service.dart):
- Thin facade that propagates factory parameter through to repository and stream service.
- `briefingStream({String? factory})` and `fetchBriefing({bool force, String? factory})` pass factory through unchanged.

**UI Integration:**

Overview tab (lib/screens/overview_tab.dart):
- `_briefingFactory` getter: Returns null if selectedUsine == 'all' (global briefing), else returns selectedUsine (factory-scoped).
- `_bindPredictiveStreams()`: Passes factory to briefingStream() call.
- `_warmPredictiveCaches()`: Passes factory to fetchBriefing() on app startup.
- `_refreshBriefing()`: Passes factory to fetchBriefing(force: true) on user refresh.
- `_rebindBriefingStream()`: New method that cancels old subscription, clears state, and resubscribes with new factory when user switches factory selection.
- `didUpdateWidget()`: Calls _rebindBriefingStream() when selectedUsine changes.

AI Morning Briefing Hero widget (lib/widgets/overview/ai_morning_briefing_hero.dart):
- `_briefChip()` method extended: Accepts optional `Color? color` parameter for custom tinting.
  - Uses tinted colors: 0.15 alpha for background, 0.28 for border.
- New chips displayed in Wrap (order: factory, accuracy, prediction, supervisor):
  - **Factory scope badge** (green): Shows only when factoryScope != null. Displays factory name.
  - **Accuracy chip** (purple): Shows "Accuracy: X%" when accuracyPct available. Includes tooltip: "Based on N validated predictions."
  - **Predictive insight chip** (amber): Shows "{type} on {convoyeur} Line {poste}" with confidence score. Tooltip: "Expected alert type and location."
  - **Top supervisor chip** (blue): Shows "{name} — {count} resolved" highlighting top performer's achievement. Tooltip: "{name} specialized in {topType}."
- Adjusted summaryMaxLines: Increased compact mode from 2 to 5 lines to accommodate full briefing paragraph.

**Firebase Paths:**

- `/ai_briefing/latest.json`: Global briefing (no factory filter).
- `/ai_briefing/factory/{slug}/latest.json`: Factory-scoped briefing where {slug} = _briefingFactorySlug(factoryName).
- `/ai_predictions/latest.json`: Latest predictions (source for top-prediction selection).
- `/ai_predictions/performance/latest.json`: Validated accuracy metrics (totalSnapshots, averageAccuracy, lastValidatedUtc).

**Data Flow:**

Sequence: Morning briefing with factory personalization
1. PM or supervisor opens Overview tab and selects a factory (or views global if "all").
2. AlertProvider notifies OverviewTab of factory selection change via didUpdateWidget.
3. OverviewTab._rebindBriefingStream() cancels old subscription and resubscribes with new factory parameter.
4. PredictiveRepository.getBriefing(factory: "production_line_2") makes HTTP request: GET /briefing?factory=production_line_2.
5. Worker handleBriefing() receives factory param, scopes alert aggregation:
   - Computes stats only for alerts where usine == "Production Line 2".
   - Fetches validated accuracy from ai_predictions/performance/latest.json.
   - Fetches predictions, filters by factory, selects top by confidence.
   - Calls _topSupervisorWeek with factoryFilter="Production Line 2", returns top supervisor from that factory's resolved alerts.
   - Injects all three contexts (factory line, accuracy line, prediction line, supervisor line) into Llama prompt.
   - Generates briefing with Llama and writes to ai_briefing/factory/production_line_2/latest.json.
6. PredictiveIntelStreamService._ensureBriefingSubscription("production_line_2") sets up stream from that path.
7. MorningBriefing fromMap() deserializes: factoryScope, accuracyPct, predictiveType/Convoyeur/Confidence, topSupervisorName/Count/Type.
8. AiMorningBriefingHero renders:
   - Factory scope badge (green, "Production Line 2").
   - Accuracy chip (purple, "Accuracy: 72%").
   - Predictive insight chip (amber, "Quality on Conveyor A Line 3").
   - Top supervisor chip (blue, "Ahmed — 8 resolved").
   - Full briefing paragraph below.

**Design Decisions:**

1. **Per-factory subscription maps:** Avoids unnecessary re-subscriptions when factory changes; lazy initialization on first access.
2. **Factory slug escaping:** Deterministic transformation ensures path consistency across worker and Flutter services.
3. **Three-line context injection:** Structured prompt context for Llama allows natural weaving of insights without prompt engineering fragility.
4. **Accuracy from validated snapshots:** Uses aggregated macro-average from validation engine, not raw worker-computed confidence.
5. **Top supervisor per factory:** Rankings isolated to factory scope ensures relevance (best performer in that plant, not globally).
6. **Name resolution fallback:** Supervisor name = firstName + lastName with UID fallback, matching scoreSupervisor pattern for consistency.
7. **Chip color coding:** Green (scope/availability), purple (model quality), amber (predictive alert), blue (team strength) reinforce semantic meaning.

---

## AF. Supervisors Workspace Redesign (May 2026)

Implemented a structural redesign of the Supervisors area to unify assignment operations and move individual analytics into a contextual overlay.

**Navigation and Subtabs:**

- Supervisors subtab set reduced to 2 tabs:
  - `Management`
  - `Collaborations`
- Legacy standalone `Assignments` subtab removed from navigation.

**Management Tab Behavior:**

- Main right-hand workspace is now assignment-first.
- Assignment board is rendered in the Management flow as the primary interaction surface.
- Supervisors can be dragged from roster cards directly into plant/factory lanes.
- Unassigned lane remains available as a drop target for removing plant assignment.

**Performance Access Pattern:**

- Supervisor performance is no longer permanently embedded in the detail column.
- Clicking a supervisor opens a floating performance popup panel contextual to that supervisor.
- The popup includes:
  - performance trend graph
  - metric cards
  - type breakdown donut and related cards
  - validated alert trail cards
- Popup supports:
  - drag to reposition
  - resize via corner handle
  - quick expand/collapse sizing toggle
  - close action

**Interaction Notes:**

- Roster cards use direct drag behavior for assignment workflows.
- Selected supervisor state is reused by both assignment chips and overlay context.
- Theme tokens from `AppTheme` remain the single source of visual styling for light/dark consistency.

## Quick File-to-Responsibility Index

**Flutter App Core:**
- lib/main.dart: bootstrap, providers, role routing.
- lib/providers/alert_provider.dart: alert state and action entry points.
- lib/screens/supervisors_tab.dart: supervisors Management/Collaborations UI, assignment board drag-and-drop, and draggable/resizable performance overlay.

**Alert and Stream Services:**
- lib/services/alert_service.dart: CRUD and transactional alert operations.
- lib/services/alert_stream_service.dart: merged streaming and new-alert detection.
- lib/services/alert_actions_service.dart: alert action helpers.
- lib/services/alert_pdf_service.dart: alert detail PDF export.

**Voice and Communication:**
- lib/services/voice_service_io.dart: capture, TTS, lock-flow integration.
- lib/services/voice_command_parser.dart: intent and number parsing logic.
- lib/services/voice_command_dispatcher.dart: command execution and spoken feedback.
- lib/services/voice_auth_service_io.dart: enrollment and speaker verification.
- lib/services/voice_lock_service.dart: lock-screen voice flow.
- lib/services/fcm_service.dart: FCM + local notification + lock-screen action handling.
- lib/services/notification_service.dart: notification content and delivery.

**AI and Predictive:**
- lib/services/ai_assignment_service.dart: assignment policy and logs (orchestrator).
- lib/services/ai/ai_scoring_engine.dart: pure scoring logic (7 factors, 4 disqualifiers).
- lib/services/ai/ai_state_manager.dart: transient state (cooldowns, skipped alerts).
- lib/services/ai/ai_decision_repository.dart: Firebase persistence and feedback.
- lib/services/ai/score_adjuster.dart: reinforcement adjustment application.
- lib/services/ai_service.dart: AI suggestion endpoint client.
- lib/services/predictive_repository.dart: worker predictive endpoints client.
- lib/services/predictive_models.dart: data models (MorningBriefing, PredictiveModel, etc.).
- lib/services/predictive_intel_service.dart: predictive facade.
- lib/services/predictive_intel_stream_service.dart: RTDB stream subscriptions (factory-scoped).
- lib/services/score_reinforcement_service.dart: reinforcement learning integration.

**System and Offline:**
- lib/services/connectivity_service.dart: app-wide connectivity signal.
- lib/services/offline_database_service.dart: RTDB persistence config.
- lib/services/offline_account_cache.dart: offline role/factory caching.
- lib/services/worker_trigger_queue.dart: resilient worker trigger queue.
- lib/services/background_sync_service.dart: reconnection-triggered sync.

**Organization and Coordination:**
- lib/services/hierarchy_service.dart: topology, assets, location validation.
- lib/services/work_instruction_service.dart: location-aware guidance.
- lib/services/collaboration_service.dart: multi-supervisor coordination and PM approval.

**Shift Management:**
- lib/services/shift_service.dart: shift CRUD and AI action triggers.
- lib/services/shift_pdf_service.dart: shift report PDF generation and export.
- lib/screens/admin/shifts_tab.dart: shift scheduling UI (schedule, live, timeline tabs).
- lib/screens/admin/shift_creation_dialog.dart: shift configuration with conflict detection.
- lib/widgets/shifts/: shift UI components (cards, backgrounds, logs panel).

**Core Infrastructure:**
- lib/services/service_locator.dart: dependency injection container.
- lib/services/auth_service.dart: Firebase authentication.
- lib/services/app_logger.dart: logging.
- lib/services/config_service.dart: app configuration.
- lib/services/push_notification_service.dart: platform notification wrapper.
- lib/services/app_lifecycle_observer.dart: app foreground/background transitions.

**Worker (Cloudflare):**
- cloudflare_worker.js: re-export shim to worker/index.js.
- worker/index.js: orchestrator, scheduled and fetch handlers.
- worker/auth.js: Firebase token generation.
- worker/alerts.js: alert state processing.
- worker/ai_suggest.js: AI suggestion endpoint.
- worker/auto_fix.js: automatic remediation.
- worker/briefing.js: briefing generation (factory-scoped).
- worker/config.js: CORS and config.
- worker/escalation.js: escalation policy checks.
- worker/fcm.js: FCM fan-out.
- worker/health.js: cron health monitoring.
- worker/load_core.js: parallel core data loading.
- worker/predictive.js: predictive model and validation.
- worker/scoring.js: supervisor scoring.
- worker/shift_commander.js: shift management and handovers.
- worker/suggest_assignee.js: assignee recommendations.
- worker/utils.js: shared utilities.
- worker/wrangler.toml: worker configuration.

**Backend:**
- functions/index.js: Firebase Functions (retry, assignment fallback).
- codebasedelta/: secondary Firebase Functions codebase.

**Database and Rules:**
- database.rules.json: Realtime Database authorization, validation, indexes.
- firebase.json: Firebase project configuration (hosting, functions).
- wrangler.toml: Cloudflare Worker deployment config (points to `cloudflare_workerV2.js`, legacy).

**Testing:**
- test/: Flutter tests (parsers, models, utilities, widgets).
- worker_test/: Jest tests for worker pure functions.
- TESTING.md: testing strategy and CI expectations.

This is the current architecture baseline for AlertSys (May 2026).

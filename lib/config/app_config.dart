import 'package:flutter/foundation.dart' show visibleForTesting;

/// Single source of truth for cross-cutting configuration constants.
///
/// Values are overridable at build time via `--dart-define` (see CI). Keeping
/// them here avoids string drift across services and makes the future DI
/// migration (Phase 6) trivial: services read from [AppConfig] instead of
/// holding private `const` URLs.
class AppConfig {
  const AppConfig._();

  /// Legacy Cloudflare Worker base URL. Kept as a fallback for older build scripts.
  static const String legacyWorkerBaseUrl = String.fromEnvironment(
    'ALERTSYS_WORKER_URL',
    defaultValue: 'https://alert-notifier.aziz-nagati01.workers.dev',
  );

  /// AI and security Worker base URL.
  static const String aiWorkerBase = String.fromEnvironment(
    'ALERTSYS_AI_WORKER_URL',
    defaultValue: legacyWorkerBaseUrl,
  );

  /// Notifications Worker base URL.
  static const String notifyWorkerBase = String.fromEnvironment(
    'ALERTSYS_NOTIFY_WORKER_URL',
    defaultValue: 'https://alertsys.aziz-nagati01.workers.dev',
  );

  /// GitHub proxy Worker base URL (Guardian console: live Actions + PRs +
  /// repository_dispatch). The token stays server-side on this worker; the app
  /// authenticates with the signed-in SuperAdmin's Firebase ID token.
  static const String githubWorkerBase = String.fromEnvironment(
    'ALERTSYS_GITHUB_WORKER_URL',
    defaultValue: 'https://alertsys-guardian-proxy.pages.dev/github-proxy',
  );

  /// Industrial ingestion + connector worker base URL. Hosts the SCADA / PLC /
  /// historian connector engine: per-connector edge push, cloud-pull polling,
  /// and the "Verify link test" endpoint used by SuperAdmin → Infrastructure.
  static const String ingestWorkerBase = String.fromEnvironment(
    'ALERTSYS_INGEST_WORKER_URL',
    defaultValue: 'https://alertsys-ingest.aziz-nagati01.workers.dev',
  );

  /// Kubix Copilot chat page (served by the sias-store worker). Per-tenant
  /// builds override this with a URL that carries the instance's tenant
  /// context (e.g. `.../copilot?tenant=NSW%237K2F&company=...`); the SuperAdmin
  /// console's Kubix card appends `lang=fr` when the console runs in French.
  static const String copilotUrl = String.fromEnvironment(
    'ALERTSYS_COPILOT_URL',
    defaultValue: 'https://sias-store.aziz-nagati01.workers.dev/copilot',
  );

  /// Deprecated alias for old call sites. New code should choose aiWorkerBase
  /// or notifyWorkerBase explicitly.
  static const String workerBaseUrl = aiWorkerBase;

  /// Low-privilege key for the two client-facing worker routes that still
  /// need a static credential: the ingest worker's `/verify` + `/control`.
  ///
  /// This is deliberately NOT `WORKER_SHARED_SECRET`. That secret is the
  /// worker-to-worker credential and grants full access to the AI and notify
  /// workers, so it must never be compiled into a build — anything shipped to
  /// a browser or an APK is public. The AI and notify workers are reached with
  /// the signed-in user's Firebase ID token instead (see WorkerAuth), and the
  /// GitHub proxy requires a SuperAdmin ID token and ignores static secrets.
  static const String clientWorkerKey = String.fromEnvironment(
    'ALERTSYS_CLIENT_WORKER_KEY',
    defaultValue: '',
  );

  // ── Runtime overrides (per-tenant web delivery) ─────────────────────────────
  // On web, the shared `sias-app` worker injects `window.__SIAS_CONFIG__` with
  // this tenant's worker URLs (see runtime_firebase_config.dart). main.dart
  // applies them here at startup so ONE web build serves every customer; the
  // compile-time const defaults above still drive Android/dart-define builds and
  // remain the fallback whenever no runtime override is present.
  static String? _rtAiWorker;
  static String? _rtNotifyWorker;
  static String? _rtIngestWorker;
  static String? _rtCopilotUrl;

  /// Applies runtime worker-URL overrides (no-op for null/empty values, so a
  /// partial injected config never blanks out a good compile-time default).
  static void applyRuntimeWorkerOverrides({
    String? aiWorkerBase,
    String? notifyWorkerBase,
    String? ingestWorkerBase,
    String? copilotUrl,
  }) {
    if (aiWorkerBase != null && aiWorkerBase.isNotEmpty) _rtAiWorker = aiWorkerBase;
    if (notifyWorkerBase != null && notifyWorkerBase.isNotEmpty) {
      _rtNotifyWorker = notifyWorkerBase;
    }
    if (ingestWorkerBase != null && ingestWorkerBase.isNotEmpty) {
      _rtIngestWorker = ingestWorkerBase;
    }
    if (copilotUrl != null && copilotUrl.isNotEmpty) _rtCopilotUrl = copilotUrl;
  }

  /// Runtime-override-aware base URLs. Endpoints below build off these so a
  /// per-tenant web build talks to that tenant's own workers.
  static String get resolvedAiWorkerBase => _rtAiWorker ?? aiWorkerBase;
  static String get resolvedNotifyWorkerBase => _rtNotifyWorker ?? notifyWorkerBase;
  static String get resolvedIngestWorkerBase => _rtIngestWorker ?? ingestWorkerBase;
  static String get resolvedCopilotUrl => _rtCopilotUrl ?? copilotUrl;

  @visibleForTesting
  static void debugResetRuntimeOverrides() {
    _rtAiWorker = null;
    _rtNotifyWorker = null;
    _rtIngestWorker = null;
    _rtCopilotUrl = null;
  }

  // ── Worker endpoints ────────────────────────────────────────────────────
  static String get workerRoot => resolvedAiWorkerBase;
  static String get configEndpoint => '$resolvedAiWorkerBase/config';
  static String get aiSuggestEndpoint => '$resolvedAiWorkerBase/ai-suggest';
  static String get shiftAiActionEndpoint =>
      '$resolvedAiWorkerBase/shift-ai-action';
  static String get briefingEndpoint => '$resolvedAiWorkerBase/briefing';
  static String get predictEndpoint => '$resolvedAiWorkerBase/predict';
  static String get suggestAssigneeEndpoint =>
      '$resolvedAiWorkerBase/suggest-assignee';
  static String get notifyEndpoint => '$resolvedNotifyWorkerBase/notify';
  static String get notifyTriggerEndpoint => notifyEndpoint;
  static String get aiRetryEndpoint => '$resolvedAiWorkerBase/ai-retry';
  static String get evalModelEndpoint => '$resolvedAiWorkerBase/eval-model';

  // ── Industrial connector endpoints ────────────────────────────────────────
  static String get connectorVerifyEndpoint =>
      '$resolvedIngestWorkerBase/verify';
  static String get connectorControlEndpoint =>
      '$resolvedIngestWorkerBase/control';
  static String connectorIngestEndpoint(String connectorId) =>
      '$resolvedIngestWorkerBase/ingest/$connectorId';

  // ── Timeouts ────────────────────────────────────────────────────────────
  static const Duration defaultRequestTimeout = Duration(seconds: 8);
  static const Duration shortRequestTimeout = Duration(seconds: 5);
}

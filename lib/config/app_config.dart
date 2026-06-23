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
  /// authenticates with [workerSharedSecret].
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

  /// Deprecated alias for old call sites. New code should choose aiWorkerBase
  /// or notifyWorkerBase explicitly.
  static const String workerBaseUrl = aiWorkerBase;

  /// Optional shared secret sent on worker requests when set.
  static const String workerSharedSecret = String.fromEnvironment(
    'ALERTSYS_WORKER_SHARED_SECRET',
    defaultValue: '',
  );

  // ── Worker endpoints ────────────────────────────────────────────────────
  static String get workerRoot => aiWorkerBase;
  static String get configEndpoint => '$aiWorkerBase/config';
  static String get aiSuggestEndpoint => '$aiWorkerBase/ai-suggest';
  static String get shiftAiActionEndpoint => '$aiWorkerBase/shift-ai-action';
  static String get briefingEndpoint => '$aiWorkerBase/briefing';
  static String get predictEndpoint => '$aiWorkerBase/predict';
  static String get suggestAssigneeEndpoint => '$aiWorkerBase/suggest-assignee';
  static String get notifyEndpoint => '$notifyWorkerBase/notify';
  static String get notifyTriggerEndpoint => notifyEndpoint;
  static String get aiRetryEndpoint => '$aiWorkerBase/ai-retry';
  static String get evalModelEndpoint => '$aiWorkerBase/eval-model';

  // ── Industrial connector endpoints ────────────────────────────────────────
  static String get connectorVerifyEndpoint => '$ingestWorkerBase/verify';
  static String get connectorControlEndpoint => '$ingestWorkerBase/control';
  static String connectorIngestEndpoint(String connectorId) =>
      '$ingestWorkerBase/ingest/$connectorId';

  // ── Timeouts ────────────────────────────────────────────────────────────
  static const Duration defaultRequestTimeout = Duration(seconds: 8);
  static const Duration shortRequestTimeout = Duration(seconds: 5);
}

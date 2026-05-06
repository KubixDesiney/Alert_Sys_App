/// Single source of truth for cross-cutting configuration constants.
///
/// Values are overridable at build time via `--dart-define` (see CI). Keeping
/// them here avoids string drift across services and makes the future DI
/// migration (Phase 6) trivial: services read from [AppConfig] instead of
/// holding private `const` URLs.
class AppConfig {
  const AppConfig._();

  /// Cloudflare Worker base URL. Override with `--dart-define=ALERTSYS_WORKER_URL=...`.
  static const String workerBaseUrl = String.fromEnvironment(
    'ALERTSYS_WORKER_URL',
    defaultValue: 'https://alert-notifier.aziz-nagati01.workers.dev',
  );

  /// Optional shared secret sent on worker requests when set.
  static const String workerSharedSecret = String.fromEnvironment(
    'ALERTSYS_WORKER_SHARED_SECRET',
    defaultValue: '',
  );

  // ── Worker endpoints ────────────────────────────────────────────────────
  static String get workerRoot => workerBaseUrl;
  static String get configEndpoint => '$workerBaseUrl/config';
  static String get aiSuggestEndpoint => '$workerBaseUrl/ai-suggest';
  static String get shiftAiActionEndpoint => '$workerBaseUrl/shift-ai-action';
  static String get briefingEndpoint => '$workerBaseUrl/briefing';
  static String get predictEndpoint => '$workerBaseUrl/predict';
  static String get suggestAssigneeEndpoint => '$workerBaseUrl/suggest-assignee';

  // ── Timeouts ────────────────────────────────────────────────────────────
  static const Duration defaultRequestTimeout = Duration(seconds: 8);
  static const Duration shortRequestTimeout = Duration(seconds: 5);
}

class WorkerAuthConfig {
  WorkerAuthConfig._();

  static const String baseUrl = String.fromEnvironment(
    'ALERTSYS_WORKER_URL',
    defaultValue: 'https://alert-notifier.aziz-nagati01.workers.dev',
  );

  static const String sharedSecret = String.fromEnvironment(
    'ALERTSYS_WORKER_SHARED_SECRET',
  );

  static Map<String, String> headers({
    bool json = false,
    String? firebaseIdToken,
  }) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (sharedSecret.isNotEmpty) 'X-AlertSys-Worker-Secret': sharedSecret,
      if (firebaseIdToken != null && firebaseIdToken.isNotEmpty)
        'X-Firebase-ID-Token': firebaseIdToken,
    };
  }
}

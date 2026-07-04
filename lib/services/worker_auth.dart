import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';

/// Builds the authentication headers for calls to the platform's own
/// Cloudflare workers (AI + notify).
///
/// The primary credential is the signed-in user's **Firebase ID token** —
/// short-lived, per-user, and verifiable server-side against Google's public
/// keys — sent as `Authorization: Bearer <idToken>`. The static
/// `ALERTSYS_WORKER_SHARED_SECRET` baked into builds is a legacy credential
/// kept only while the installed fleet migrates; the workers accept either
/// (see `WORKER_AUTH_MODE` in wrangler.ai.toml). Once every client sends ID
/// tokens the secret gets dropped from app builds entirely.
class WorkerAuth {
  const WorkerAuth._();

  static Future<Map<String, String>> headers() async {
    final h = <String, String>{};
    if (AppConfig.workerSharedSecret.isNotEmpty) {
      h['x-worker-secret'] = AppConfig.workerSharedSecret;
    }
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null && token.isNotEmpty) {
        h['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // No Firebase session (tests, pre-login) — the request goes out with
      // whatever legacy credential is configured; the worker's 'log' mode
      // records it.
    }
    return h;
  }
}

import 'package:firebase_auth/firebase_auth.dart';

/// Builds the authentication headers for calls to the platform's own
/// Cloudflare workers (AI + notify).
///
/// The only credential is the signed-in user's **Firebase ID token** —
/// short-lived, per-user, and verifiable server-side against Google's public
/// keys — sent as `Authorization: Bearer <idToken>`.
///
/// The static `WORKER_SHARED_SECRET` is no longer sent, and no longer compiled
/// into builds. It grants full worker-level access, so a build that carried it
/// published that credential to anyone who opened `main.dart.js`. It is now a
/// worker-to-worker and CI credential only. Both workers run
/// `WORKER_AUTH_MODE=required` and still accept the secret from server-side
/// callers; browser and app traffic authenticates as a user.
class WorkerAuth {
  const WorkerAuth._();

  static Future<Map<String, String>> headers() async {
    final h = <String, String>{};
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null && token.isNotEmpty) {
        h['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // No Firebase session (tests, pre-login). The request goes out
      // unauthenticated and the worker rejects it under
      // WORKER_AUTH_MODE=required; for queued alert triggers the notify
      // worker's one-minute cron still delivers.
    }
    return h;
  }
}

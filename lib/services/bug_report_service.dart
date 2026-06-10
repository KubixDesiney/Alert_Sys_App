import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Captures runtime errors (widget build failures, uncaught async errors and
/// every ERROR-level log line across services) and persists deduplicated bug
/// records under `bugs/client/{hash}` for the SuperAdmin Logs tab.
///
/// The autonomous bug-fix agent later annotates the same records with
/// `status: ai_fixed` (plus commit) or `status: escalated` (plus the GitHub
/// issue URL) so operators can see what the AI did about each bug.
class BugReportService {
  BugReportService._();

  static final BugReportService instance = BugReportService._();

  static const _minReportInterval = Duration(minutes: 5);
  final Map<String, DateTime> _lastReported = {};
  bool _initialized = false;

  /// Wires the global hooks. Safe to call once at startup.
  void init() {
    if (_initialized) return;
    _initialized = true;

    AppLogger.onErrorEntry = (entry) {
      unawaited(report(
        area: inferArea('${entry.message} ${entry.error ?? ''}'),
        message: entry.message,
        error: entry.error,
      ));
    };

    // Uncaught async errors (outside the Flutter framework zone).
    final previous = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(
        area: inferArea('$error'),
        message: 'Uncaught async error',
        error: '$error',
        stack: stack,
      ));
      if (previous != null) return previous(error, stack);
      return false;
    };
  }

  /// Routes an error message to a functional area shown in the Logs tab.
  static String inferArea(String text) {
    final t = text.toLowerCase();
    if (t.contains('login') || t.contains('auth') || t.contains('sign')) {
      return 'auth';
    }
    if (t.contains('notification') || t.contains('fcm') || t.contains('push')) {
      return 'notifications';
    }
    if (t.contains('permission') ||
        t.contains('database') ||
        t.contains('firebase') ||
        t.contains('rtdb')) {
      return 'database';
    }
    if (t.contains('locator') || t.contains('map') || t.contains('location')) {
      return 'locator';
    }
    if (t.contains('supervisor')) return 'supervisors';
    if (t.contains('voice') || t.contains('speech') || t.contains('stt')) {
      return 'voice';
    }
    if (t.contains('shift')) return 'shifts';
    if (t.contains('lstm') || t.contains(' ai ') || t.startsWith('ai')) {
      return 'ai';
    }
    return 'app';
  }

  /// Writes (or refreshes) a deduplicated bug record. Never throws.
  Future<void> report({
    required String area,
    required String message,
    String? error,
    StackTrace? stack,
  }) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return;

      final hash = _fnv1a('$area|$message|${_clamp(error ?? '', 120)}');
      final now = DateTime.now();
      final last = _lastReported[hash];
      if (last != null && now.difference(last) < _minReportInterval) return;
      _lastReported[hash] = now;

      final ref = FirebaseDatabase.instance.ref('bugs/client/$hash');
      final existing = await ref.get();
      final nowIso = now.toUtc().toIso8601String();
      if (existing.exists && existing.value is Map) {
        await ref.update({
          'lastSeenAt': nowIso,
          'count': ServerValue.increment(1),
        });
      } else {
        await ref.set({
          'area': area,
          'message': _clamp(message, 500),
          if (error != null && error.isNotEmpty) 'error': _clamp(error, 1500),
          if (stack != null) 'stack': _clamp('$stack', 2500),
          'status': 'detected',
          'firstSeenAt': nowIso,
          'lastSeenAt': nowIso,
          'count': 1,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'appSource': 'client',
        });
      }
    } catch (e) {
      // Use debugPrint directly — going through AppLogger here would loop.
      debugPrint('[bug_report] failed to persist bug record: $e');
    }
  }

  static String _clamp(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final code in input.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

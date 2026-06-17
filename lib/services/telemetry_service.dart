import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Lightweight, self-hosted application telemetry — the data behind a real APM
/// view. On every app start it records a session; on the first error in a
/// session it records a "crashed" session, plus a running error count. From
/// those three counters the console computes the **crash-free session rate** and
/// **error rate**, and the monitor worker fires an SLA/error-budget alert when
/// crash-free drops below the configured SLO.
///
/// Counters live at `telemetry/daily/{yyyy-MM-dd}` and are incremented
/// atomically with `ServerValue.increment`, so concurrent devices never clobber
/// each other. This is intentionally dependency-free (no Sentry/Crashlytics
/// native SDK) so it ships on every platform and feeds the existing
/// monitor-worker + webhook alerting you already run.
class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  bool _initialized = false;
  bool _sessionErrored = false;
  int _sessionErrorCount = 0;
  DateTime _lastErrorWrite = DateTime.fromMillisecondsSinceEpoch(0);

  // Guard rails so a runaway error loop can't flood RTDB.
  static const int _maxErrorsPerSession = 300;
  static const Duration _minErrorWriteGap = Duration(milliseconds: 500);

  static String todayKey() =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  DatabaseReference _node(String child) =>
      FirebaseDatabase.instance.ref('telemetry/daily/${todayKey()}/$child');

  /// Wires the global error hooks. Call ONCE at startup, AFTER
  /// `BugReportService.init()` so the existing hooks are chained, not replaced.
  void init() {
    if (_initialized) return;
    _initialized = true;
    unawaited(_recordSession());

    final prevEntry = AppLogger.onErrorEntry;
    AppLogger.onErrorEntry = (entry) {
      prevEntry?.call(entry); // keep the bugs/client pipeline running
      _onError();
    };

    final prevOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _onError();
      return prevOnError?.call(error, stack) ?? false;
    };
  }

  Future<void> _recordSession() async {
    try {
      await _node('sessions').set(ServerValue.increment(1));
      await _node('lastAt').set(DateTime.now().toIso8601String());
    } catch (_) {
      // Telemetry is strictly best-effort; never surface its own failures.
    }
  }

  void _onError() {
    if (_sessionErrorCount >= _maxErrorsPerSession) return;
    _sessionErrorCount++;
    final firstThisSession = !_sessionErrored;
    _sessionErrored = true;

    final now = DateTime.now();
    if (!firstThisSession &&
        now.difference(_lastErrorWrite) < _minErrorWriteGap) {
      return; // collapse bursts; the count stays approximate by design
    }
    _lastErrorWrite = now;
    unawaited(_writeError(firstThisSession));
  }

  Future<void> _writeError(bool firstThisSession) async {
    try {
      await _node('errors').set(ServerValue.increment(1));
      if (firstThisSession) {
        await _node('errorSessions').set(ServerValue.increment(1));
      }
    } catch (_) {}
  }

  /// Fraction of sessions with no reported error (0..1). Pure — unit tested.
  static double crashFreeRate({required int sessions, required int errorSessions}) {
    if (sessions <= 0) return 1.0;
    final free = (sessions - errorSessions).clamp(0, sessions);
    return free / sessions;
  }

  /// Average errors per session. Pure — unit tested.
  static double errorRate({required int sessions, required int errors}) {
    if (sessions <= 0) return 0.0;
    return errors / sessions;
  }
}

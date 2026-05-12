import 'dart:async';

import 'package:flutter/foundation.dart';

/// A single buffered log entry — kept in memory so the Developer tab can
/// surface recent console output without depending on `adb logcat` or a
/// browser dev console. We do not persist these anywhere; the buffer dies
/// with the process.
class AppLogEntry {
  final DateTime at;
  final String level;
  final String message;
  final String? error;

  const AppLogEntry({
    required this.at,
    required this.level,
    required this.message,
    this.error,
  });
}

/// Lightweight in-memory ring buffer that captures recent log lines and
/// notifies any number of listeners (e.g. the Developer tab's console pane).
///
/// Kept as a separate object on purpose: `AppLogger` is a `const` value in
/// many places, so we cannot store mutable state on it directly. Listeners
/// hold a reference to this singleton.
class AppLogBuffer {
  AppLogBuffer._();

  static final AppLogBuffer instance = AppLogBuffer._();

  /// Maximum number of log lines retained. The oldest entry is evicted
  /// when the buffer is full.
  static const int capacity = 200;

  final List<AppLogEntry> _entries = <AppLogEntry>[];
  final StreamController<List<AppLogEntry>> _controller =
      StreamController<List<AppLogEntry>>.broadcast();

  /// Snapshot of the current buffer contents, newest entry last.
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  /// Subscribe to live updates — the stream emits the full buffer every
  /// time a new line is appended. Subscribers redraw against the snapshot
  /// they receive rather than maintain their own state.
  Stream<List<AppLogEntry>> get stream => _controller.stream;

  void add(AppLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeAt(0);
    }
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_entries));
    }
  }

  void clear() {
    _entries.clear();
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_entries));
    }
  }
}

class AppLogger {
  const AppLogger({this.enabled = true});

  final bool enabled;

  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _log('DEBUG', message, error, stackTrace);
  }

  void info(String message, [Object? error, StackTrace? stackTrace]) {
    _log('INFO', message, error, stackTrace);
  }

  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _log('WARN', message, error, stackTrace);
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message, error, stackTrace);
  }

  void _log(
    String level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!enabled) {
      return;
    }
    final buffer = StringBuffer('[$level] $message');
    if (error != null) {
      buffer.write(' | $error');
    }
    if (stackTrace != null && kDebugMode) {
      buffer.write('\n$stackTrace');
    }
    debugPrint(buffer.toString());
    // Mirror into the in-memory ring buffer so the Developer tab can read
    // it. We deliberately keep the buffer behind a singleton rather than
    // an instance field — the existing codebase uses `const AppLogger()`
    // in several places.
    AppLogBuffer.instance.add(
      AppLogEntry(
        at: DateTime.now(),
        level: level,
        message: message,
        error: error?.toString(),
      ),
    );
  }
}

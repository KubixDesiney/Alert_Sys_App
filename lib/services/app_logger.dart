import 'package:flutter/foundation.dart';

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
  }
}

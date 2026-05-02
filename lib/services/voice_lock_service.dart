import 'dart:io';

import 'package:flutter/services.dart';

class VoiceLockResult {
  final String transcript;
  final List<String> alternatives;
  final String audioPath;
  const VoiceLockResult({
    required this.transcript,
    this.alternatives = const <String>[],
    required this.audioPath,
  });

  Iterable<String> get transcripts sync* {
    if (transcript.trim().isNotEmpty) yield transcript.trim();
    for (final alternative in alternatives) {
      final text = alternative.trim();
      if (text.isNotEmpty) yield text;
    }
  }
}

/// Flutter wrapper for the Android full-screen voice-lock recording flow.
/// Returns null on non-Android platforms or if the platform channel fails.
class VoiceLockService {
  static const _channel = MethodChannel('alertsys/voice_lock');

  static Future<VoiceLockResult?> startVoiceLockFlow({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startVoiceLockFlow',
        {'timeoutMs': timeout.inMilliseconds},
      );
      if (result == null) return null;
      return VoiceLockResult(
        transcript: result['transcript']?.toString() ?? '',
        alternatives: _stringListFromChannelValue(result['alternatives']),
        audioPath: result['audioPath']?.toString() ?? '',
      );
    } on PlatformException {
      return null;
    }
  }

  static List<String> _stringListFromChannelValue(Object? value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }
}

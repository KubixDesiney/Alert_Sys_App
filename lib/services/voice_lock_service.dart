import 'dart:io';

import 'package:flutter/services.dart';

class VoiceLockResult {
  final String transcript;
  final String audioPath;
  const VoiceLockResult({required this.transcript, required this.audioPath});
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
        audioPath: result['audioPath']?.toString() ?? '',
      );
    } on PlatformException {
      return null;
    }
  }
}

// Bridges parsed [VoiceCommand] objects to AlertProvider actions.
// Speaks confirmations/errors via [VoiceService] so the user always hears
// whether the command succeeded — this matters for hands-free use.
// Reuses the existing AlertProvider methods so all claim/resolve/escalate
// rules (in-progress checks, hierarchy notifications, etc.) keep working.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:typed_data';
import '../providers/alert_provider.dart';
import 'voice_auth_service.dart';
import 'voice_command_parser.dart';
import 'voice_service.dart';

class VoiceCommandDispatcher {
  final AlertProvider provider;
  VoiceCommandDispatcher(this.provider);

  /// Run a parsed command against the provider. All user feedback goes
  /// through TTS — there's no UI surface in this layer by design.
  ///
  /// Biometric verification is mandatory here:
  ///   - If [voiceAlreadyVerified] is true, the caller already checked it.
  ///   - Otherwise [rawAudio] must match the current user's enrolled voiceprint.
  Future<VoiceCommandExecutionResult> execute(
    VoiceCommand cmd, {
    Uint8List? rawAudio,
    int rawAudioSampleRate = 16000,
    bool voiceAlreadyVerified = false,
    String? fallbackAlertId,
  }) async {
    if (!voiceAlreadyVerified) {
      final hasAudio = rawAudio != null && rawAudio.lengthInBytes >= 1600;
      if (!hasAudio) {
        return _speakResult(
          false,
          'I could not capture your voice sample. Please try again.',
        );
      }
      final auth = await VoiceAuthService.instance.verifyCurrentUser(
        rawAudio: rawAudio,
        sampleRate: rawAudioSampleRate,
      );
      if (!auth.verified) {
        return _speakResult(false, _authFailureMessage(auth));
      }
    }

    if (cmd.intent == VoiceIntent.unknown) {
      return _speakResult(false,
          'I did not understand. Say the full command, like claim alert 1025 or resolve alert 1025.');
    }

    // Navigation intents — caller wires these up via a callback if desired.
    // Speaking-only fallback so the user knows we heard them.
    switch (cmd.intent) {
      case VoiceIntent.showDashboard:
        return _speakResult(true, 'Opening dashboard.');
      case VoiceIntent.showAlerts:
        return _speakResult(true, 'Showing alerts.');
      case VoiceIntent.showFixed:
        return _speakResult(true, 'Showing resolved alerts.');
      default:
        break;
    }

    final number = cmd.alertNumber;
    final _AlertRef? match;
    if (number == null) {
      if (fallbackAlertId != null &&
          fallbackAlertId.isNotEmpty &&
          _mentionsAlert(cmd.rawText)) {
        match = _findById(fallbackAlertId);
        if (match == null) {
          return _speakResult(false, 'Alert was not found.');
        }
      } else {
        return _speakResult(false,
            'I did not catch the alert number. Say the full command, like claim alert 1025.');
      }
    } else {
      // Look up the alert by alertNumber. Voice commands require the spoken,
      // human-facing alert number so there is no second prompt or confirmation.
      match = _findByNumber(number);
      if (match == null) {
        return _speakResult(false, 'Alert number $number was not found.');
      }
    }

    try {
      switch (cmd.intent) {
        case VoiceIntent.claim:
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            return _speakResult(false, 'You are not signed in.');
          }
          final name = await _displayName(user.uid) ?? 'Supervisor';
          await provider.takeAlert(match.id, user.uid, name);
          return _speakResult(true, 'Alert ${match.number} claimed.');
        case VoiceIntent.resolve:
          final reason = (cmd.reason == null || cmd.reason!.trim().isEmpty)
              ? 'Resolved by voice command'
              : cmd.reason!.trim();
          await provider.resolveAlert(match.id, reason);
          return _speakResult(true, 'Alert ${match.number} resolved.');
        case VoiceIntent.escalate:
          await provider.toggleCritical(match.id, true);
          return _speakResult(true, 'Alert ${match.number} escalated.');
        default:
          break;
      }
    } catch (e) {
      return _speakResult(false, 'Action failed. ${_shortError(e)}');
    }
    return const VoiceCommandExecutionResult(
      success: false,
      message: 'Command was not handled.',
    );
  }

  // Look up by alertNumber from the provider's cached list.
  _AlertRef? _findByNumber(int number) {
    for (final a in provider.allAlerts) {
      if (a.alertNumber == number) {
        return _AlertRef(a.id, a.alertNumber);
      }
    }
    return null;
  }

  _AlertRef? _findById(String alertId) {
    for (final a in provider.allAlerts) {
      if (a.id == alertId) {
        return _AlertRef(a.id, a.alertNumber);
      }
    }
    return null;
  }

  static bool _mentionsAlert(String rawText) {
    final normalized = rawText
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return RegExp(r'\b(alert|alerts|alarm|alarms|case|ticket)\b')
        .hasMatch(normalized);
  }

  Future<String?> _displayName(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('users/$uid').get();
      if (!snap.exists) return null;
      final m = Map<String, dynamic>.from(snap.value as Map);
      return (m['fullName'] ?? m['name'] ?? m['email'])?.toString();
    } catch (_) {
      return null;
    }
  }

  static String _shortError(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }

  static String _authFailureMessage(VoiceVerificationResult auth) {
    if (auth.unenrolled) return 'Please enroll your voice first.';
    final message = auth.message ?? '';
    if (message.contains('No audio sample')) {
      return 'I could not capture your voice sample. Please try again.';
    }
    return 'Voice not recognized';
  }

  Future<VoiceCommandExecutionResult> _speakResult(
    bool success,
    String message,
  ) async {
    await VoiceService.instance.speak(message);
    return VoiceCommandExecutionResult(success: success, message: message);
  }
}

class VoiceCommandExecutionResult {
  final bool success;
  final String message;

  const VoiceCommandExecutionResult({
    required this.success,
    required this.message,
  });
}

class _AlertRef {
  final String id;
  final int number;
  _AlertRef(this.id, this.number);
}

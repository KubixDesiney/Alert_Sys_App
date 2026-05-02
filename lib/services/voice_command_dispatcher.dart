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
  Future<void> execute(
    VoiceCommand cmd, {
    Uint8List? rawAudio,
    int rawAudioSampleRate = 16000,
    bool voiceAlreadyVerified = false,
  }) async {
    if (!voiceAlreadyVerified) {
      final auth = await VoiceAuthService.instance.verifyCurrentUser(
        rawAudio: rawAudio,
        sampleRate: rawAudioSampleRate,
      );
      if (!auth.verified) {
        await VoiceService.instance.speak('Voice not recognized');
        return;
      }
    }

    if (cmd.intent == VoiceIntent.unknown) {
      await VoiceService.instance.speak(
          'I did not understand. Try saying claim alert, resolve alert, or escalate alert.');
      return;
    }

    // Navigation intents — caller wires these up via a callback if desired.
    // Speaking-only fallback so the user knows we heard them.
    switch (cmd.intent) {
      case VoiceIntent.showDashboard:
        await VoiceService.instance.speak('Opening dashboard.');
        return;
      case VoiceIntent.showAlerts:
        await VoiceService.instance.speak('Showing alerts.');
        return;
      case VoiceIntent.showFixed:
        await VoiceService.instance.speak('Showing resolved alerts.');
        return;
      default:
        break;
    }

    final number = cmd.alertNumber;
    if (number == null && cmd.intent != VoiceIntent.claim) {
      await VoiceService.instance.speak(
          'I did not catch the alert number. Please say the number clearly.');
      return;
    }

    // Look up the alert by alertNumber. For a plain "claim alert" command,
    // allow a hands-free claim only when there is exactly one available alert.
    final match =
        number == null ? _singleAvailableClaimTarget() : _findByNumber(number);
    if (match == null) {
      if (number == null) {
        final available = provider.availableAlerts.length;
        await VoiceService.instance.speak(available == 0
            ? 'There are no available alerts to claim.'
            : 'I found $available available alerts. Say claim alert followed by the number.');
      } else {
        await VoiceService.instance
            .speak('Alert number $number was not found.');
      }
      return;
    }

    try {
      switch (cmd.intent) {
        case VoiceIntent.claim:
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            await VoiceService.instance.speak('You are not signed in.');
            return;
          }
          final name = await _displayName(user.uid) ?? 'Supervisor';
          await provider.takeAlert(match.id, user.uid, name);
          await VoiceService.instance.speak('Alert ${match.number} claimed.');
          break;
        case VoiceIntent.resolve:
          final reason = (cmd.reason == null || cmd.reason!.trim().isEmpty)
              ? 'Resolved by voice command'
              : cmd.reason!.trim();
          await provider.resolveAlert(match.id, reason);
          await VoiceService.instance.speak('Alert ${match.number} resolved.');
          break;
        case VoiceIntent.escalate:
          await provider.toggleCritical(match.id, true);
          await VoiceService.instance.speak('Alert ${match.number} escalated.');
          break;
        default:
          break;
      }
    } catch (e) {
      await VoiceService.instance.speak('Action failed. ${_shortError(e)}');
    }
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

  _AlertRef? _singleAvailableClaimTarget() {
    final available = provider.availableAlerts;
    if (available.length != 1) return null;
    final alert = available.first;
    return _AlertRef(alert.id, alert.alertNumber);
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
}

class _AlertRef {
  final String id;
  // ignore: unused_element
  final int number;
  _AlertRef(this.id, this.number);
}

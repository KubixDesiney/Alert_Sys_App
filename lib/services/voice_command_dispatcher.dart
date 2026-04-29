// Bridges parsed [VoiceCommand] objects to AlertProvider actions.
// Speaks confirmations/errors via [VoiceService] so the user always hears
// whether the command succeeded — this matters for hands-free use.
// Reuses the existing AlertProvider methods so all claim/resolve/escalate
// rules (in-progress checks, hierarchy notifications, etc.) keep working.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/alert_provider.dart';
import 'voice_command_parser.dart';
import 'voice_service.dart';

class VoiceCommandDispatcher {
  final AlertProvider provider;
  VoiceCommandDispatcher(this.provider);

  /// Run a parsed command against the provider. All user feedback goes
  /// through TTS — there's no UI surface in this layer by design.
  Future<void> execute(VoiceCommand cmd) async {
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
    if (number == null) {
      await VoiceService.instance.speak(
          'I did not catch the alert number. Please say the number clearly.');
      return;
    }

    // Look up the alert by alertNumber. Falls back to the last-seen list
    // from the provider. If not found, abort with a spoken error.
    final match = _findByNumber(number);
    if (match == null) {
      await VoiceService.instance
          .speak('Alert number $number was not found.');
      return;
    }

    try {
      switch (cmd.intent) {
        case VoiceIntent.claim:
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            await VoiceService.instance
                .speak('You are not signed in.');
            return;
          }
          final name = await _displayName(user.uid) ?? 'Supervisor';
          await provider.takeAlert(match.id, user.uid, name);
          await VoiceService.instance.speak('Alert $number claimed.');
          break;
        case VoiceIntent.resolve:
          final reason = (cmd.reason == null || cmd.reason!.trim().isEmpty)
              ? 'Resolved by voice command'
              : cmd.reason!.trim();
          await provider.resolveAlert(match.id, reason);
          await VoiceService.instance.speak('Alert $number resolved.');
          break;
        case VoiceIntent.escalate:
          await provider.toggleCritical(match.id, true);
          await VoiceService.instance.speak('Alert $number escalated.');
          break;
        default:
          break;
      }
    } catch (e) {
      await VoiceService.instance
          .speak('Action failed. ${_shortError(e)}');
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

  Future<String?> _displayName(String uid) async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('users/$uid').get();
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

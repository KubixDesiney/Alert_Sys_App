// Minimal full-screen voice flow opened from the "Speak command"
// notification action. Walks the user through:
//   1. capture command  ("claim alert" / "claim alert N" / "accept assignment")
//   2. resolve target alert
//   3. capture confirmation ("yes")
//   4. invoke AlertProvider.takeAlert (existing claim rules apply)
//   5. speak result, close screen
//
// Designed to feel like a phone-call screen: large status text, mic indicator,
// no nav bar. On Android we ask the host activity to show on lock screen
// + turn the screen on via a method channel into MainActivity.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/alert_model.dart';
import '../providers/alert_provider.dart';
import '../services/voice_command_parser.dart';
import '../services/voice_service.dart';
import '../theme.dart';

class VoiceClaimScreen extends StatefulWidget {
  /// If the alert id is known from the notification payload, pass it here.
  /// The user can still say "claim alert N" to override or to claim
  /// a different alert by number.
  final String? alertId;

  const VoiceClaimScreen({super.key, this.alertId});

  @override
  State<VoiceClaimScreen> createState() => _VoiceClaimScreenState();
}

enum _Step { initializing, awaitingCommand, awaitingConfirm, working, done }

class _VoiceClaimScreenState extends State<VoiceClaimScreen> {
  static const _channel = MethodChannel('alertsys/voice_claim');

  _Step _step = _Step.initializing;
  String _statusLine = 'Preparing voice command…';
  String _hint = '';
  bool _success = false;
  bool _flowStarted = false;

  @override
  void initState() {
    super.initState();
    _prepareLockScreenVoice();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runFlow());
  }

  @override
  void dispose() {
    VoiceService.instance.stopListening();
    _disableLockScreenMode();
    super.dispose();
  }

  Future<void> _prepareLockScreenVoice() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('prepareLockScreenVoice');
    } catch (_) {
      try {
        await _channel.invokeMethod('showOnLockScreen');
      } catch (_) {}
    }
  }

  Future<void> _disableLockScreenMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('clearLockScreen');
    } catch (_) {}
  }

  Future<void> _runFlow() async {
    if (_flowStarted) return;
    _flowStarted = true;

    await VoiceService.instance.init();
    if (!mounted) return;

    if (!VoiceService.instance.isAvailable) {
      _finish(
        success: false,
        message:
            'Voice unavailable: ${VoiceService.instance.lastError ?? "speech recognizer not ready"}',
        speak: 'Voice is not available on this device.',
      );
      return;
    }

    _setStep(_Step.awaitingCommand,
        status: 'Speak your command',
        hint: 'e.g. "Claim alert" or "Accept assignment"');
    await VoiceService.instance.speak('Speak your command.');
    if (!mounted) return;

    final cmdText = await VoiceService.instance
        .captureOnce(timeout: const Duration(seconds: 6));
    if (!mounted) return;

    final cmd = VoiceCommandParser.parse(cmdText);
    if (cmd.intent != VoiceIntent.claim) {
      _finish(
        success: false,
        message: cmdText.isEmpty
            ? 'I did not hear a command.'
            : 'Unrecognized command: "$cmdText"',
        speak: 'I did not understand. Try claim alert, or accept assignment.',
      );
      return;
    }

    final target = await _resolveTargetAlert(cmd.alertNumber);
    if (target == null) {
      _finish(
        success: false,
        message: cmd.alertNumber != null
            ? 'Alert number ${cmd.alertNumber} not found.'
            : 'No alert specified. Say "claim alert" followed by the number.',
        speak: cmd.alertNumber != null
            ? 'Alert number ${cmd.alertNumber} was not found.'
            : 'I did not catch the alert number.',
      );
      return;
    }

    if (target.status != 'disponible') {
      _finish(
        success: false,
        message: 'Alert #${target.alertNumber} is no longer available '
            '(status: ${target.status}).',
        speak: 'That alert is no longer available.',
      );
      return;
    }

    _setStep(_Step.awaitingConfirm,
        status: 'Say YES to confirm',
        hint: 'Claim alert #${target.alertNumber}?');
    await VoiceService.instance.speak('Say yes to confirm.');
    if (!mounted) return;

    final confirmText = await VoiceService.instance
        .captureOnce(timeout: const Duration(seconds: 4));
    if (!mounted) return;

    if (!VoiceCommandParser.isYes(confirmText)) {
      _finish(
        success: false,
        message: 'Confirmation not received — claim cancelled.',
        speak: 'Cancelled.',
      );
      return;
    }

    _setStep(_Step.working,
        status: 'Claiming alert…', hint: 'Alert #${target.alertNumber}');

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _finish(
          success: false,
          message: 'You are not signed in.',
          speak: 'You are not signed in.',
        );
        return;
      }

      final provider = context.read<AlertProvider>();
      final name = await _displayName(user.uid) ?? 'Supervisor';
      await provider.takeAlert(target.id, user.uid, name);

      _finish(
        success: true,
        message: 'Alert #${target.alertNumber} claimed.',
        speak: 'Alert claimed.',
      );
    } catch (e) {
      _finish(
        success: false,
        message: _humanizeError(e),
        speak: _humanizeError(e),
      );
    }
  }

  Future<AlertModel?> _resolveTargetAlert(int? spokenNumber) async {
    final provider = context.read<AlertProvider>();
    final alerts = provider.allAlerts;

    // 1. Spoken number always wins — the user explicitly named one.
    if (spokenNumber != null) {
      for (final a in alerts) {
        if (a.alertNumber == spokenNumber) return a;
      }
      return null;
    }

    // 2. Notification-supplied id, if still in cache.
    if (widget.alertId != null) {
      for (final a in alerts) {
        if (a.id == widget.alertId) return a;
      }
      // Cache miss — fall back to a direct DB read.
      try {
        final snap = await FirebaseDatabase.instance
            .ref('alerts/${widget.alertId}')
            .get();
        if (snap.exists && snap.value != null) {
          return AlertModel.fromMap(
              widget.alertId!, Map<String, dynamic>.from(snap.value as Map));
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _displayName(String uid) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('users/$uid').get();
      if (!snap.exists) return null;
      final m = Map<String, dynamic>.from(snap.value as Map);
      final first = (m['firstName'] ?? '').toString();
      final last = (m['lastName'] ?? '').toString();
      final full = '$first $last'.trim();
      if (full.isNotEmpty) return full;
      return (m['fullName'] ?? m['name'] ?? m['email'])?.toString();
    } catch (_) {
      return null;
    }
  }

  String _humanizeError(Object e) {
    final s = e.toString();
    if (s.contains('already have an alert in progress')) {
      return 'You already have an alert in progress. Resolve it first.';
    }
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  void _setStep(_Step step, {required String status, String hint = ''}) {
    if (!mounted) return;
    setState(() {
      _step = step;
      _statusLine = status;
      _hint = hint;
    });
  }

  void _finish({
    required bool success,
    required String message,
    required String speak,
  }) async {
    if (!mounted) return;
    setState(() {
      _step = _Step.done;
      _statusLine = message;
      _success = success;
      _hint = '';
    });
    await VoiceService.instance.speak(speak);
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final listening =
        _step == _Step.awaitingCommand || _step == _Step.awaitingConfirm;

    Color iconColor;
    IconData iconData;
    if (_step == _Step.done) {
      iconColor = _success ? t.green : t.red;
      iconData = _success ? Icons.check_circle : Icons.error_outline;
    } else if (listening) {
      iconColor = t.red;
      iconData = Icons.mic;
    } else {
      iconColor = t.navy;
      iconData = Icons.mic_none;
    }

    return Scaffold(
      backgroundColor: t.scaffold,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close, color: t.muted),
                  ),
                  const Spacer(),
                  Text('Voice claim',
                      style: TextStyle(
                          color: t.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                ],
              ),
              const Spacer(),
              _PulseIcon(active: listening, icon: iconData, color: iconColor),
              const SizedBox(height: 36),
              Text(
                _statusLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.text, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              if (_hint.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted, fontSize: 14),
                ),
              ],
              const Spacer(),
              if (_step == _Step.done)
                ElevatedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Close'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  final bool active;
  final IconData icon;
  final Color color;
  const _PulseIcon(
      {required this.active, required this.icon, required this.color});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseIcon old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = widget.active ? _c.value : 0.0;
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                Container(
                  width: 100 + 60 * v,
                  height: 100 + 60 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.18 * (1 - v)),
                  ),
                ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
                child: Icon(widget.icon, color: Colors.white, size: 44),
              ),
            ],
          ),
        );
      },
    );
  }
}

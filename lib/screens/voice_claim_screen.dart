// Full-screen voice flow opened from the "Speak command" notification action.
// It captures one complete command such as "claim alert 1025" or
// "resolve alert 1025", verifies the speaker, executes it, then closes.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:provider/provider.dart';

import '../providers/alert_provider.dart';
import '../services/voice_command_dispatcher.dart';
import '../services/voice_command_parser.dart';
import '../services/voice_service.dart';
import '../theme.dart';

class VoiceClaimScreen extends StatefulWidget {
  /// Kept for notification payload compatibility. Commands intentionally use
  /// the spoken alert number so the user can say one full sentence.
  final String? alertId;

  const VoiceClaimScreen({super.key, this.alertId});

  @override
  State<VoiceClaimScreen> createState() => _VoiceClaimScreenState();
}

enum _Step { initializing, awaitingCommand, working, done }

class _VoiceClaimScreenState extends State<VoiceClaimScreen> {
  static const _channel = MethodChannel('alertsys/voice_claim');

  _Step _step = _Step.initializing;
  String _statusLine = 'Preparing voice command...';
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

    _setStep(
      _Step.awaitingCommand,
      status: 'Speak your command',
      hint: 'e.g. "Claim alert 1025" or "Resolve alert 1025"',
    );
    await VoiceService.instance.speak('Speak your command.');
    if (!mounted) return;

    // Strict capture loop: Vosk is grammar-locked to the command vocabulary,
    // so anything outside "<verb> alert <number>" comes back as nothing.
    // Re-prompt once before failing so a single fluke (door slam, partial
    // word) doesn't drop the supervisor back to manual touch.
    VoiceCommandCapture? capture;
    VoiceCommand? command;
    for (var attempt = 0; attempt < 2; attempt++) {
      capture = await VoiceService.instance.captureCommandWithAudio(
        timeout: const Duration(seconds: 6),
        sampleRate: 16000,
      );
      if (!mounted) return;

      command = VoiceCommandParser.parseCanonical(capture.transcripts);
      if (_isCompleteActionCommand(command)) break;

      if (attempt == 0) {
        _setStep(
          _Step.awaitingCommand,
          status: 'I did not catch that — say it again',
          hint: 'Say "Claim alert" then the number, e.g. "Claim alert 1025"',
        );
        await VoiceService.instance.speak(
          'Please say the full command, like claim alert 1025.',
        );
        if (!mounted) return;
      }
    }

    if (capture == null ||
        command == null ||
        !_isCompleteActionCommand(command)) {
      _finish(
        success: false,
        message: (capture?.transcript ?? '').trim().isEmpty
            ? 'I did not hear a command.'
            : 'Unrecognized command: "${capture!.transcript}"',
        speak:
            'I did not understand. Say the full command, like claim alert 1025.',
      );
      return;
    }

    _setStep(
      _Step.working,
      status: _workingStatus(command),
      hint: 'Alert #${command.alertNumber}',
    );

    final provider = context.read<AlertProvider>();
    final result = await VoiceCommandDispatcher(provider).execute(
      command,
      rawAudio: capture.rawAudio,
      rawAudioSampleRate: capture.sampleRate,
    );
    _finish(success: result.success, message: result.message, speak: '');
  }

  bool _isCompleteActionCommand(VoiceCommand command) {
    return command.alertNumber != null &&
        (command.intent == VoiceIntent.claim ||
            command.intent == VoiceIntent.resolve ||
            command.intent == VoiceIntent.escalate);
  }

  String _workingStatus(VoiceCommand command) {
    switch (command.intent) {
      case VoiceIntent.claim:
        return 'Claiming alert...';
      case VoiceIntent.resolve:
        return 'Resolving alert...';
      case VoiceIntent.escalate:
        return 'Escalating alert...';
      default:
        return 'Running command...';
    }
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
    final listening = _step == _Step.awaitingCommand;

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
                  Text(
                    'Voice command',
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _PulseIcon(active: listening, icon: iconData, color: iconColor),
              const SizedBox(height: 36),
              Text(
                _statusLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
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
                      borderRadius: BorderRadius.circular(10),
                    ),
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

  const _PulseIcon({
    required this.active,
    required this.icon,
    required this.color,
  });

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final v = widget.active ? _controller.value : 0.0;
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

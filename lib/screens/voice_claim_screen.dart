// Full-screen voice flow opened from notification actions.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:provider/provider.dart';

import '../providers/alert_provider.dart';
import '../services/voice_auth_service.dart';
import '../services/voice_command_dispatcher.dart';
import '../services/voice_command_parser.dart';
import '../services/voice_service.dart';
import '../theme.dart';

class VoiceClaimScreen extends StatefulWidget {
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
    unawaited(VoiceService.instance.init());
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
      await _finish(
        success: false,
        message: VoiceCommandDispatcher.unrecognizedVoice,
        speak: true,
      );
      return;
    }

    if (VoiceService.instance.requiresVoiceEnrollment) {
      final state = await VoiceAuthService.instance.enrollmentState();
      if (state != VoiceEnrollmentState.enrolled) {
        await _finish(
          success: false,
          message: VoiceCommandDispatcher.enrollVoice,
          speak: true,
        );
        return;
      }
    }

    _setStep(
      _Step.awaitingCommand,
      status: 'Speak your command',
      hint:
          'Claim alert number, resolve alert, suspend alert, or mark critical',
    );

    VoiceCommandCapture? capture;
    for (var attempt = 0; attempt < 2; attempt++) {
      capture = await VoiceService.instance.captureCommandWithAudio(
        timeout: const Duration(seconds: 6),
        sampleRate: 16000,
      );
      if (!mounted) return;

      if (_hasTranscript(capture)) break;
    }

    if (capture == null || !_hasTranscript(capture)) {
      await _finish(
        success: false,
        message: VoiceCommandDispatcher.noCommandHeard,
        speak: true,
      );
      return;
    }

    final transcripts = capture.transcripts.toList();
    var command = VoiceCommandParser.parseBest(transcripts);
    if (!mounted) return;
    final provider = context.read<AlertProvider>();
    for (
      var attempt = 0;
      attempt < 2 && _needsClaimContinuation(command, provider);
      attempt++
    ) {
      _setStep(
        _Step.awaitingCommand,
        status: 'Speak your command',
        hint: 'Claim alert number',
      );
      final numberCapture = await VoiceService.instance.captureCommandWithAudio(
        timeout: const Duration(seconds: 5),
        sampleRate: 16000,
      );
      if (!mounted) return;
      if (!_hasTranscript(numberCapture)) break;
      _appendClaimNumberAttempt(transcripts, command, numberCapture);
      command = VoiceCommandParser.parseBest(transcripts);
    }

    if (_isActionCommand(command)) {
      _setStep(
        _Step.working,
        status: _workingStatus(command),
        hint: _workingHint(command),
      );
    } else {
      _setStep(_Step.working, status: 'Running command...', hint: '');
    }

    if (!mounted) return;
    final result = await VoiceCommandDispatcher(provider).execute(
      command,
      rawAudio: capture.rawAudio,
      rawAudioSampleRate: capture.sampleRate,
      voiceAlreadyVerified: true,
      fallbackAlertId: widget.alertId,
    );
    await _finish(success: result.success, message: result.message);
  }

  bool _hasTranscript(VoiceCommandCapture capture) {
    return capture.transcript.trim().isNotEmpty ||
        capture.alternatives.any((text) => text.trim().isNotEmpty);
  }

  bool _needsClaimContinuation(VoiceCommand command, AlertProvider provider) {
    if (command.intent != VoiceIntent.claim) return false;
    final number = command.alertNumber;
    if (number == null) return true;
    if (VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(command)) {
      return true;
    }

    final spoken = number.toString();
    var longerPrefixMatch = false;
    for (final alert in provider.allAlerts) {
      final candidate = alert.alertNumber.toString();
      if (candidate != spoken && candidate.startsWith(spoken)) {
        longerPrefixMatch = true;
      }
    }
    return longerPrefixMatch;
  }

  void _appendClaimNumberAttempt(
    List<String> transcripts,
    VoiceCommand partialClaim,
    VoiceCommandCapture numberCapture,
  ) {
    final numberParts = numberCapture.transcripts.toList();
    final base = partialClaim.rawText.trim();
    final merged = <String>[];
    if (base.isNotEmpty) {
      for (final part in numberParts) {
        final text = part.trim();
        if (text.isNotEmpty) merged.add('$base $text');
      }
    }
    transcripts
      ..insertAll(0, merged)
      ..addAll(numberParts);
  }

  bool _isActionCommand(VoiceCommand command) {
    return command.intent == VoiceIntent.claim ||
        command.intent == VoiceIntent.resolve ||
        command.intent == VoiceIntent.suspend ||
        command.intent == VoiceIntent.escalate;
  }

  String _workingHint(VoiceCommand command) {
    final number = command.alertNumber;
    if (number != null) return 'Alert #$number';
    if (command.intent == VoiceIntent.claim) return 'Alert number required';
    return 'Current claimed alert';
  }

  String _workingStatus(VoiceCommand command) {
    switch (command.intent) {
      case VoiceIntent.claim:
        return 'Claiming alert...';
      case VoiceIntent.resolve:
        return 'Resolving alert...';
      case VoiceIntent.suspend:
        return 'Suspending alert...';
      case VoiceIntent.escalate:
        return 'Marking critical...';
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

  Future<void> _finish({
    required bool success,
    required String message,
    bool speak = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _step = _Step.done;
      _statusLine = message;
      _success = success;
      _hint = '';
    });
    if (speak) await VoiceService.instance.speak(message);
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

// Floating microphone button with a pulse animation while listening.
// Drop it into a Stack/Positioned on any screen to enable voice commands.
//
// Behavior:
//   tap -> request mic, listen for one short command window, parse,
//   optionally ask for a missing alert number, then dispatch.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/alert_provider.dart';
import '../screens/voice_enrollment_screen.dart';
import '../services/voice_auth_service.dart';
import '../services/voice_command_dispatcher.dart';
import '../services/voice_command_parser.dart';
import '../services/voice_service.dart';
import '../theme.dart';

class VoiceCommandButton extends StatefulWidget {
  final Duration listenDuration;
  const VoiceCommandButton({
    super.key,
    this.listenDuration = const Duration(seconds: 5),
  });

  @override
  State<VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

class _VoiceCommandButtonState extends State<VoiceCommandButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _listening = false;
  bool _shownEnrollmentHint = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Warm the recognizer up the moment the FAB mounts so the first tap
    // starts listening with no perceptible delay. init() is idempotent.
    unawaited(VoiceService.instance.init());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    // Make sure the voice service is fully initialized
    await VoiceService.instance.init();

    if (!VoiceService.instance.isAvailable) {
      final err = VoiceService.instance.lastError ?? 'Unknown error';
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Voice unavailable'),
            content: SelectableText(
              'The speech model could not be loaded.\n\n$err',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (_listening) {
      await VoiceService.instance.stopListening();
      _stopUi();
      return;
    }

    final enrollState = await VoiceAuthService.instance.enrollmentState();
    if (enrollState != VoiceEnrollmentState.enrolled) {
      await _maybeSuggestEnrollment();
      await VoiceService.instance.speak('Please enroll your voice first.');
      return;
    }

    final provider = context.read<AlertProvider>();
    final dispatcher = VoiceCommandDispatcher(provider);

    setState(() => _listening = true);
    _pulse.repeat(reverse: true);

    final capture = await VoiceService.instance.captureCommandWithAudio(
      timeout: widget.listenDuration,
      sampleRate: 16000,
    );
    _stopUi();
    if (!mounted) return;

    if (capture.transcript.trim().isEmpty && capture.alternatives.isEmpty) {
      await VoiceService.instance.speak(
        'I did not hear anything. Please tap the mic and try again.',
      );
      return;
    }

    // Action commands require a fresh voice sample that matches enrollment.
    final pcm = capture.rawAudio ??
        await VoiceService.instance.captureRawAudio(
          duration: const Duration(milliseconds: 1600),
        );
    if (pcm == null || pcm.lengthInBytes <= 1600) {
      await VoiceService.instance.speak(
        'I could not capture your voice sample. Please try again.',
      );
      return;
    }

    final auth = await VoiceAuthService.instance.verifyCurrentUser(
      rawAudio: pcm,
      sampleRate: capture.sampleRate,
    );
    if (!auth.verified) {
      await VoiceService.instance.speak(_authFailureMessage(auth));
      return;
    }

    final cmd = VoiceCommandParser.parseBest(capture.transcripts);
    await dispatcher.execute(cmd, voiceAlreadyVerified: true);
  }

  Future<VoiceEnrollmentState> _maybeSuggestEnrollment() async {
    final state = await VoiceAuthService.instance.enrollmentState();
    if (!mounted ||
        _shownEnrollmentHint ||
        state != VoiceEnrollmentState.unenrolled) {
      return state;
    }
    _shownEnrollmentHint = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'Enroll your voice before using biometric voice commands.'),
        action: SnackBarAction(
          label: 'Enroll',
          onPressed: _openEnrollment,
        ),
      ),
    );
    return state;
  }

  void _openEnrollment() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VoiceEnrollmentScreen()),
    );
  }

  void _stopUi() {
    if (!mounted) return;
    setState(() => _listening = false);
    _pulse.stop();
    _pulse.reset();
  }

  String _authFailureMessage(VoiceVerificationResult auth) {
    if (auth.unenrolled) return 'Please enroll your voice first.';
    final message = auth.message ?? '';
    if (message.contains('No audio sample')) {
      return 'I could not capture your voice sample. Please try again.';
    }
    return 'Voice not recognized';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final size = 56.0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // 0..1 → ring opacity & scale.
        final v = _listening ? _pulse.value : 0.0;
        final ringSize = size + (28 * v);

        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_listening)
                Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.red.withValues(alpha: 0.18 * (1 - v)),
                  ),
                ),
              Material(
                color: _listening ? t.red : t.navy,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggle,
                  onLongPress: _openEnrollment,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Icon(
                      _listening ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

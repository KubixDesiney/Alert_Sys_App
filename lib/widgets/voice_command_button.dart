// Floating microphone button with a pulse animation while listening.
// Drop it into a Stack/Positioned on any screen to enable voice commands.
//
// Behavior:
//   tap -> request mic, listen for one short command window, parse,
//   optionally ask for a missing alert number, then dispatch.

import 'dart:async';
import 'dart:typed_data';
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
  StreamSubscription<String>? _commandSub;
  bool _listening = false;
  bool _shownEnrollmentHint = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _commandSub?.cancel();
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

    final provider = context.read<AlertProvider>();
    final dispatcher = VoiceCommandDispatcher(provider);
    final enrollmentState = await _maybeSuggestEnrollment();

    setState(() => _listening = true);
    _pulse.repeat(reverse: true);

    await _commandSub?.cancel();
    _commandSub = VoiceService.instance.commandStream.listen((text) async {
      if (!_listening) return;
      _stopUi();
      await VoiceService.instance.stopListening();
      var cmd = VoiceCommandParser.parse(text);
      if (_needsAlertNumber(cmd)) {
        await VoiceService.instance.speak('What alert number?');
        if (!mounted) return;

        setState(() => _listening = true);
        _pulse.repeat(reverse: true);
        final numberText = await VoiceService.instance.captureOnce(
          timeout: const Duration(seconds: 4),
        );
        _stopUi();

        if (numberText.trim().isNotEmpty) {
          cmd = VoiceCommandParser.parse('${cmd.rawText} $numberText');
        }
      }
      final rawAudio = enrollmentState == VoiceEnrollmentState.enrolled
          ? await _captureVerificationSample()
          : null;
      await dispatcher.execute(cmd, rawAudio: rawAudio);
    });

    await VoiceService.instance.startListening(timeout: widget.listenDuration);

    Future.delayed(widget.listenDuration + const Duration(milliseconds: 900),
        () {
      if (mounted && _listening) _stopUi();
    });
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
            'Voice commands are available. Enroll your voice for biometric protection.'),
        action: SnackBarAction(
          label: 'Enroll',
          onPressed: _openEnrollment,
        ),
      ),
    );
    return state;
  }

  Future<Uint8List?> _captureVerificationSample() async {
    await VoiceService.instance.speak('Say your verification phrase.');
    if (!mounted) return null;
    setState(() => _listening = true);
    _pulse.repeat(reverse: true);
    final audio = await VoiceService.instance.captureRawAudio(
      duration: const Duration(milliseconds: 2200),
      sampleRate: 16000,
    );
    _stopUi();
    return audio;
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

  bool _needsAlertNumber(VoiceCommand cmd) {
    return cmd.alertNumber == null &&
        (cmd.intent == VoiceIntent.claim ||
            cmd.intent == VoiceIntent.resolve ||
            cmd.intent == VoiceIntent.escalate);
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

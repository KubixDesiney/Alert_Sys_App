// Floating microphone button for hands-free alert commands.
//
// Tap captures one speech_to_text command, then dispatches it through the
// narrow voice contract. Long-press opens Android voice enrollment.

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
    this.listenDuration = const Duration(seconds: 6),
  });

  @override
  State<VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

enum _ButtonState { idle, listening, working }

class _VoiceCommandButtonState extends State<VoiceCommandButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _commandInFlight = false;
  _ButtonState _state = _ButtonState.idle;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    unawaited(VoiceService.instance.init());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_commandInFlight) return;
    _commandInFlight = true;
    try {
      await VoiceService.instance.init();

      if (!VoiceService.instance.isAvailable) {
        await VoiceService.instance.speak(
          VoiceCommandDispatcher.unrecognizedVoice,
        );
        return;
      }

      if (VoiceService.instance.requiresVoiceEnrollment) {
        final state = await VoiceAuthService.instance.enrollmentState();
        if (state != VoiceEnrollmentState.enrolled) {
          await VoiceService.instance.speak(VoiceCommandDispatcher.enrollVoice);
          return;
        }
      }

      VoiceCommandCapture? capture;
      for (var attempt = 0; attempt < 2; attempt++) {
        _setState(_ButtonState.listening);
        capture = await VoiceService.instance.captureCommandWithAudio(
          timeout: widget.listenDuration,
          sampleRate: 16000,
        );
        if (!mounted) return;

        final heard =
            capture.transcript.trim().isNotEmpty ||
            capture.alternatives.any((text) => text.trim().isNotEmpty);
        if (heard) break;

        _setState(_ButtonState.idle);
        if (attempt == 1) {
          await VoiceService.instance.speak(
            VoiceCommandDispatcher.noCommandHeard,
          );
          return;
        }
      }

      final heard =
          capture != null &&
          (capture.transcript.trim().isNotEmpty ||
              capture.alternatives.any((text) => text.trim().isNotEmpty));
      if (!heard) {
        await VoiceService.instance.speak(
          VoiceCommandDispatcher.noCommandHeard,
        );
        return;
      }

      _setState(_ButtonState.working);
      if (!mounted) return;

      final provider = context.read<AlertProvider>();
      final transcripts = capture.transcripts.toList();
      var command = VoiceCommandParser.parseBest(transcripts);
      for (
        var attempt = 0;
        attempt < 2 && _needsClaimContinuation(command, provider);
        attempt++
      ) {
        _setState(_ButtonState.listening);
        final numberCapture = await VoiceService.instance
            .captureCommandWithAudio(
              timeout: const Duration(seconds: 5),
              sampleRate: 16000,
            );
        if (!mounted) return;
        if (!_hasTranscript(numberCapture)) break;
        _appendClaimNumberAttempt(transcripts, command, numberCapture);
        command = VoiceCommandParser.parseBest(transcripts);
        _setState(_ButtonState.working);
      }
      await VoiceCommandDispatcher(provider).execute(
        command,
        rawAudio: capture.rawAudio,
        rawAudioSampleRate: capture.sampleRate,
      );
    } finally {
      _commandInFlight = false;
      if (mounted) _setState(_ButtonState.idle);
    }
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

  void _openEnrollment() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VoiceEnrollmentScreen()));
  }

  void _setState(_ButtonState next) {
    if (!mounted) return;
    setState(() => _state = next);
    if (next == _ButtonState.listening) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    const size = 56.0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final listening = _state == _ButtonState.listening;
        final working = _state == _ButtonState.working;
        final v = listening ? _pulse.value : 0.0;
        final ringSize = size + (28 * v);

        Color buttonColor;
        IconData iconData;
        if (working) {
          buttonColor = t.navy;
          iconData = Icons.graphic_eq;
        } else if (listening) {
          buttonColor = t.red;
          iconData = Icons.mic;
        } else {
          buttonColor = t.navy;
          iconData = Icons.mic_none;
        }

        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (listening)
                Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.red.withValues(alpha: 0.18 * (1 - v)),
                  ),
                ),
              Material(
                color: buttonColor,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => unawaited(_handleTap()),
                  onLongPress: _openEnrollment,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: working
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Icon(iconData, color: Colors.white, size: 26),
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

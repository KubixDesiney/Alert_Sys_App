// Floating microphone button with a pulse animation while listening.
// Drop it into a Stack/Positioned on any screen to enable voice commands.
//
// Behavior:
//   tap → request mic, start Vosk listener for 5s, animate pulse,
//   on first final transcript → parse → dispatch → speak result.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/alert_provider.dart';
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
    if (_listening) {
      await VoiceService.instance.stopListening();
      _stopUi();
      return;
    }

    final provider = context.read<AlertProvider>();
    final dispatcher = VoiceCommandDispatcher(provider);

    // First-tap initialization can be slow (~1-2s) while Vosk loads the model.
    try {
      await VoiceService.instance.init();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice unavailable: $e')),
      );
      return;
    }

    setState(() => _listening = true);
    _pulse.repeat(reverse: true);

    // Subscribe BEFORE we start, so we don't miss a fast result.
    await _commandSub?.cancel();
    _commandSub = VoiceService.instance.commandStream.listen((text) async {
      // Auto-stop on first final result — a button-press session is one shot.
      if (!_listening) return;
      _stopUi();
      await VoiceService.instance.stopListening();
      final cmd = VoiceCommandParser.parse(text);
      await dispatcher.execute(cmd);
    });

    await VoiceService.instance.startListening(timeout: widget.listenDuration);

    // Belt-and-braces UI stop when Vosk's internal timeout fires.
    Future.delayed(widget.listenDuration + const Duration(milliseconds: 300),
        () {
      if (mounted && _listening) _stopUi();
    });
  }

  void _stopUi() {
    if (!mounted) return;
    setState(() => _listening = false);
    _pulse.stop();
    _pulse.reset();
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

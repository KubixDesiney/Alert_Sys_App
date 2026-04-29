// Push-to-talk voice service backed by native SpeechRecognizer/TTS on mobile.
// (and the OS-equivalent on iOS / Web Speech API on browsers) via
// the speech_to_text plugin. No background listening, no continuous
// capture — every listen window is started by an explicit call and
// auto-stops within [timeout].

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();
  static const MethodChannel _audioChannel = MethodChannel('alertsys/audio');

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  Timer? _listenCutoff;
  int _listenSession = 0;
  bool _initialized = false;
  bool _available = false;
  bool _listening = false;
  String? lastError;

  bool get isAvailable => _available;
  bool get isListening => _listening;
  Stream<String> get commandStream => _commandsController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onError: (e) {
          debugPrint('VoiceService onError: ${e.errorMsg}');
          lastError = e.errorMsg;
        },
        onStatus: (s) => debugPrint('VoiceService status: $s'),
        debugLogging: false,
        options: [
          stt.SpeechToText.androidAlwaysUseStop,
          stt.SpeechToText.androidNoBluetooth,
        ],
      );
      try {
        await _tts.setLanguage('en-US');
        await _tts.setSpeechRate(0.5);
        await _tts.setPitch(1.0);
        await _tts.awaitSpeakCompletion(true);
      } catch (e) {
        debugPrint('VoiceService TTS setup failed: $e');
      }
      if (!_available) {
        lastError ??= 'Speech recognition not available on this device';
      }
    } catch (e, st) {
      debugPrint('VoiceService.init failed: $e\n$st');
      _available = false;
      lastError = '$e';
    }
  }

  /// Push-to-talk style listener. Broadcasts the best transcript captured
  /// during [timeout]. Use this for the in-app FAB; for sequential prompts
  /// prefer [captureOnce], which awaits the result directly.
  Future<void> startListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_initialized) await init();
    if (!_available || _listening) return;

    if (!await _ensureMicPermission()) {
      await speak('Microphone permission is required.');
      return;
    }

    _listening = true;
    final session = ++_listenSession;
    String bestTranscript = '';
    var emitted = false;

    Future<void> finishListen() async {
      if (emitted || session != _listenSession) return;
      emitted = true;
      final text = bestTranscript.trim();
      if (text.isNotEmpty) {
        _commandsController.add(text);
      }
      await stopListening();
    }

    try {
      await _speech.listen(
        onResult: (r) {
          final text = r.recognizedWords.trim();
          if (text.isNotEmpty) {
            bestTranscript = text;
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(seconds: 4),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
      _listenCutoff?.cancel();
      _listenCutoff = Timer(
        timeout + const Duration(milliseconds: 200),
        () => unawaited(finishListen()),
      );
    } catch (e) {
      debugPrint('VoiceService.startListening: $e');
      _listening = false;
      await _releaseAndroidAudioSession();
    }
  }

  /// Capture exactly one finalized phrase. Returns empty string on
  /// timeout / no speech / permission denied. Designed for the
  /// notification-driven claim flow where steps are sequential.
  Future<String> captureOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_initialized) await init();
    if (!_available) return '';
    if (!await _ensureMicPermission()) return '';

    final completer = Completer<String>();
    _listening = true;
    Timer? cutoff;
    String bestTranscript = '';

    try {
      await _speech.listen(
        onResult: (r) {
          final text = r.recognizedWords.trim();
          if (text.isNotEmpty) {
            bestTranscript = text;
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(seconds: 4),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
      cutoff = Timer(timeout + const Duration(milliseconds: 600), () {
        if (!completer.isCompleted) {
          completer.complete(bestTranscript.trim());
        }
      });
      return await completer.future;
    } catch (e) {
      debugPrint('VoiceService.captureOnce: $e');
      return '';
    } finally {
      cutoff?.cancel();
      _listening = false;
      try {
        await _speech.stop();
      } catch (_) {}
      await _releaseAndroidAudioSession();
    }
  }

  Future<void> stopListening() async {
    _listenSession++;
    _listenCutoff?.cancel();
    _listenCutoff = null;
    if (!_listening) return;
    _listening = false;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('VoiceService.stopListening: $e');
    }
    await _releaseAndroidAudioSession();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text, focus: false);
    } catch (e) {
      debugPrint('VoiceService.speak: $e');
    } finally {
      await _releaseAndroidAudioSession();
    }
  }

  Future<void> dispose() async {
    await stopListening();
    await _commandsController.close();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<bool> _ensureMicPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('VoiceService permission error: $e');
      return false;
    }
  }

  Future<void> _releaseAndroidAudioSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _audioChannel.invokeMethod('releaseAudioSession');
    } catch (e) {
      debugPrint('VoiceService audio cleanup failed: $e');
    }
  }
}

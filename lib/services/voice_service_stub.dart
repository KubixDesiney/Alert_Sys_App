// Web stub – no Vosk, only TTS for spoken feedback.
// The microphone button will do nothing on web, but voice reply
// via push notification can still use platform speech-to-text.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final FlutterTts _tts = FlutterTts();
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();
  bool _initialized = false;

  Stream<String> get commandStream => _commandsController.stream;
  bool get isListening => false;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> startListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Not supported on web – voice commands via push notification still work
  }

  Future<void> stopListening() async {}

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('VoiceService.speak (web): $e');
    }
  }

  Future<void> dispose() async {
    await _commandsController.close();
    await _tts.stop();
  }
}

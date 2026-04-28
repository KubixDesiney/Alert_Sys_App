// Web stub – no native voice recognition, no TTS.
// The microphone button will do nothing on web, and TTS is silent.
// Voice reply via push notification still works because the platform
// handles speech‑to‑text on the keyboard's mic button.

import 'dart:async';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  bool _initialized = false;

  Stream<String> get commandStream => _commandsController.stream;
  bool get isListening => false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<void> startListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Not supported on web – voice commands via push notification still work
  }

  Future<void> stopListening() async {}

  Future<void> speak(String text) async {
    // TTS not available on web
  }

  Future<void> dispose() async {
    await _commandsController.close();
  }
}

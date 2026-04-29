import 'dart:async';

class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  String? lastError = 'Voice commands are not available on web.';

  bool get isAvailable => false;
  bool get isListening => false;
  Stream<String> get commandStream => _commandsController.stream;

  Future<void> init() async {
    lastError = 'Voice commands are not available on web.';
  }

  Future<void> startListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  Future<String> captureOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return '';
  }

  Future<void> stopListening() async {}

  Future<void> speak(String text) async {}

  Future<void> dispose() async {
    await _commandsController.close();
  }
}

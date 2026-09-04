import 'dart:async';
import 'dart:typed_data';

class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  String? lastError = 'Voice commands are not available on this platform.';

  bool get isAvailable => false;
  bool get isListening => false;
  bool get requiresVoiceEnrollment => false;

  /// No raw-audio source on this platform, so a spoken command can never be
  /// tied to a person here. The dispatcher refuses rather than run unverified.
  bool get supportsVoiceVerification => false;
  Stream<String> get commandStream => _commandsController.stream;

  Future<void> init() async {
    lastError = 'Voice commands are not available on this platform.';
  }

  Future<String> captureOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return '';
  }

  Future<VoiceCommandCapture> captureCommandWithAudio({
    Duration timeout = const Duration(seconds: 5),
    Duration endSilence = const Duration(milliseconds: 800),
    int sampleRate = 16000,
    bool forceLockScreen = false,
  }) async {
    return VoiceCommandCapture.empty(sampleRate: sampleRate);
  }

  Future<Uint8List?> captureRawAudio({
    Duration duration = const Duration(milliseconds: 1800),
    int sampleRate = 16000,
  }) async {
    return null;
  }

  Future<void> stopListening() async {}

  Future<void> speak(String text) async {}

  Future<void> dispose() async {
    await _commandsController.close();
  }
}

class VoiceCommandCapture {
  final String transcript;
  final List<String> alternatives;
  final Uint8List? rawAudio;
  final int sampleRate;
  final double confidence;
  final bool voiceAlreadyVerified;

  const VoiceCommandCapture({
    required this.transcript,
    this.alternatives = const <String>[],
    required this.rawAudio,
    required this.sampleRate,
    this.confidence = -1,
    this.voiceAlreadyVerified = false,
  });

  const VoiceCommandCapture.empty({
    required this.sampleRate,
    this.voiceAlreadyVerified = false,
  }) : transcript = '',
       alternatives = const <String>[],
       rawAudio = null,
       confidence = -1;

  Iterable<String> get transcripts sync* {
    if (transcript.trim().isNotEmpty) yield transcript.trim();
    for (final alternative in alternatives) {
      final text = alternative.trim();
      if (text.isNotEmpty) yield text;
    }
  }
}

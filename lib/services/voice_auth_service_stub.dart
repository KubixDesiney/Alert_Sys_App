import 'dart:typed_data';

enum VoiceEnrollmentState { enrolled, unenrolled, unavailable }

class VoiceVerificationResult {
  final bool verified;
  final bool unenrolled;
  final double? similarity;
  final String? message;

  const VoiceVerificationResult({
    required this.verified,
    required this.unenrolled,
    this.similarity,
    this.message,
  });
}

class VoiceAuthService {
  VoiceAuthService._();
  static final VoiceAuthService instance = VoiceAuthService._();

  static const double threshold = 0.88;

  Future<VoiceEnrollmentState> enrollmentState() async {
    return VoiceEnrollmentState.unavailable;
  }

  Future<VoiceVerificationResult> verifyCurrentUser({
    Uint8List? rawAudio,
    int sampleRate = 16000,
  }) async {
    return const VoiceVerificationResult(
      verified: false,
      unenrolled: true,
      message: 'Voice biometrics are unavailable on this platform.',
    );
  }

  Future<List<double>> extractEmbedding(
    Uint8List rawAudio, {
    int sampleRate = 16000,
  }) async {
    return const <double>[];
  }

  Future<void> enrollCurrentUser(List<List<double>> embeddings) async {}

  Future<void> preload() async {}
}

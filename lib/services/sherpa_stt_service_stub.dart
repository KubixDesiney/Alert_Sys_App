import 'dart:typed_data';

class SherpaSttService {
  SherpaSttService._();
  static final SherpaSttService instance = SherpaSttService._();

  bool get isReady => false;

  Future<bool> ensureReady() async => false;

  Future<String> transcribe(Uint8List pcmBytes, {int sampleRate = 16000}) async => '';

  void dispose() {}
}

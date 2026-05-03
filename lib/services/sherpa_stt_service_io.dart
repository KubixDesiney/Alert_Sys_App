// Offline speech-to-text backed by sherpa_onnx v1.13 (k2-fsa streaming Zipformer).
//
// Why sherpa_onnx instead of Vosk or the speech_to_text plugin:
//   - Ships as a standard pub package (no Maven AAR, no JNA, no custom Kotlin)
//   - Streaming Zipformer transducer (~17 MB int8) has ~30 % lower WER than
//     Vosk small-en on LibriSpeech and handles command + digit utterances in
//     factory noise far better than Android's SpeechRecognizer
//   - Runs fully offline after the one-time first-launch download
//   - Dart-side transcription = no Android-version-specific STT quirks
//
// Model: sherpa-onnx-streaming-zipformer-en-2023-06-26 (~17 MB, int8 quantised)
// Downloaded once to getApplicationDocumentsDirectory() on first init.
//
// API notes (v1.13.0):
//   - OnlineModelConfig uses `transducer: OnlineTransducerModelConfig(...)` +
//     `modelType: 'zipformer2'` — there is no separate `zipformer2` field.
//   - `inputFinished()` lives on OnlineStream, not OnlineRecognizer.

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SherpaSttService {
  SherpaSttService._();
  static final SherpaSttService instance = SherpaSttService._();

  static const _modelDirName =
      'sherpa-onnx-streaming-zipformer-en-2023-06-26';
  static const _downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'asr-models/sherpa-onnx-streaming-zipformer-en-2023-06-26.tar.bz2';

  sherpa.OnlineRecognizer? _recognizer;
  Future<bool>? _initFuture;

  bool get isReady => _recognizer != null;

  Future<bool> ensureReady() => _initFuture ??= _init();

  Future<bool> _init() async {
    try {
      sherpa.initBindings();
      final modelPath = await _ensureModel();
      if (modelPath == null) return false;

      // Probe the extracted directory — file names vary across model releases
      // so we match by role rather than hardcoding exact names.
      final encoder = _findFile(modelPath, 'encoder');
      final decoder = _findFile(modelPath, 'decoder');
      final joiner = _findFile(modelPath, 'joiner');
      final tokens = File('$modelPath/tokens.txt');

      if (encoder == null || decoder == null || joiner == null ||
          !tokens.existsSync()) {
        debugPrint('SherpaStt: incomplete model in $modelPath — '
            'encoder=$encoder decoder=$decoder joiner=$joiner '
            'tokens=${tokens.existsSync()}');
        return false;
      }

      final config = sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner,
          ),
          tokens: tokens.path,
          // 'zipformer2' tells the runtime which graph topology to use.
          modelType: 'zipformer2',
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
        decodingMethod: 'greedy_search',
        maxActivePaths: 4,
        enableEndpoint: true,
        // Trailing-silence rules tuned for factory push-to-talk:
        // rule2 at 1.0 s catches a natural pause after "...one zero two five"
        // without cutting off the number itself.
        rule1MinTrailingSilence: 2.4,
        rule2MinTrailingSilence: 1.0,
        rule3MinUtteranceLength: 20.0,
      );

      _recognizer = sherpa.OnlineRecognizer(config);
      debugPrint('SherpaStt: ready (encoder=$encoder)');
      return true;
    } catch (e, st) {
      debugPrint('SherpaStt._init failed: $e\n$st');
      return false;
    }
  }

  /// Transcribe a complete push-to-talk utterance from raw 16-bit PCM bytes.
  /// Returns the trimmed, lowercased transcript or empty string on failure.
  Future<String> transcribe(Uint8List pcmBytes,
      {int sampleRate = 16000}) async {
    final rec = _recognizer;
    if (rec == null || pcmBytes.length < 640) return '';

    try {
      final samples = _pcm16ToFloat32(pcmBytes);
      final stream = rec.createStream();
      // Feed all audio, then mark end-of-input on the *stream* (not recognizer).
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      stream.inputFinished();
      while (rec.isReady(stream)) {
        rec.decode(stream);
      }
      final text = rec.getResult(stream).text.trim().toLowerCase();
      stream.free();
      return text;
    } catch (e) {
      debugPrint('SherpaStt.transcribe: $e');
      return '';
    }
  }

  void dispose() {
    try {
      _recognizer?.free();
    } catch (_) {}
    _recognizer = null;
    _initFuture = null;
  }

  // ---------------------------------------------------------------------------
  // Model management
  // ---------------------------------------------------------------------------

  Future<String?> _ensureModel() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_modelDirName');
    final marker = File('${dir.path}/tokens.txt');

    if (marker.existsSync()) {
      debugPrint('SherpaStt: model cached at ${dir.path}');
      return dir.path;
    }

    debugPrint('SherpaStt: downloading model from $_downloadUrl');
    try {
      final response = await http
          .get(Uri.parse(_downloadUrl))
          .timeout(const Duration(minutes: 4));
      if (response.statusCode != 200) {
        debugPrint('SherpaStt: HTTP ${response.statusCode}');
        return null;
      }
      debugPrint(
          'SherpaStt: extracting ${response.bodyBytes.length ~/ 1024} KB');
      await Isolate.run(
          () => _extractTarBz2(response.bodyBytes, docs.path));
      if (!marker.existsSync()) {
        debugPrint('SherpaStt: tokens.txt missing after extraction');
        return null;
      }
      debugPrint('SherpaStt: model ready at ${dir.path}');
      return dir.path;
    } catch (e) {
      debugPrint('SherpaStt: model setup failed: $e');
      return null;
    }
  }

  /// Finds the first `.onnx` file in [dir] whose name contains [role]
  /// (case-insensitive). Prefers int8-quantised variants.
  static String? _findFile(String dir, String role) {
    final entries = Directory(dir).listSync();
    final candidates = entries
        .whereType<File>()
        .where((f) =>
            f.path.toLowerCase().contains(role) &&
            f.path.toLowerCase().endsWith('.onnx'))
        .toList();
    if (candidates.isEmpty) return null;
    // Prefer int8 for smaller memory footprint on embedded devices.
    final int8 =
        candidates.where((f) => f.path.contains('int8')).toList();
    return (int8.isNotEmpty ? int8.first : candidates.first).path;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    final out = Float32List(count);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < count; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}

// Top-level so Isolate.run can reach it. Decompresses a tar.bz2 blob and
// writes each entry under [destDir].
void _extractTarBz2(Uint8List compressedBytes, String destDir) {
  final decompressed = BZip2Decoder().decodeBytes(compressedBytes);
  final archive = TarDecoder().decodeBytes(decompressed);
  for (final entry in archive.files) {
    final outPath = '$destDir/${entry.name}';
    if (entry.isFile) {
      final file = File(outPath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.content as List<int>);
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
}

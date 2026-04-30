import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:tflite_flutter/tflite_flutter.dart';

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
  static const String _modelAsset =
      'assets/models/conformer_tisid_small.tflite';

  Interpreter? _interpreter;
  Future<void>? _loadFuture;

  Future<VoiceEnrollmentState> enrollmentState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return VoiceEnrollmentState.unavailable;
    final enrolled = await _loadVoiceprint(uid);
    return enrolled == null || enrolled.isEmpty
        ? VoiceEnrollmentState.unenrolled
        : VoiceEnrollmentState.enrolled;
  }

  Future<VoiceVerificationResult> verifyCurrentUser({
    Uint8List? rawAudio,
    int sampleRate = 16000,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const VoiceVerificationResult(
        verified: false,
        unenrolled: false,
        message: 'No signed-in user.',
      );
    }

    final enrolled = await _loadVoiceprint(uid);
    if (enrolled == null || enrolled.isEmpty) {
      return const VoiceVerificationResult(
        verified: false,
        unenrolled: true,
        message: 'No enrolled voiceprint. Voice verification is required.',
      );
    }

    if (rawAudio == null || rawAudio.lengthInBytes < 1600) {
      return const VoiceVerificationResult(
        verified: false,
        unenrolled: false,
        message: 'No audio sample captured for voice verification.',
      );
    }

    try {
      final embedding =
          await extractEmbedding(rawAudio, sampleRate: sampleRate);
      final similarity = cosineSimilarity(enrolled, embedding);
      return VoiceVerificationResult(
        verified: similarity >= threshold,
        unenrolled: false,
        similarity: similarity,
      );
    } catch (e, st) {
      debugPrint('VoiceAuthService.verifyCurrentUser failed: $e\n$st');
      return VoiceVerificationResult(
        verified: false,
        unenrolled: false,
        message: e.toString(),
      );
    }
  }

  Future<List<double>> extractEmbedding(
    Uint8List rawAudio, {
    int sampleRate = 16000,
  }) async {
    await _ensureModelLoaded();
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Speaker embedding model is not loaded.');
    }

    final samples = _pcm16BytesToDoubles(rawAudio);
    final normalizedSamples = sampleRate == 16000
        ? samples
        : _resampleLinear(samples, sampleRate, 16000);
    final features = _buildStackedMelFeatures(normalizedSamples);
    if (features.isEmpty) {
      throw StateError('Not enough speech audio for voice verification.');
    }

    final inputs = interpreter.getInputTensors();
    final outputs = interpreter.getOutputTensors();
    if (inputs.isEmpty || outputs.isEmpty) {
      throw StateError('Speaker model has no inputs or outputs.');
    }

    final firstShape = inputs.first.shape;
    final batchSize = firstShape.length >= 2 ? firstShape.first : 1;
    final featureWidth = firstShape.isNotEmpty ? firstShape.last : 512;
    final modelFeatures = _fitFeatureWidth(features, featureWidth);

    var states = <Object>[
      for (var i = 1; i < inputs.length; i++) _zeroTensorBuffer(inputs[i]),
    ];
    var lastOutput = <double>[];
    final usableFrameCount =
        modelFeatures.length - (modelFeatures.length % batchSize);
    final frameCount = usableFrameCount <= 0 ? batchSize : usableFrameCount;

    for (var start = 0; start < frameCount; start += batchSize) {
      final chunk = <List<double>>[];
      for (var i = 0; i < batchSize; i++) {
        final index = math.min(start + i, modelFeatures.length - 1);
        chunk.add(modelFeatures[index]);
      }

      final outputMap = <int, Object>{
        for (var i = 0; i < outputs.length; i++)
          i: _zeroTensorBuffer(outputs[i]),
      };
      interpreter.runForMultipleInputs(
        [_float32BufferForFeatures(chunk, inputs[0]), ...states],
        outputMap,
      );
      lastOutput = _lastOutputVectorFromBuffer(outputMap[0], outputs[0].shape);
      states = [
        for (var i = 1; i < outputs.length; i++) outputMap[i]!,
      ];
    }

    if (lastOutput.isEmpty) {
      throw StateError('Speaker model returned an empty embedding.');
    }
    return l2Normalize(lastOutput);
  }

  Future<void> enrollCurrentUser(List<List<double>> embeddings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('You must be signed in to enroll a voiceprint.');
    }
    if (embeddings.length < 3) {
      throw ArgumentError('Voice enrollment requires 3 samples.');
    }

    final averaged = averageEmbeddings(embeddings);
    await FirebaseDatabase.instance.ref('users/$uid/voiceprint').set({
      'embedding': averaged,
      'threshold': threshold,
      'model': 'tflite-hub/conformer-speaker-encoder/conformer_tisid_small',
      'sampleCount': embeddings.length,
      'updatedAt': ServerValue.timestamp,
    });
  }

  static List<double> averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return const <double>[];
    final width = embeddings.first.length;
    final sum = List<double>.filled(width, 0);
    var count = 0;
    for (final embedding in embeddings) {
      if (embedding.length != width) continue;
      final normalized = l2Normalize(embedding);
      for (var i = 0; i < width; i++) {
        sum[i] += normalized[i];
      }
      count++;
    }
    if (count == 0) return const <double>[];
    return l2Normalize(sum.map((v) => v / count).toList(growable: false));
  }

  static List<double> l2Normalize(List<double> values) {
    var sumSquares = 0.0;
    for (final value in values) {
      sumSquares += value * value;
    }
    if (sumSquares <= 0) return List<double>.from(values);
    final norm = math.sqrt(sumSquares);
    return values.map((value) => value / norm).toList(growable: false);
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    if (n == 0) return -1;
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na <= 0 || nb <= 0) return -1;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// Warms up the TFLite model so the first verification call is fast.
  Future<void> preload() => _ensureModelLoaded();

  Future<void> _ensureModelLoaded() {
    final existing = _loadFuture;
    if (existing != null) return existing;
    return _loadFuture = () async {
      _interpreter ??= await Interpreter.fromAsset(_modelAsset);
    }();
  }

  Future<List<double>?> _loadVoiceprint(String uid) async {
    final snapshot = await FirebaseDatabase.instance
        .ref('users/$uid/voiceprint/embedding')
        .get();
    if (!snapshot.exists || snapshot.value == null) return null;
    return _numbersFromFirebaseValue(snapshot.value);
  }

  List<double> _numbersFromFirebaseValue(Object? value) {
    if (value is List) {
      return value
          .whereType<num>()
          .map((v) => v.toDouble())
          .toList(growable: false);
    }
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return entries
          .map((e) => e.value)
          .whereType<num>()
          .map((v) => v.toDouble())
          .toList(growable: false);
    }
    return const <double>[];
  }

  List<double> _pcm16BytesToDoubles(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final samples = <double>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      samples.add(data.getInt16(i, Endian.little) / 32768.0);
    }
    return samples;
  }

  List<double> _resampleLinear(
    List<double> samples,
    int sourceRate,
    int targetRate,
  ) {
    if (samples.isEmpty || sourceRate <= 0 || sourceRate == targetRate) {
      return samples;
    }
    final outputLength = (samples.length * targetRate / sourceRate).round();
    if (outputLength <= 1) return samples;
    final ratio = sourceRate / targetRate;
    return List<double>.generate(outputLength, (i) {
      final src = i * ratio;
      final left = src.floor().clamp(0, samples.length - 1);
      final right = (left + 1).clamp(0, samples.length - 1);
      final frac = src - left;
      return samples[left] * (1 - frac) + samples[right] * frac;
    }, growable: false);
  }

  List<List<double>> _buildStackedMelFeatures(List<double> samples) {
    const sampleRate = 16000;
    const frameSize = 512;
    const hopSize = 480;
    const melBins = 128;
    const lowerHz = 125.0;
    const upperHz = 7500.0;
    if (samples.length < frameSize) return const <List<double>>[];

    final preemphasized = List<double>.filled(samples.length, 0);
    preemphasized[0] = samples[0];
    for (var i = 1; i < samples.length; i++) {
      preemphasized[i] = samples[i] - 0.97 * samples[i - 1];
    }

    final filters =
        _melFilterBank(melBins, frameSize, sampleRate, lowerHz, upperHz);
    final bins = <List<double>>[];
    for (var start = 0;
        start + frameSize <= preemphasized.length;
        start += hopSize) {
      final frame = preemphasized.sublist(start, start + frameSize);
      for (var i = 0; i < frame.length; i++) {
        frame[i] *= 0.5 - 0.5 * math.cos(2 * math.pi * i / (frame.length - 1));
      }
      final power = _powerSpectrum(frame);
      final mel = List<double>.filled(melBins, 0);
      for (var m = 0; m < melBins; m++) {
        var energy = 0.0;
        final filter = filters[m];
        for (var k = 0; k < filter.length; k++) {
          energy += power[k] * filter[k];
        }
        mel[m] = math.log(math.max(energy, 1e-6));
      }
      bins.add(mel);
    }

    if (bins.isEmpty) return const <List<double>>[];
    final stacked = <List<double>>[];
    for (var i = 0; i < bins.length; i += 3) {
      final row = <double>[];
      for (var context = 3; context >= 0; context--) {
        row.addAll(bins[math.max(0, i - context)]);
      }
      stacked.add(row);
    }
    return stacked;
  }

  List<List<double>> _fitFeatureWidth(List<List<double>> features, int width) {
    if (features.isEmpty) return features;
    return features.map((row) {
      if (row.length == width) return row;
      if (row.length > width) return row.sublist(0, width);
      return <double>[...row, ...List<double>.filled(width - row.length, 0)];
    }).toList(growable: false);
  }

  List<List<double>> _melFilterBank(
    int melBins,
    int fftSize,
    int sampleRate,
    double lowerHz,
    double upperHz,
  ) {
    final spectrumBins = fftSize ~/ 2 + 1;
    final lowerMel = _hzToMel(lowerHz);
    final upperMel = _hzToMel(upperHz);
    final melPoints = List<double>.generate(
      melBins + 2,
      (i) => lowerMel + (upperMel - lowerMel) * i / (melBins + 1),
      growable: false,
    );
    final hzPoints = melPoints.map(_melToHz).toList(growable: false);
    final binPoints = hzPoints
        .map((hz) => ((fftSize + 1) * hz / sampleRate).floor())
        .map((bin) => bin.clamp(0, spectrumBins - 1))
        .toList(growable: false);

    return List<List<double>>.generate(melBins, (m) {
      final filter = List<double>.filled(spectrumBins, 0);
      final left = binPoints[m];
      final center = math.max(binPoints[m + 1], left + 1);
      final right = math.max(binPoints[m + 2], center + 1);
      for (var k = left; k < center && k < spectrumBins; k++) {
        filter[k] = (k - left) / (center - left);
      }
      for (var k = center; k < right && k < spectrumBins; k++) {
        filter[k] = (right - k) / (right - center);
      }
      return filter;
    }, growable: false);
  }

  List<double> _powerSpectrum(List<double> frame) {
    final n = frame.length;
    final bins = n ~/ 2 + 1;
    final result = List<double>.filled(bins, 0);
    for (var k = 0; k < bins; k++) {
      var real = 0.0;
      var imag = 0.0;
      for (var t = 0; t < n; t++) {
        final angle = -2 * math.pi * k * t / n;
        real += frame[t] * math.cos(angle);
        imag += frame[t] * math.sin(angle);
      }
      result[k] = real * real + imag * imag;
    }
    return result;
  }

  double _hzToMel(double hz) => 2595.0 * math.log(1 + hz / 700.0) / math.ln10;
  double _melToHz(double mel) => 700.0 * (math.pow(10, mel / 2595.0) - 1);

  ByteBuffer _zeroTensorBuffer(Tensor tensor) {
    return Uint8List(tensor.numBytes()).buffer;
  }

  ByteBuffer _float32BufferForFeatures(
    List<List<double>> features,
    Tensor tensor,
  ) {
    final bytes = Uint8List(tensor.numBytes());
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    for (final row in features) {
      for (final value in row) {
        if (offset + 4 > bytes.length) return bytes.buffer;
        data.setFloat32(offset, value, Endian.little);
        offset += 4;
      }
    }
    return bytes.buffer;
  }

  List<double> _flattenDoubles(Object? value) {
    final out = <double>[];
    void walk(Object? node) {
      if (node is num) {
        out.add(node.toDouble());
      } else if (node is Iterable) {
        for (final child in node) {
          walk(child);
        }
      }
    }

    walk(value);
    return out;
  }

  List<double> _lastOutputVectorFromBuffer(Object? value, List<int> shape) {
    if (value is! ByteBuffer) return _lastOutputVector(value, shape);
    final data = ByteData.view(value);
    final flattened = <double>[];
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      flattened.add(data.getFloat32(i, Endian.little));
    }
    return _sliceLastOutputVector(flattened, shape);
  }

  List<double> _lastOutputVector(Object? value, List<int> shape) {
    return _sliceLastOutputVector(_flattenDoubles(value), shape);
  }

  List<double> _sliceLastOutputVector(List<double> flattened, List<int> shape) {
    if (flattened.isEmpty || shape.length < 2 || shape.first <= 1) {
      return flattened;
    }
    final rows = shape.first;
    if (flattened.length % rows != 0) return flattened;
    final width = flattened.length ~/ rows;
    return flattened.sublist(flattened.length - width);
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'lstm_types.dart';

/// A real, dependency-free LSTM implemented in pure Dart.
///
/// Architecture: single LSTM layer followed by a dense sigmoid head for
/// multi-label classification (one output per canonical alert type).
/// Training is genuine gradient descent: full backpropagation through time
/// with an Adam optimizer, gradient clipping, and weighted binary
/// cross-entropy for class imbalance. Nothing here is simulated — the loss
/// curves shown in the SuperAdmin console come straight from these updates.
class LstmNetwork {
  final int inputSize;
  final int hiddenSize;
  final int outputSize;

  /// Combined gate weights, rows ordered [input, forget, candidate, output].
  /// Shape: (4*hidden) x (input + hidden).
  late Float64List _w;
  late Float64List _b; // 4*hidden
  late Float64List _wy; // output x hidden
  late Float64List _by; // output

  // Adam moments.
  late Float64List _mW, _vW, _mB, _vB, _mWy, _vWy, _mBy, _vBy;
  int _adamStep = 0;

  static const double _beta1 = 0.9;
  static const double _beta2 = 0.999;
  static const double _eps = 1e-8;
  static const double _clipNorm = 1.0;

  LstmNetwork({
    required this.inputSize,
    required this.hiddenSize,
    required this.outputSize,
    int seed = 42,
  }) {
    final rng = math.Random(seed);
    final cols = inputSize + hiddenSize;
    final scale = math.sqrt(6.0 / (cols + hiddenSize));
    _w = Float64List(4 * hiddenSize * cols);
    for (var i = 0; i < _w.length; i++) {
      _w[i] = (rng.nextDouble() * 2 - 1) * scale;
    }
    _b = Float64List(4 * hiddenSize);
    // Forget-gate bias starts at 1.0 so early training preserves memory.
    for (var i = hiddenSize; i < 2 * hiddenSize; i++) {
      _b[i] = 1.0;
    }
    final yScale = math.sqrt(6.0 / (hiddenSize + outputSize));
    _wy = Float64List(outputSize * hiddenSize);
    for (var i = 0; i < _wy.length; i++) {
      _wy[i] = (rng.nextDouble() * 2 - 1) * yScale;
    }
    _by = Float64List(outputSize);
    _initMoments();
  }

  LstmNetwork._raw(this.inputSize, this.hiddenSize, this.outputSize) {
    final cols = inputSize + hiddenSize;
    _w = Float64List(4 * hiddenSize * cols);
    _b = Float64List(4 * hiddenSize);
    _wy = Float64List(outputSize * hiddenSize);
    _by = Float64List(outputSize);
    _initMoments();
  }

  void _initMoments() {
    final cols = inputSize + hiddenSize;
    _mW = Float64List(4 * hiddenSize * cols);
    _vW = Float64List(4 * hiddenSize * cols);
    _mB = Float64List(4 * hiddenSize);
    _vB = Float64List(4 * hiddenSize);
    _mWy = Float64List(outputSize * hiddenSize);
    _vWy = Float64List(outputSize * hiddenSize);
    _mBy = Float64List(outputSize);
    _vBy = Float64List(outputSize);
  }

  static double _sigmoid(double x) {
    if (x >= 0) {
      final z = math.exp(-x);
      return 1.0 / (1.0 + z);
    }
    final z = math.exp(x);
    return z / (1.0 + z);
  }

  /// Runs the forward pass and returns the sigmoid output probabilities.
  List<double> predict(List<Float64List> window) {
    final h = Float64List(hiddenSize);
    final c = Float64List(hiddenSize);
    final cols = inputSize + hiddenSize;
    final gates = Float64List(4 * hiddenSize);
    for (final x in window) {
      _stepForward(x, h, c, gates, cols);
    }
    final out = List<double>.filled(outputSize, 0);
    for (var k = 0; k < outputSize; k++) {
      var s = _by[k];
      final row = k * hiddenSize;
      for (var j = 0; j < hiddenSize; j++) {
        s += _wy[row + j] * h[j];
      }
      out[k] = _sigmoid(s);
    }
    return out;
  }

  void _stepForward(
    Float64List x,
    Float64List h,
    Float64List c,
    Float64List gates,
    int cols,
  ) {
    // gates = W [x; h] + b
    for (var r = 0; r < 4 * hiddenSize; r++) {
      var s = _b[r];
      final base = r * cols;
      for (var j = 0; j < inputSize; j++) {
        s += _w[base + j] * x[j];
      }
      for (var j = 0; j < hiddenSize; j++) {
        s += _w[base + inputSize + j] * h[j];
      }
      gates[r] = s;
    }
    for (var j = 0; j < hiddenSize; j++) {
      final i = _sigmoid(gates[j]);
      final f = _sigmoid(gates[hiddenSize + j]);
      final g = _tanh(gates[2 * hiddenSize + j]);
      final o = _sigmoid(gates[3 * hiddenSize + j]);
      c[j] = f * c[j] + i * g;
      h[j] = o * _tanh(c[j]);
    }
  }

  static double _tanh(double x) {
    if (x > 20) return 1;
    if (x < -20) return -1;
    final e2 = math.exp(2 * x);
    return (e2 - 1) / (e2 + 1);
  }

  /// Trains on one mini-batch and returns the mean weighted BCE loss.
  ///
  /// [posWeights] up-weights rare positive labels (one weight per output).
  double trainBatch(
    List<TrainingSample> batch,
    double learningRate,
    Float64List posWeights,
  ) {
    final cols = inputSize + hiddenSize;
    final gW = Float64List(4 * hiddenSize * cols);
    final gB = Float64List(4 * hiddenSize);
    final gWy = Float64List(outputSize * hiddenSize);
    final gBy = Float64List(outputSize);

    var totalLoss = 0.0;
    for (final sample in batch) {
      totalLoss += _backward(sample, posWeights, gW, gB, gWy, gBy, cols);
    }
    final n = batch.length.toDouble();
    final inv = 1.0 / n;
    for (var i = 0; i < gW.length; i++) {
      gW[i] *= inv;
    }
    for (var i = 0; i < gB.length; i++) {
      gB[i] *= inv;
    }
    for (var i = 0; i < gWy.length; i++) {
      gWy[i] *= inv;
    }
    for (var i = 0; i < gBy.length; i++) {
      gBy[i] *= inv;
    }

    _clipGlobalNorm([gW, gB, gWy, gBy]);

    _adamStep++;
    _adamUpdate(_w, gW, _mW, _vW, learningRate);
    _adamUpdate(_b, gB, _mB, _vB, learningRate);
    _adamUpdate(_wy, gWy, _mWy, _vWy, learningRate);
    _adamUpdate(_by, gBy, _mBy, _vBy, learningRate);

    return totalLoss / n;
  }

  /// Full BPTT for a single sample; accumulates gradients, returns loss.
  double _backward(
    TrainingSample sample,
    Float64List posWeights,
    Float64List gW,
    Float64List gB,
    Float64List gWy,
    Float64List gBy,
    int cols,
  ) {
    final window = sample.window;
    final T = window.length;
    final h4 = 4 * hiddenSize;

    // Forward pass storing every activation needed by the backward pass.
    final iG = List<Float64List>.generate(T, (_) => Float64List(hiddenSize));
    final fG = List<Float64List>.generate(T, (_) => Float64List(hiddenSize));
    final gG = List<Float64List>.generate(T, (_) => Float64List(hiddenSize));
    final oG = List<Float64List>.generate(T, (_) => Float64List(hiddenSize));
    final cS = List<Float64List>.generate(T, (_) => Float64List(hiddenSize));
    final hS = List<Float64List>.generate(T, (_) => Float64List(hiddenSize));

    var hPrev = Float64List(hiddenSize);
    var cPrev = Float64List(hiddenSize);
    final gates = Float64List(h4);

    for (var t = 0; t < T; t++) {
      final x = window[t];
      for (var r = 0; r < h4; r++) {
        var s = _b[r];
        final base = r * cols;
        for (var j = 0; j < inputSize; j++) {
          s += _w[base + j] * x[j];
        }
        for (var j = 0; j < hiddenSize; j++) {
          s += _w[base + inputSize + j] * hPrev[j];
        }
        gates[r] = s;
      }
      for (var j = 0; j < hiddenSize; j++) {
        final ii = _sigmoid(gates[j]);
        final ff = _sigmoid(gates[hiddenSize + j]);
        final gg = _tanh(gates[2 * hiddenSize + j]);
        final oo = _sigmoid(gates[3 * hiddenSize + j]);
        iG[t][j] = ii;
        fG[t][j] = ff;
        gG[t][j] = gg;
        oG[t][j] = oo;
        cS[t][j] = ff * cPrev[j] + ii * gg;
        hS[t][j] = oo * _tanh(cS[t][j]);
      }
      hPrev = hS[t];
      cPrev = cS[t];
    }

    // Output head.
    final hLast = hS[T - 1];
    final y = Float64List(outputSize);
    for (var k = 0; k < outputSize; k++) {
      var s = _by[k];
      final row = k * hiddenSize;
      for (var j = 0; j < hiddenSize; j++) {
        s += _wy[row + j] * hLast[j];
      }
      y[k] = _sigmoid(s);
    }

    // Weighted BCE loss + dL/dlogit.
    var loss = 0.0;
    final dLogit = Float64List(outputSize);
    for (var k = 0; k < outputSize; k++) {
      final t = sample.target[k];
      final p = y[k].clamp(1e-7, 1 - 1e-7);
      final w = posWeights[k];
      loss += -(w * t * math.log(p) + (1 - t) * math.log(1 - p));
      // d/ds of weighted BCE with s = logit:
      dLogit[k] = y[k] * (1 - t + w * t) - w * t;
    }
    loss /= outputSize;
    final invOut = 1.0 / outputSize;
    for (var k = 0; k < outputSize; k++) {
      dLogit[k] *= invOut;
    }

    // Gradients into the dense head and dh at the last timestep.
    final dh = Float64List(hiddenSize);
    for (var k = 0; k < outputSize; k++) {
      final row = k * hiddenSize;
      final dl = dLogit[k];
      gBy[k] += dl;
      for (var j = 0; j < hiddenSize; j++) {
        gWy[row + j] += dl * hLast[j];
        dh[j] += _wy[row + j] * dl;
      }
    }

    // BPTT.
    final dc = Float64List(hiddenSize);
    final dz = Float64List(h4);
    for (var t = T - 1; t >= 0; t--) {
      final cPrevT = t == 0 ? Float64List(hiddenSize) : cS[t - 1];
      final hPrevT = t == 0 ? Float64List(hiddenSize) : hS[t - 1];
      final x = window[t];

      for (var j = 0; j < hiddenSize; j++) {
        final tc = _tanh(cS[t][j]);
        final doo = dh[j] * tc;
        final dco = dh[j] * oG[t][j] * (1 - tc * tc) + dc[j];
        final dii = dco * gG[t][j];
        final dff = dco * cPrevT[j];
        final dgg = dco * iG[t][j];
        dc[j] = dco * fG[t][j];

        dz[j] = dii * iG[t][j] * (1 - iG[t][j]);
        dz[hiddenSize + j] = dff * fG[t][j] * (1 - fG[t][j]);
        dz[2 * hiddenSize + j] = dgg * (1 - gG[t][j] * gG[t][j]);
        dz[3 * hiddenSize + j] = doo * oG[t][j] * (1 - oG[t][j]);
      }

      // Accumulate weight gradients and propagate dh to t-1.
      for (var j = 0; j < hiddenSize; j++) {
        dh[j] = 0;
      }
      for (var r = 0; r < h4; r++) {
        final d = dz[r];
        if (d == 0) continue;
        final base = r * cols;
        gB[r] += d;
        for (var j = 0; j < inputSize; j++) {
          gW[base + j] += d * x[j];
        }
        for (var j = 0; j < hiddenSize; j++) {
          gW[base + inputSize + j] += d * hPrevT[j];
          dh[j] += _w[base + inputSize + j] * d;
        }
      }
    }

    return loss;
  }

  void _clipGlobalNorm(List<Float64List> grads) {
    var sq = 0.0;
    for (final g in grads) {
      for (var i = 0; i < g.length; i++) {
        sq += g[i] * g[i];
      }
    }
    final norm = math.sqrt(sq);
    if (norm <= _clipNorm || norm == 0) return;
    final scale = _clipNorm / norm;
    for (final g in grads) {
      for (var i = 0; i < g.length; i++) {
        g[i] *= scale;
      }
    }
  }

  void _adamUpdate(
    Float64List param,
    Float64List grad,
    Float64List m,
    Float64List v,
    double lr,
  ) {
    final bc1 = 1 - math.pow(_beta1, _adamStep).toDouble();
    final bc2 = 1 - math.pow(_beta2, _adamStep).toDouble();
    for (var i = 0; i < param.length; i++) {
      m[i] = _beta1 * m[i] + (1 - _beta1) * grad[i];
      v[i] = _beta2 * v[i] + (1 - _beta2) * grad[i] * grad[i];
      final mHat = m[i] / bc1;
      final vHat = v[i] / bc2;
      param[i] -= lr * mHat / (math.sqrt(vHat) + _eps);
    }
  }

  /// Computes loss/accuracy/macro-F1 on a held-out set without updating
  /// weights.
  ({double loss, double accuracy, double f1}) evaluate(
    List<TrainingSample> samples,
    Float64List posWeights,
  ) {
    if (samples.isEmpty) return (loss: 0, accuracy: 0, f1: 0);
    var loss = 0.0;
    var correct = 0;
    var total = 0;
    final tp = List<int>.filled(outputSize, 0);
    final fp = List<int>.filled(outputSize, 0);
    final fn = List<int>.filled(outputSize, 0);

    for (final sample in samples) {
      final y = predict(sample.window);
      for (var k = 0; k < outputSize; k++) {
        final t = sample.target[k];
        final p = y[k].clamp(1e-7, 1 - 1e-7);
        final w = posWeights[k];
        loss += -(w * t * math.log(p) + (1 - t) * math.log(1 - p));
        final pred = y[k] >= 0.5;
        final truth = t >= 0.5;
        if (pred == truth) correct++;
        if (pred && truth) tp[k]++;
        if (pred && !truth) fp[k]++;
        if (!pred && truth) fn[k]++;
        total++;
      }
    }
    var f1Sum = 0.0;
    var f1Count = 0;
    for (var k = 0; k < outputSize; k++) {
      final denom = 2 * tp[k] + fp[k] + fn[k];
      if (tp[k] + fn[k] == 0) continue; // class absent in val set
      f1Sum += denom == 0 ? 0 : 2 * tp[k] / denom;
      f1Count++;
    }
    return (
      loss: loss / (samples.length * outputSize),
      accuracy: total == 0 ? 0 : correct / total,
      f1: f1Count == 0 ? 0 : f1Sum / f1Count,
    );
  }

  /// Deep copy of the learned parameters (used to snapshot the best epoch).
  LstmNetwork clone() {
    final copy = LstmNetwork._raw(inputSize, hiddenSize, outputSize);
    copy._w.setAll(0, _w);
    copy._b.setAll(0, _b);
    copy._wy.setAll(0, _wy);
    copy._by.setAll(0, _by);
    return copy;
  }

  Map<String, dynamic> toJson() => {
        'inputSize': inputSize,
        'hiddenSize': hiddenSize,
        'outputSize': outputSize,
        'w': _round(_w),
        'b': _round(_b),
        'wy': _round(_wy),
        'by': _round(_by),
      };

  String toJsonString() => jsonEncode(toJson());

  static List<double> _round(Float64List v) =>
      v.map((e) => double.parse(e.toStringAsPrecision(7))).toList();

  factory LstmNetwork.fromJson(Map<String, dynamic> json) {
    final net = LstmNetwork._raw(
      (json['inputSize'] as num).toInt(),
      (json['hiddenSize'] as num).toInt(),
      (json['outputSize'] as num).toInt(),
    );
    net._w = Float64List.fromList(
        (json['w'] as List).map((e) => (e as num).toDouble()).toList());
    net._b = Float64List.fromList(
        (json['b'] as List).map((e) => (e as num).toDouble()).toList());
    net._wy = Float64List.fromList(
        (json['wy'] as List).map((e) => (e as num).toDouble()).toList());
    net._by = Float64List.fromList(
        (json['by'] as List).map((e) => (e as num).toDouble()).toList());
    return net;
  }

  factory LstmNetwork.fromJsonString(String json) =>
      LstmNetwork.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

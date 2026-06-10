import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/lstm/lstm_network.dart';
import 'package:alertsysapp/services/lstm/lstm_types.dart';

/// Builds a synthetic sequence task the network must genuinely learn:
/// output k fires when the mean of input feature k over the window exceeds
/// 0.5. Random weights score ~chance; a learning network nails it.
List<TrainingSample> _syntheticSamples(int count, int seqLen, int seed) {
  final rng = math.Random(seed);
  final samples = <TrainingSample>[];
  for (var n = 0; n < count; n++) {
    final window = <Float64List>[];
    final sums = Float64List(4);
    for (var t = 0; t < seqLen; t++) {
      final x = Float64List(kLstmFeatureCols.length);
      for (var j = 0; j < x.length; j++) {
        x[j] = rng.nextDouble();
      }
      for (var k = 0; k < 4; k++) {
        sums[k] += x[k];
      }
      window.add(x);
    }
    final target = Float64List(4);
    for (var k = 0; k < 4; k++) {
      target[k] = sums[k] / seqLen > 0.5 ? 1 : 0;
    }
    samples.add(TrainingSample(window: window, target: target, machineKey: 'm'));
  }
  return samples;
}

void main() {
  group('LstmNetwork', () {
    test('training reduces loss on a learnable sequence task', () {
      final samples = _syntheticSamples(240, 8, 7);
      final train = samples.sublist(0, 200);
      final val = samples.sublist(200);
      final net = LstmNetwork(
        inputSize: kLstmFeatureCols.length,
        hiddenSize: 12,
        outputSize: 4,
        seed: 3,
      );
      final posWeights = Float64List.fromList([1, 1, 1, 1]);

      final initial = net.evaluate(val, posWeights);
      double lastTrainLoss = 0;
      for (var epoch = 0; epoch < 25; epoch++) {
        for (var s = 0; s < train.length; s += 20) {
          lastTrainLoss = net.trainBatch(
            train.sublist(s, math.min(s + 20, train.length)),
            0.02,
            posWeights,
          );
        }
      }
      final after = net.evaluate(val, posWeights);

      expect(after.loss, lessThan(initial.loss * 0.7),
          reason: 'validation loss should drop materially when learning');
      expect(after.accuracy, greaterThan(0.8),
          reason: 'task is learnable to >80% accuracy');
      expect(lastTrainLoss, lessThan(initial.loss));
    });

    test('serialization round-trips predictions exactly', () {
      final net = LstmNetwork(
        inputSize: kLstmFeatureCols.length,
        hiddenSize: 8,
        outputSize: 4,
        seed: 11,
      );
      final sample = _syntheticSamples(1, 8, 5).first;
      final before = net.predict(sample.window);
      final restored = LstmNetwork.fromJsonString(net.toJsonString());
      final afterPred = restored.predict(sample.window);
      for (var k = 0; k < 4; k++) {
        expect(afterPred[k], closeTo(before[k], 1e-5));
      }
    });

    test('clone is independent of further training on the original', () {
      final net = LstmNetwork(
        inputSize: kLstmFeatureCols.length,
        hiddenSize: 8,
        outputSize: 4,
        seed: 13,
      );
      final samples = _syntheticSamples(40, 6, 9);
      final probe = samples.first.window;
      final snapshot = net.clone();
      final before = snapshot.predict(probe);
      net.trainBatch(samples, 0.05, Float64List.fromList([1, 1, 1, 1]));
      final after = snapshot.predict(probe);
      for (var k = 0; k < 4; k++) {
        expect(after[k], equals(before[k]));
      }
      // And the original did actually change.
      final changed = net.predict(probe);
      expect(changed, isNot(equals(before)));
    });

    test('outputs are valid probabilities', () {
      final net = LstmNetwork(
        inputSize: kLstmFeatureCols.length,
        hiddenSize: 6,
        outputSize: 4,
        seed: 1,
      );
      final sample = _syntheticSamples(1, 14, 2).first;
      for (final p in net.predict(sample.window)) {
        expect(p, inInclusiveRange(0, 1));
      }
    });
  });
}

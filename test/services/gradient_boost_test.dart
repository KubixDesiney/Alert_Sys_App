import 'dart:math' as math;
import 'dart:typed_data';

import 'package:alertsysapp/services/forecast/forecast_types.dart';
import 'package:alertsysapp/services/forecast/gradient_boost.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a learnable synthetic task: type 0 fires when feature 7 (dayofweek)
/// is a weekday, type 1 fires when feature 17 (total_7d) is high. The booster
/// must drive training loss down and reproduce both rules.
({List<Float64List> x, List<Float64List> y}) _separableData(int n, int seed) {
  final rng = math.Random(seed);
  final x = <Float64List>[];
  final y = <Float64List>[];
  for (var i = 0; i < n; i++) {
    final f = Float64List(kForecastFeatureCols.length);
    f[7] = rng.nextInt(7).toDouble(); // dayofweek
    f[17] = rng.nextDouble() * 10; // total_7d
    f[5] = rng.nextDouble() * 20; // noise feature
    final t = Float64List(kForecastAlertTypes.length);
    t[0] = f[7] < 5 ? 1 : 0;
    t[1] = f[17] > 6 ? 1 : 0;
    x.add(f);
    y.add(t);
  }
  return (x: x, y: y);
}

void main() {
  group('GbdtBooster', () {
    test('drives loss down on a separable task and beats the baseline', () {
      final train = _separableData(600, 3);
      final val = _separableData(150, 4);
      final booster = GbdtBooster(
        trainX: train.x,
        trainY: train.y,
        valX: val.x,
        valY: val.y,
        config: const ForecastTrainingConfig(
          rounds: 40,
          learningRate: 0.2,
          maxDepth: 3,
          minSamplesLeaf: 5,
          subsample: 1.0,
          colsample: 1.0,
          seed: 11,
        ),
      );

      final baseline = booster.evalVal();
      for (var r = 0; r < 40; r++) {
        booster.boostOneRound();
      }
      final after = booster.evalVal();

      expect(after.loss, lessThan(baseline.loss * 0.5),
          reason: 'boosting must materially beat the prior-only baseline');
      expect(after.accuracy, greaterThan(0.95));

      // The learned rules hold on fresh points.
      final weekday = Float64List(kForecastFeatureCols.length)
        ..[7] = 2
        ..[17] = 1;
      final weekend = Float64List(kForecastFeatureCols.length)
        ..[7] = 6
        ..[17] = 9;
      expect(booster.model.predict(weekday)[0], greaterThan(0.5));
      expect(booster.model.predict(weekend)[0], lessThan(0.5));
      expect(booster.model.predict(weekend)[1], greaterThan(0.5));
      expect(booster.model.predict(weekday)[1], lessThan(0.5));
    });

    test('probabilities always stay within [0, 1]', () {
      final train = _separableData(200, 7);
      final booster = GbdtBooster(
        trainX: train.x,
        trainY: train.y,
        valX: const [],
        valY: const [],
        config: const ForecastTrainingConfig(
          rounds: 10,
          learningRate: 0.3,
          maxDepth: 4,
          minSamplesLeaf: 4,
        ),
      );
      for (var r = 0; r < 10; r++) {
        booster.boostOneRound();
      }
      for (final row in train.x.take(50)) {
        for (final p in booster.model.predict(row)) {
          expect(p, inInclusiveRange(0, 1));
        }
      }
    });
  });

  group('GradientBoostModel serialization', () {
    GradientBoostModel trained() {
      final train = _separableData(300, 9);
      final booster = GbdtBooster(
        trainX: train.x,
        trainY: train.y,
        valX: const [],
        valY: const [],
        config: const ForecastTrainingConfig(
          rounds: 12,
          learningRate: 0.15,
          maxDepth: 3,
          minSamplesLeaf: 5,
          seed: 2,
        ),
      );
      for (var r = 0; r < 12; r++) {
        booster.boostOneRound();
      }
      return booster.model;
    }

    test('round-trips through JSON with near-identical predictions', () {
      final model = trained();
      final restored =
          GradientBoostModel.fromJsonString(model.toJsonString());

      expect(restored.featureCount, model.featureCount);
      expect(restored.roundsPerType, model.roundsPerType);
      final probe = Float64List(kForecastFeatureCols.length)
        ..[7] = 3
        ..[17] = 8;
      final a = model.predict(probe);
      final b = restored.predict(probe);
      for (var k = 0; k < a.length; k++) {
        expect(b[k], closeTo(a[k], 1e-4));
      }
    });

    test('truncated keeps only the first n rounds per type', () {
      final model = trained();
      final cut = model.truncated(5);
      expect(cut.roundsPerType, 5);
      for (final seq in cut.trees) {
        expect(seq.length, 5);
      }
      // Original is untouched.
      expect(model.roundsPerType, 12);
    });

    test('clone is independent of the original', () {
      final model = trained();
      final copy = model.clone();
      copy.trees[0].removeLast();
      expect(model.trees[0].length, 12);
      expect(copy.trees[0].length, 11);
    });
  });

  group('GradientBoostModel dynamic (non-default) type set', () {
    test('trains, sizes and serializes a custom 3-type ensemble', () {
      const types = ['overheating', 'vibration', 'leak'];
      final width = forecastFeatureCountFor(types.length); // 3*3+13 = 22
      final rng = math.Random(5);
      final x = <Float64List>[];
      final y = <Float64List>[];
      for (var i = 0; i < 200; i++) {
        final f = Float64List(width);
        f[0] = rng.nextDouble();
        final t = Float64List(types.length);
        t[0] = f[0] > 0.5 ? 1 : 0;
        x.add(f);
        y.add(t);
      }
      final booster = GbdtBooster(
        trainX: x,
        trainY: y,
        valX: const [],
        valY: const [],
        config: const ForecastTrainingConfig(
          rounds: 6,
          learningRate: 0.2,
          maxDepth: 3,
          minSamplesLeaf: 5,
        ),
        types: types,
      );
      for (var r = 0; r < 6; r++) {
        booster.boostOneRound();
      }
      final model = booster.model;
      expect(model.types, types);
      expect(model.outputSize, 3);
      expect(model.featureCount, width);
      expect(model.featureCount, 22);
      expect(model.thresholds.length, 3);

      final probe = Float64List(width)..[0] = 0.9;
      expect(model.predict(probe).length, 3);

      final restored =
          GradientBoostModel.fromJsonString(model.toJsonString());
      expect(restored.types, types);
      expect(restored.featureCount, width);
      expect(restored.predict(probe).length, 3);
    });

    test('legacy JSON without a types list defaults to the standard set', () {
      const json = '{"algo":"gbdt","featureCount":25,"base":[0,0,0,0],'
          '"baseRounds":0,"adaptedRounds":0,'
          '"thresholds":[0.5,0.5,0.5,0.5],"trees":[[],[],[],[]]}';
      final m = GradientBoostModel.fromJsonString(json);
      expect(m.types, kForecastAlertTypes);
    });
  });
}

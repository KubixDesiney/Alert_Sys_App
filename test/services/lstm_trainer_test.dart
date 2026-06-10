import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/lstm/lstm_feature_engineer.dart';
import 'package:alertsysapp/services/lstm/lstm_trainer.dart';
import 'package:alertsysapp/services/lstm/lstm_types.dart';

/// Generates a synthetic plant with a learnable temporal pattern: machine A
/// fires quality alerts on weekdays, machine B fires maintenance alerts
/// every third day. A learning LSTM must beat its starting validation loss.
List<AlertRecord> _syntheticHistory({int days = 160}) {
  final rng = math.Random(99);
  final records = <AlertRecord>[];
  final start = DateTime.utc(2025, 10, 1);
  for (var d = 0; d < days; d++) {
    final day = start.add(Duration(days: d));
    final weekday = day.weekday; // 1=Mon..7=Sun
    if (weekday <= 5 && rng.nextDouble() < 0.85) {
      records.add(AlertRecord(
        timestamp: day.add(Duration(hours: 8 + rng.nextInt(4))),
        type: 'qualite',
        usine: 'Plant A',
        convoyeur: 1,
        poste: 1,
        isCritical: rng.nextDouble() < 0.2,
      ));
    }
    if (d % 3 == 0) {
      records.add(AlertRecord(
        timestamp: day.add(Duration(hours: 14 + rng.nextInt(3))),
        type: 'maintenance',
        usine: 'Plant A',
        convoyeur: 2,
        poste: 4,
      ));
    }
  }
  return records;
}

void main() {
  group('LstmTrainer end-to-end', () {
    test('learns a real temporal pattern from engineered alert history',
        () async {
      final records = _syntheticHistory();
      final rows = LstmFeatureEngineer.buildDailyRows(records);
      final scaler = FeatureScaler.fit(rows);
      final samples = LstmFeatureEngineer.buildWindows(rows, scaler, 14);
      expect(samples.length, greaterThan(100));

      final trainer = LstmTrainer();
      final updates = <LstmTrainingUpdate>[];
      await for (final update in trainer.train(
        samples: samples,
        scaler: scaler,
        config: const LstmTrainingConfig(
          hiddenSize: 16,
          epochs: 18,
          learningRate: 0.01,
          batchSize: 24,
          patience: 18,
          seed: 5,
        ),
      )) {
        updates.add(update);
      }

      final result = trainer.result;
      expect(result, isNotNull);
      expect(updates.last.phase, LstmTrainingPhase.done);
      expect(result!.epochs.length, greaterThanOrEqualTo(3));

      // Loss curves are real: validation loss must drop from its start.
      final first = result.epochs.first.valLoss;
      final best =
          result.epochs.map((e) => e.valLoss).reduce(math.min);
      expect(best, lessThan(first),
          reason: 'validation loss must decrease when genuinely learning');
      expect(result.isLearning, isTrue);
      expect(result.bestValAccuracy, greaterThan(0.6));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refuses datasets that are too small', () async {
      final trainer = LstmTrainer();
      final updates = <LstmTrainingUpdate>[];
      await for (final u in trainer.train(
        samples: const [],
        scaler: const FeatureScaler(mins: [], maxs: []),
        config: LstmTrainingConfig.auto(0),
      )) {
        updates.add(u);
      }
      expect(updates.single.phase, LstmTrainingPhase.failed);
      expect(trainer.result, isNull);
    });

    test('cancel stops training and keeps best weights', () async {
      final records = _syntheticHistory(days: 120);
      final rows = LstmFeatureEngineer.buildDailyRows(records);
      final scaler = FeatureScaler.fit(rows);
      final samples = LstmFeatureEngineer.buildWindows(rows, scaler, 14);

      final trainer = LstmTrainer();
      var epochsSeen = 0;
      await for (final update in trainer.train(
        samples: samples,
        scaler: scaler,
        config: const LstmTrainingConfig(
          hiddenSize: 12,
          epochs: 50,
          learningRate: 0.01,
          batchSize: 24,
          seed: 7,
        ),
      )) {
        if (update.phase == LstmTrainingPhase.training) {
          epochsSeen = update.epochs.length;
          if (epochsSeen >= 2) trainer.cancel();
        }
        if (update.phase == LstmTrainingPhase.stopped) {
          expect(update.progress, 1);
        }
      }
      expect(trainer.result, isNotNull);
      expect(trainer.result!.epochs.length, lessThan(50));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

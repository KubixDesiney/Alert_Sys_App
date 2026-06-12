import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/forecast/forecast_feature_engineer.dart';
import 'package:alertsysapp/services/forecast/forecast_trainer.dart';
import 'package:alertsysapp/services/forecast/forecast_types.dart';

/// Generates a synthetic plant with a learnable temporal pattern: machine A
/// fires quality alerts on weekdays, machine B fires maintenance alerts
/// every third day. A learning model must beat its baseline validation loss.
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
  group('ForecastTrainer end-to-end', () {
    test('learns a real temporal pattern from engineered alert history',
        () async {
      final records = _syntheticHistory();
      final rows = ForecastFeatureEngineer.buildDailyRows(records);
      final samples = ForecastFeatureEngineer.buildSamples(rows);
      expect(samples.length, greaterThan(100));

      final trainer = ForecastTrainer();
      final updates = <ForecastTrainingUpdate>[];
      await for (final update in trainer.train(
        samples: samples,
        config: const ForecastTrainingConfig(
          rounds: 60,
          learningRate: 0.1,
          maxDepth: 3,
          minSamplesLeaf: 8,
          patience: 60,
          seed: 5,
        ),
      )) {
        updates.add(update);
      }

      final result = trainer.result;
      expect(result, isNotNull);
      expect(updates.last.phase, ForecastTrainingPhase.done);
      expect(result!.rounds.length, greaterThanOrEqualTo(3));

      // Loss curves are real: validation loss must drop from its baseline.
      final first = result.rounds.first.valLoss;
      final best = result.rounds.map((e) => e.valLoss).reduce(math.min);
      expect(best, lessThan(first),
          reason: 'validation loss must decrease when genuinely learning');
      expect(result.isLearning, isTrue);
      expect(result.bestValAccuracy, greaterThan(0.6));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refuses datasets that are too small', () async {
      final trainer = ForecastTrainer();
      final updates = <ForecastTrainingUpdate>[];
      await for (final u in trainer.train(
        samples: const [],
        config: ForecastTrainingConfig.auto(0),
      )) {
        updates.add(u);
      }
      expect(updates.single.phase, ForecastTrainingPhase.failed);
      expect(trainer.result, isNull);
    });

    test('cancel stops training and keeps the best ensemble', () async {
      final records = _syntheticHistory(days: 120);
      final rows = ForecastFeatureEngineer.buildDailyRows(records);
      final samples = ForecastFeatureEngineer.buildSamples(rows);

      final trainer = ForecastTrainer();
      var roundsSeen = 0;
      await for (final update in trainer.train(
        samples: samples,
        config: const ForecastTrainingConfig(
          rounds: 200,
          learningRate: 0.1,
          maxDepth: 3,
          minSamplesLeaf: 8,
          seed: 7,
        ),
      )) {
        if (update.phase == ForecastTrainingPhase.training) {
          roundsSeen = update.rounds.length;
          if (roundsSeen >= 3) trainer.cancel();
        }
        if (update.phase == ForecastTrainingPhase.stopped) {
          expect(update.progress, 1);
        }
      }
      expect(trainer.result, isNotNull);
      expect(trainer.result!.rounds.length, lessThan(200));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('resume continues from a checkpointed model and round', () async {
      final records = _syntheticHistory(days: 120);
      final rows = ForecastFeatureEngineer.buildDailyRows(records);
      final samples = ForecastFeatureEngineer.buildSamples(rows);

      // First leg: 10 rounds.
      final first = ForecastTrainer();
      const config = ForecastTrainingConfig(
        rounds: 20,
        learningRate: 0.1,
        maxDepth: 3,
        minSamplesLeaf: 8,
        patience: 50,
        seed: 13,
      );
      ForecastTrainingUpdate? snapshot;
      await for (final u in first.train(
          samples: samples, config: config.copyWith(rounds: 10))) {
        snapshot = u;
      }
      final leg1 = first.result!;
      expect(leg1.rounds.last.round, 10);

      // Second leg resumes with the live model and stats.
      final second = ForecastTrainer();
      await for (final _ in second.train(
        samples: samples,
        config: config,
        resumeModel: first.liveModel,
        startRound: 11,
        resumeStats: snapshot!.rounds,
      )) {}
      final leg2 = second.result!;
      expect(leg2.rounds.last.round, 20);
      // History is continuous: contains both legs' rounds.
      expect(leg2.rounds.map((r) => r.round), contains(5));
      expect(leg2.rounds.map((r) => r.round), contains(15));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('ForecastTrainer.adapt', () {
    test('appends adaptation rounds without touching the input model',
        () async {
      final records = _syntheticHistory(days: 120);
      final samples = ForecastFeatureEngineer.buildSamples(
          ForecastFeatureEngineer.buildDailyRows(records));

      final trainer = ForecastTrainer();
      await for (final _ in trainer.train(
        samples: samples,
        config: const ForecastTrainingConfig(
          rounds: 15,
          learningRate: 0.1,
          maxDepth: 3,
          minSamplesLeaf: 8,
          patience: 50,
          seed: 3,
        ),
      )) {}
      final base = trainer.result!.model;
      final baseRounds = base.roundsPerType;

      final adapted = await ForecastTrainer.adapt(
        model: base,
        samples: samples,
        rounds: 4,
      );
      expect(adapted, isNotNull);
      expect(adapted!.roundsPerType, baseRounds + 4);
      expect(adapted.adaptedRounds, 4);
      // The deployed input is untouched.
      expect(base.roundsPerType, baseRounds);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refuses to adapt on too few samples', () async {
      final records = _syntheticHistory(days: 120);
      final samples = ForecastFeatureEngineer.buildSamples(
          ForecastFeatureEngineer.buildDailyRows(records));
      final trainer = ForecastTrainer();
      await for (final _ in trainer.train(
        samples: samples,
        config: const ForecastTrainingConfig(
          rounds: 5,
          learningRate: 0.1,
          maxDepth: 3,
          minSamplesLeaf: 8,
          patience: 50,
          seed: 3,
        ),
      )) {}
      final adapted = await ForecastTrainer.adapt(
        model: trainer.result!.model,
        samples: samples.take(10).toList(),
        rounds: 4,
      );
      expect(adapted, isNull);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

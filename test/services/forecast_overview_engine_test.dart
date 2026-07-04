import 'dart:math' as math;
import 'dart:typed_data';

import 'package:alertsysapp/services/forecast/forecast_engine.dart';
import 'package:alertsysapp/services/forecast/forecast_model_store.dart';
import 'package:alertsysapp/services/forecast/forecast_overview_engine.dart';
import 'package:alertsysapp/services/forecast/forecast_trainer.dart';
import 'package:alertsysapp/services/forecast/forecast_types.dart';
import 'package:alertsysapp/services/forecast/gradient_boost.dart';
import 'package:flutter_test/flutter_test.dart';

MachineForecast _forecast(
  String usine,
  int convoyeur,
  int poste,
  Map<String, double> probs,
) =>
    MachineForecast(
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
      typeProbabilities: {
        for (final t in kForecastAlertTypes) t: probs[t] ?? 0.0,
      },
    );

AlertRecord _record(
  String usine,
  int convoyeur,
  int poste,
  String type,
  DateTime ts, {
  bool critical = false,
}) =>
    AlertRecord(
      timestamp: ts,
      type: type,
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
      isCritical: critical,
    );

FeatureSample _sample(List<double> target) => FeatureSample(
      features: Float64List(kForecastFeatureCols.length),
      target: Float64List.fromList(target),
      machineKey: 'A|1|1',
    );

void main() {
  group('ForecastOverviewEngine.buildPredictiveModel', () {
    final now = DateTime(2026, 6, 11, 8);

    test('emits one failure per machine-type above the floor, sorted', () {
      final forecasts = [
        _forecast('Delta', 1, 3, {'qualite': 0.96, 'maintenance': 0.1}),
        _forecast('Aero', 1, 2, {'manque_ressource': 0.5}),
      ];
      final model = ForecastOverviewEngine.buildPredictiveModel(
        forecasts: forecasts,
        records: const [],
        now: now,
      );

      expect(model.predictions.length, 2); // 0.1 is below the 0.2 floor
      expect(model.predictions.first.type, 'qualite');
      expect(model.predictions.first.confidence, 96);
      expect(model.predictions.first.usine, 'Delta');
      expect(model.predictions[1].type, 'manque_ressource');
      expect(model.predictions[1].confidence, 50);

      // Higher probability ⇒ sooner ETA, always inside the 24h horizon.
      expect(model.predictions.first.etaHours!,
          lessThan(model.predictions[1].etaHours!));
      expect(model.predictions.first.etaHours!, greaterThanOrEqualTo(0.5));
      expect(model.predictions[1].etaHours!, lessThanOrEqualTo(24));
    });

    test('surfaces top low-risk entries when nothing crosses the floor', () {
      // A calm plant must still show live AI output on the PM dashboard
      // instead of an empty "not enough data" card.
      final forecasts = [
        _forecast('Delta', 1, 3, {'qualite': 0.12, 'maintenance': 0.04}),
        _forecast('Aero', 1, 2, {'manque_ressource': 0.08}),
      ];
      final model = ForecastOverviewEngine.buildPredictiveModel(
        forecasts: forecasts,
        records: const [],
        now: now,
      );

      expect(model.predictions, isNotEmpty);
      expect(model.predictions.first.type, 'qualite');
      expect(model.predictions.first.confidence, 12);
      // The relaxed floor still drops near-zero noise.
      expect(
        model.predictions.every((p) => p.confidence >= 1),
        isTrue,
      );
    });

    test('enriches failures with machine history facts', () {
      final forecasts = [
        _forecast('Delta', 1, 3, {'qualite': 0.9}),
      ];
      final records = [
        _record('Delta', 1, 3, 'qualite', DateTime(2026, 6, 1), critical: true),
        _record('Delta', 1, 3, 'qualite', DateTime(2026, 6, 8)),
        _record('Delta', 1, 3, 'maintenance', DateTime(2026, 6, 10)),
        _record('Other', 2, 1, 'qualite', DateTime(2026, 6, 9)),
      ];
      final model = ForecastOverviewEngine.buildPredictiveModel(
        forecasts: forecasts,
        records: records,
        now: now,
      );

      final f = model.predictions.single;
      expect(f.pastCount, 2); // only this machine's qualite alerts
      expect(f.criticalCount, 1);
      expect(f.lastTs, DateTime(2026, 6, 8));
    });

    test('bucket decomposition reproduces the day-level probability', () {
      final forecasts = [
        _forecast('Delta', 1, 3, {'qualite': 0.6}),
        _forecast('Aero', 1, 2, {'qualite': 0.4}),
      ];
      final model = ForecastOverviewEngine.buildPredictiveModel(
        forecasts: forecasts,
        records: const [],
        now: now,
      );

      final curve = model.curves['qualite']!;
      const expectedDay = 1 - (1 - 0.6) * (1 - 0.4);
      expect(curve.total24h, closeTo(expectedDay, 1e-9));
      expect(curve.buckets.length, 12);

      var noAlert = 1.0;
      for (final b in curve.buckets) {
        noAlert *= 1 - b.probability;
      }
      expect(1 - noAlert, closeTo(curve.total24h, 1e-9));

      // Uniform fallback shape: all buckets equal.
      final probs = curve.buckets.map((b) => b.probability).toList();
      expect(probs.reduce(math.max), closeTo(probs.reduce(math.min), 1e-9));

      // Quiet type stays quiet.
      expect(model.curves['maintenance']!.total24h, 0);
    });

    test('buckets are aligned to the current hour', () {
      final forecasts = [
        _forecast('Delta', 1, 3, {'qualite': 0.5}),
      ];
      final model = ForecastOverviewEngine.buildPredictiveModel(
        forecasts: forecasts,
        records: const [],
        now: DateTime(2026, 6, 11, 8),
      );
      final buckets = model.curves['qualite']!.buckets;
      expect(buckets.first.startHour, 8);
      expect(buckets.first.endHour, 10);
      expect(buckets.last.startHour, 6); // (8 + 22) % 24
      expect(buckets[1].offsetHours, 2);
    });
  });

  group('ForecastTrainer.diagnose', () {
    test('explains a tiny, flat run', () {
      final samples = [
        for (var i = 0; i < 10; i++) _sample([0, 0, 0, 0]),
      ];
      final rounds = [
        const RoundStat(
            round: 0, trainLoss: 0.7, valLoss: 0.7, valAccuracy: 0.5, valF1: 0),
        const RoundStat(
            round: 1, trainLoss: 0.7, valLoss: 0.71, valAccuracy: 0.5, valF1: 0),
      ];
      final reasons = ForecastTrainer.diagnose(
        samples: samples,
        rounds: rounds,
        config: ForecastTrainingConfig.auto(samples.length),
      );

      expect(reasons, isNotEmpty);
      expect(reasons.join(' '), contains('10 training samples'));
      expect(reasons.join(' '), contains('round'));
    });

    test('flags missing positive labels and zero loss improvement', () {
      final samples = [
        for (var i = 0; i < 200; i++)
          _sample([i % 4 == 0 ? 1 : 0, i % 3 == 0 ? 1 : 0, 0, 0]),
      ];
      final rounds = [
        for (var r = 0; r < 10; r++)
          RoundStat(
              round: r,
              trainLoss: 0.6,
              valLoss: 0.6 + r * 0.001,
              valAccuracy: 0.5,
              valF1: 0),
      ];
      final reasons = ForecastTrainer.diagnose(
        samples: samples,
        rounds: rounds,
        config: ForecastTrainingConfig.auto(samples.length),
      );

      final text = reasons.join(' ');
      expect(text, contains('defaut_produit'));
      expect(text, contains('manque_ressource'));
      expect(text, contains('never dropped'));
    });

    test('reports the improvement shortfall when loss moved a little', () {
      final samples = [
        for (var i = 0; i < 400; i++) _sample([i % 5 == 0 ? 1 : 0, 0, 0, 0]),
      ];
      final rounds = [
        for (var r = 0; r < 10; r++)
          RoundStat(
              round: r,
              trainLoss: 0.6,
              // 1% total improvement — below the 3% verdict bar.
              valLoss: 0.6 * (1 - 0.001 * r),
              valAccuracy: 0.5,
              valF1: 0),
      ];
      final reasons = ForecastTrainer.diagnose(
        samples: samples,
        rounds: rounds,
        config: ForecastTrainingConfig.auto(samples.length),
      );
      expect(reasons.join(' '), contains('improved only'));
    });
  });

  group('ForecastTrainer.isLearningFromStats', () {
    test('requires a 3% drop below the round-0 baseline', () {
      List<RoundStat> stats(double last) => [
            const RoundStat(
                round: 0,
                trainLoss: 1,
                valLoss: 1.0,
                valAccuracy: 0.5,
                valF1: 0),
            const RoundStat(
                round: 1,
                trainLoss: 1,
                valLoss: 0.99,
                valAccuracy: 0.5,
                valF1: 0),
            RoundStat(
                round: 2,
                trainLoss: 1,
                valLoss: last,
                valAccuracy: 0.5,
                valF1: 0),
          ];
      expect(ForecastTrainer.isLearningFromStats(stats(0.96)), isTrue);
      expect(ForecastTrainer.isLearningFromStats(stats(0.98)), isFalse);
      expect(
          ForecastTrainer.isLearningFromStats(stats(0.96).sublist(0, 2)),
          isFalse);
    });
  });

  group('dynamic (non-default) type set', () {
    final now = DateTime(2026, 6, 11, 8);

    test('risk curves follow the forecasts’ configured type set', () {
      final forecasts = [
        const MachineForecast(
          usine: 'P',
          convoyeur: 1,
          poste: 1,
          typeProbabilities: {'overheating': 0.8, 'vibration': 0.3},
        ),
      ];
      final model = ForecastOverviewEngine.buildPredictiveModel(
        forecasts: forecasts,
        records: const [],
        now: now,
      );
      expect(model.curves.keys.toSet(), {'overheating', 'vibration'});
      expect(model.predictions.map((p) => p.type),
          contains('overheating'));
    });
  });

  group('stale-model fallback (ForecastEngine width guard)', () {
    List<AlertRecord> burst(String type) => [
          for (var d = 1; d <= 12; d++)
            _record('P', 1, 1, type, DateTime.utc(2026, 1, d)),
        ];

    test('skips inference when the model width no longer matches its types', () {
      // Simulates a stale model: its persisted featureCount (the old 4-type
      // width, 25) disagrees with its 2-type set (width 19). Inference must
      // not mis-index — it returns nothing so the caller falls back to the
      // statistical model.
      final model = GradientBoostModel.empty(
        featureCount: 25,
        baseScores: Float64List.fromList([0, 0]),
        types: const ['overheating', 'vibration'],
      );
      final out = ForecastEngine.computeForecasts(
        TrainedForecastModel(model: model),
        burst('overheating'),
        now: DateTime.utc(2026, 1, 20),
      );
      expect(out, isEmpty);
    });

    test('forecasts a matching custom-type model with per-type probabilities',
        () {
      final model = GradientBoostModel.empty(
        featureCount: forecastFeatureCountFor(2),
        baseScores: Float64List.fromList([0, 0]),
        types: const ['overheating', 'vibration'],
      );
      final out = ForecastEngine.computeForecasts(
        TrainedForecastModel(model: model),
        burst('overheating'),
        now: DateTime.utc(2026, 1, 20),
      );
      expect(out, isNotEmpty);
      expect(out.first.typeProbabilities.keys.toSet(),
          {'overheating', 'vibration'});
    });
  });
}

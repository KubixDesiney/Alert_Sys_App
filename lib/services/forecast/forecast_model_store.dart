import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'gradient_boost.dart';
import 'forecast_types.dart';

/// A deployed model plus everything inference and the console need.
class TrainedForecastModel {
  final GradientBoostModel model;
  final DateTime? trainedAt;
  final String? datasetName;
  final int sampleCount;
  final double valLoss;
  final double valAccuracy;
  final bool learning;
  final int version;
  final DateTime? lastAdaptedAt;

  const TrainedForecastModel({
    required this.model,
    this.trainedAt,
    this.datasetName,
    this.sampleCount = 0,
    this.valLoss = 0,
    this.valAccuracy = 0,
    this.learning = false,
    this.version = 1,
    this.lastAdaptedAt,
  });

  static TrainedForecastModel? fromSnapshotValue(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final weights = map['weights'];
    if (weights is! String) return null;
    try {
      return TrainedForecastModel(
        model: GradientBoostModel.fromJsonString(weights),
        trainedAt: DateTime.tryParse((map['trainedAt'] ?? '').toString()),
        datasetName: map['datasetName']?.toString(),
        sampleCount: (map['sampleCount'] as num?)?.toInt() ?? 0,
        valLoss: (map['valLoss'] as num?)?.toDouble() ?? 0,
        valAccuracy: (map['valAccuracy'] as num?)?.toDouble() ?? 0,
        learning: map['learning'] == true,
        version: (map['version'] as num?)?.toInt() ?? 1,
        lastAdaptedAt:
            DateTime.tryParse((map['lastAdaptedAt'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Rolling self-evaluation of deployed forecasts against realized alerts.
class ForecastAccuracy {
  final int gradedDays;
  final int gradedPairs;
  final double brierMean;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final DateTime? lastGradedDay;
  final DateTime? updatedAt;

  const ForecastAccuracy({
    required this.gradedDays,
    required this.gradedPairs,
    required this.brierMean,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    this.lastGradedDay,
    this.updatedAt,
  });

  /// Of the alerts the model called (p >= 0.5), how many materialized.
  double get precision {
    final denom = truePositives + falsePositives;
    return denom == 0 ? 0 : truePositives / denom;
  }

  /// Of the alerts that happened, how many the model called.
  double get recall {
    final denom = truePositives + falseNegatives;
    return denom == 0 ? 0 : truePositives / denom;
  }

  static ForecastAccuracy? fromSnapshotValue(Object? value) {
    if (value is! Map) return null;
    final m = Map<String, dynamic>.from(value);
    final pairs = (m['gradedPairs'] as num?)?.toInt() ?? 0;
    return ForecastAccuracy(
      gradedDays: (m['gradedDays'] as num?)?.toInt() ?? 0,
      gradedPairs: pairs,
      brierMean: pairs == 0
          ? 0
          : ((m['brierSum'] as num?)?.toDouble() ?? 0) / pairs,
      truePositives: (m['tp'] as num?)?.toInt() ?? 0,
      falsePositives: (m['fp'] as num?)?.toInt() ?? 0,
      falseNegatives: (m['fn'] as num?)?.toInt() ?? 0,
      lastGradedDay:
          DateTime.tryParse((m['lastGradedDay'] ?? '').toString()),
      updatedAt: DateTime.tryParse((m['updatedAt'] ?? '').toString()),
    );
  }
}

/// Persists trained forecast models, training telemetry, and the
/// continuous-learning bookkeeping under `ai_forecast/`.
class ForecastModelStore {
  final DatabaseReference _root;
  final DatabaseReference _agents;

  ForecastModelStore({FirebaseDatabase? database})
      : _root = (database ?? FirebaseDatabase.instance).ref('ai_forecast'),
        _agents = (database ?? FirebaseDatabase.instance).ref('ai_agents');

  /// SuperAdmin fleet switches for the predictive agent
  /// (`ai_agents/predictive`). Missing/unreadable nodes default to enabled so
  /// the learner never silently dies on a rules hiccup.
  Future<bool> predictiveAgentFlag(String setting) async {
    try {
      final snap = await _agents.child('predictive/settings/$setting').get();
      return snap.value != false;
    } catch (_) {
      return true;
    }
  }

  /// Saves the trained ensemble so every Production Manager dashboard can run
  /// on-device inference with identical trees.
  Future<void> saveModel({
    required GradientBoostModel model,
    required String datasetName,
    required int sampleCount,
    required double valLoss,
    required double valAccuracy,
    required bool learning,
    required List<RoundStat> rounds,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _root.child('model').set({
      'weights': model.toJsonString(),
      'algo': 'gbdt',
      'featureCount': model.featureCount,
      'rounds': model.roundsPerType,
      'adaptedRounds': model.adaptedRounds,
      'types': kForecastAlertTypes,
      // Tuned per-type decision thresholds, duplicated outside the weights
      // blob so the Cloudflare worker can grade outcomes without parsing the
      // full ensemble JSON.
      'thresholds': [for (final t in model.thresholds) t],
      'trainedAt': now,
      'datasetName': datasetName,
      'sampleCount': sampleCount,
      'valLoss': double.parse(valLoss.toStringAsFixed(6)),
      'valAccuracy': double.parse(valAccuracy.toStringAsFixed(6)),
      'learning': learning,
      'roundsRun': rounds.isEmpty ? 0 : rounds.last.round,
      'version': 1,
    });
    await _root.child('history').push().set({
      'trainedAt': now,
      'datasetName': datasetName,
      'sampleCount': sampleCount,
      'valLoss': double.parse(valLoss.toStringAsFixed(6)),
      'valAccuracy': double.parse(valAccuracy.toStringAsFixed(6)),
      'learning': learning,
      'roundsRun': rounds.isEmpty ? 0 : rounds.last.round,
    });
    // A fresh deployment starts a fresh self-evaluation ledger.
    await _root.child('accuracy/latest').remove();
  }

  /// Overwrites the deployed trees after a continuous-learning adaptation,
  /// keeping the original training metadata.
  Future<void> saveAdaptedModel({
    required GradientBoostModel model,
    required int previousVersion,
  }) async {
    await _root.child('model').update({
      'weights': model.toJsonString(),
      'adaptedRounds': model.adaptedRounds,
      'thresholds': [for (final t in model.thresholds) t],
      'lastAdaptedAt': DateTime.now().toUtc().toIso8601String(),
      'version': previousVersion + 1,
    });
  }

  Future<TrainedForecastModel?> loadModel() async {
    final snap = await _root.child('model').get();
    return TrainedForecastModel.fromSnapshotValue(snap.value);
  }

  /// Live stream of the deployed model (null while none is trained).
  Stream<TrainedForecastModel?> modelStream() => _root
      .child('model')
      .onValue
      .map((event) =>
          TrainedForecastModel.fromSnapshotValue(event.snapshot.value));

  // ── Training telemetry ────────────────────────────────────────────────────

  /// Mirrors live training telemetry so other admins can watch a run.
  Future<void> writeTrainingStatus({
    required String status,
    required double progress,
    required String message,
    List<RoundStat> rounds = const [],
  }) async {
    try {
      await _root.child('training/latest').set({
        'status': status,
        'progress': double.parse(progress.toStringAsFixed(4)),
        'message': message,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'rounds': rounds
            .skip(rounds.length > 120 ? rounds.length - 120 : 0)
            .map((e) => e.toMap())
            .toList(),
      });
    } catch (_) {
      // Telemetry must never break a training run.
    }
  }

  /// Live stream of the shared training telemetry (lets a second console
  /// spectate a run owned by another session).
  Stream<Map<String, dynamic>?> trainingStatusStream() =>
      _root.child('training/latest').onValue.map((event) {
        final v = event.snapshot.value;
        return v is Map ? Map<String, dynamic>.from(v) : null;
      });

  // ── Run checkpointing ─────────────────────────────────────────────────────
  //
  // A training run survives tab switches in-memory (the controller is app
  // global), and survives full page/app restarts through this checkpoint:
  // trees + round stats + config land under `ai_forecast/training/checkpoint`
  // and the uploaded dataset under `ai_forecast/training/dataset`, so any
  // SuperAdmin session can pick the run back up exactly where it stopped.

  /// Persists the uploaded dataset (compact row encoding) so an interrupted
  /// run can be resumed after the app or browser tab is closed.
  Future<void> saveDatasetBlob({
    required String name,
    required String kind,
    required String blob,
    required int recordCount,
  }) async {
    await _root.child('training/dataset').set({
      'name': name,
      'kind': kind,
      'recordCount': recordCount,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'blob': blob,
    });
  }

  Future<Map<String, dynamic>?> loadDatasetBlob() async {
    final snap = await _root.child('training/dataset').get();
    final v = snap.value;
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// Writes the resumable snapshot of an in-flight (or just-finished) run.
  Future<void> saveCheckpoint({
    required String status, // running | done | stopped | failed
    required String owner,
    required GradientBoostModel model,
    required int bestRound,
    required ForecastTrainingConfig config,
    required List<RoundStat> rounds,
    required String datasetName,
    required int sampleCount,
    required bool isLearning,
  }) async {
    await _root.child('training/checkpoint').set({
      'status': status,
      'owner': owner,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'weights': model.toJsonString(),
      'bestRound': bestRound,
      'config': config.toMap(),
      'round': rounds.isEmpty ? 0 : rounds.last.round,
      'roundStats': rounds
          .skip(rounds.length > 300 ? rounds.length - 300 : 0)
          .map((e) => e.toMap())
          .toList(),
      'datasetName': datasetName,
      'sampleCount': sampleCount,
      'isLearning': isLearning,
    });
  }

  Future<Map<String, dynamic>?> loadCheckpoint() async {
    final snap = await _root.child('training/checkpoint').get();
    final v = snap.value;
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Future<void> clearCheckpoint() async {
    await _root.child('training/checkpoint').remove();
  }

  // ── Continuous learning: outcome grading ────────────────────────────────
  //
  // Every day the engine snapshots what the deployed model predicted for
  // tomorrow under `accuracy/pending/{yyyy-MM-dd}`. Once that day has fully
  // elapsed, any dashboard grades the snapshot against the alerts that
  // actually happened, folds the result into the rolling ledger at
  // `accuracy/latest`, and archives the day under `accuracy/history`.

  static String dayKey(DateTime day) {
    final d = day.toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> savePendingOutcome({
    required DateTime targetDay,
    required int modelVersion,
    required Map<String, Map<String, double>> machineProbabilities,
  }) async {
    await _root.child('accuracy/pending/${dayKey(targetDay)}').set({
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'modelVersion': modelVersion,
      'machines': {
        for (final e in machineProbabilities.entries)
          // RTDB paths cannot contain '|'.
          e.key.replaceAll('|', '~'): e.value,
      },
    });
  }

  Future<Map<String, dynamic>?> loadPendingOutcomes() async {
    final snap = await _root.child('accuracy/pending').get();
    final v = snap.value;
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Future<void> removePendingOutcome(String dateKey) async {
    await _root.child('accuracy/pending/$dateKey').remove();
  }

  /// Folds one graded day into the rolling ledger and archives it.
  Future<void> recordGradedDay({
    required String dateKey,
    required int pairs,
    required double brierSum,
    required int tp,
    required int fp,
    required int fn,
  }) async {
    final ref = _root.child('accuracy/latest');
    final snap = await ref.get();
    final prev = snap.value is Map
        ? Map<String, dynamic>.from(snap.value as Map)
        : <String, dynamic>{};
    int prevInt(String k) => (prev[k] as num?)?.toInt() ?? 0;
    final prevBrier = (prev['brierSum'] as num?)?.toDouble() ?? 0;
    await ref.set({
      'gradedDays': prevInt('gradedDays') + 1,
      'gradedPairs': prevInt('gradedPairs') + pairs,
      'brierSum': double.parse((prevBrier + brierSum).toStringAsFixed(6)),
      'tp': prevInt('tp') + tp,
      'fp': prevInt('fp') + fp,
      'fn': prevInt('fn') + fn,
      'lastGradedDay': dateKey,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _root.child('accuracy/history/$dateKey').set({
      'pairs': pairs,
      'brier':
          double.parse((pairs == 0 ? 0 : brierSum / pairs).toStringAsFixed(6)),
      'tp': tp,
      'fp': fp,
      'fn': fn,
      'gradedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<ForecastAccuracy?> loadAccuracy() async {
    final snap = await _root.child('accuracy/latest').get();
    return ForecastAccuracy.fromSnapshotValue(snap.value);
  }

  Stream<ForecastAccuracy?> accuracyStream() =>
      _root.child('accuracy/latest').onValue.map(
          (event) => ForecastAccuracy.fromSnapshotValue(event.snapshot.value));

  // ── Continuous learning: adaptation lock ─────────────────────────────────

  /// Claims the cross-dashboard adaptation lock. Returns true when this
  /// session may adapt the deployed model now.
  Future<bool> tryClaimAdaptationLock(String sessionId,
      {Duration ttl = const Duration(minutes: 10)}) async {
    final ref = _root.child('learning/lock');
    final snap = await ref.get();
    final v = snap.value;
    if (v is Map) {
      final at = DateTime.tryParse((v['at'] ?? '').toString());
      if (at != null && DateTime.now().toUtc().difference(at.toUtc()) < ttl) {
        return false;
      }
    }
    await ref.set({
      'owner': sessionId,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    // Read back: last writer wins in RTDB, so confirm we kept the claim.
    final confirm = await ref.get();
    final c = confirm.value;
    return c is Map && c['owner'] == sessionId;
  }

  Future<void> releaseAdaptationLock(String sessionId) async {
    final ref = _root.child('learning/lock');
    final snap = await ref.get();
    final v = snap.value;
    if (v is Map && v['owner'] == sessionId) {
      await ref.remove();
    }
  }
}

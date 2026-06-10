import 'dart:typed_data';

/// Canonical alert types the forecaster learns. Order matters: it defines the
/// output vector layout of the network and must stay aligned with the
/// Cloudflare worker's `_LSTM_TYPES`.
const List<String> kLstmAlertTypes = [
  'qualite',
  'maintenance',
  'defaut_produit',
  'manque_ressource',
];

/// Feature column order for each daily row. Mirrors the worker's
/// `_LSTM_FEATURE_COLS` so models stay interchangeable with edge tooling.
const List<String> kLstmFeatureCols = [
  'is_qualite',
  'is_maintenance',
  'is_defaut_produit',
  'is_manque_ressource',
  'critical_count',
  'days_since_failure',
  'hour',
  'dayofweek',
];

/// A single normalized alert event extracted from any uploaded data source.
class AlertRecord {
  final DateTime timestamp;
  final String type;
  final String usine;
  final int convoyeur;
  final int poste;
  final bool isCritical;

  const AlertRecord({
    required this.timestamp,
    required this.type,
    required this.usine,
    this.convoyeur = 0,
    this.poste = 0,
    this.isCritical = false,
  });

  String get machineKey => '$usine|$convoyeur|$poste';
}

/// Aggregate description of a parsed dataset, displayed before training.
class DatasetSummary {
  final String sourceName;
  final String sourceKind;
  final int totalRows;
  final int parsedRows;
  final int skippedRows;
  final Map<String, int> typeCounts;
  final Map<String, int> factoryCounts;
  final DateTime? firstTimestamp;
  final DateTime? lastTimestamp;
  final int machineCount;

  const DatasetSummary({
    required this.sourceName,
    required this.sourceKind,
    required this.totalRows,
    required this.parsedRows,
    required this.skippedRows,
    required this.typeCounts,
    required this.factoryCounts,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required this.machineCount,
  });

  int get daySpan {
    if (firstTimestamp == null || lastTimestamp == null) return 0;
    return lastTimestamp!.difference(firstTimestamp!).inDays + 1;
  }
}

/// One supervised training sample: a [seqLen]x[features] window of scaled
/// daily rows for one machine, labelled with the next day's alert types.
class TrainingSample {
  final List<Float64List> window;
  final Float64List target;
  final String machineKey;

  const TrainingSample({
    required this.window,
    required this.target,
    required this.machineKey,
  });
}

/// Hyperparameters. [auto] picks sensible values from the dataset shape so
/// the SuperAdmin does not need ML expertise, but every value stays editable.
class LstmTrainingConfig {
  final int seqLen;
  final int hiddenSize;
  final int epochs;
  final double learningRate;
  final int batchSize;
  final double valSplit;
  final int patience;
  final int seed;

  const LstmTrainingConfig({
    this.seqLen = 14,
    required this.hiddenSize,
    required this.epochs,
    required this.learningRate,
    required this.batchSize,
    this.valSplit = 0.2,
    this.patience = 8,
    this.seed = 42,
  });

  factory LstmTrainingConfig.auto(int sampleCount) {
    if (sampleCount < 400) {
      return const LstmTrainingConfig(
        hiddenSize: 16,
        epochs: 60,
        learningRate: 0.01,
        batchSize: 16,
      );
    }
    if (sampleCount < 3000) {
      return const LstmTrainingConfig(
        hiddenSize: 24,
        epochs: 40,
        learningRate: 0.006,
        batchSize: 32,
      );
    }
    return const LstmTrainingConfig(
      hiddenSize: 32,
      epochs: 30,
      learningRate: 0.004,
      batchSize: 48,
    );
  }

  LstmTrainingConfig copyWith({
    int? seqLen,
    int? hiddenSize,
    int? epochs,
    double? learningRate,
    int? batchSize,
    double? valSplit,
    int? patience,
    int? seed,
  }) {
    return LstmTrainingConfig(
      seqLen: seqLen ?? this.seqLen,
      hiddenSize: hiddenSize ?? this.hiddenSize,
      epochs: epochs ?? this.epochs,
      learningRate: learningRate ?? this.learningRate,
      batchSize: batchSize ?? this.batchSize,
      valSplit: valSplit ?? this.valSplit,
      patience: patience ?? this.patience,
      seed: seed ?? this.seed,
    );
  }
}

/// Metrics produced at the end of each training epoch — these feed the live
/// learning curves in the SuperAdmin console.
class EpochStat {
  final int epoch;
  final double trainLoss;
  final double valLoss;
  final double valAccuracy;
  final double valF1;

  const EpochStat({
    required this.epoch,
    required this.trainLoss,
    required this.valLoss,
    required this.valAccuracy,
    required this.valF1,
  });

  Map<String, dynamic> toMap() => {
        'epoch': epoch,
        'trainLoss': trainLoss,
        'valLoss': valLoss,
        'valAccuracy': valAccuracy,
        'valF1': valF1,
      };
}

enum LstmTrainingPhase { preparing, training, evaluating, done, stopped, failed }

/// Streamed progress update from the trainer.
class LstmTrainingUpdate {
  final LstmTrainingPhase phase;

  /// 0..1 overall progress across all planned epochs.
  final double progress;
  final List<EpochStat> epochs;
  final String message;

  /// True once the loss trajectory proves the network is genuinely learning
  /// (validation loss materially below its starting point).
  final bool isLearning;

  const LstmTrainingUpdate({
    required this.phase,
    required this.progress,
    required this.epochs,
    required this.message,
    required this.isLearning,
  });
}

/// A per-machine forecast for the next 24 hours.
class MachineForecast {
  final String usine;
  final int convoyeur;
  final int poste;

  /// Probability per canonical type, aligned with [kLstmAlertTypes].
  final Map<String, double> typeProbabilities;

  const MachineForecast({
    required this.usine,
    required this.convoyeur,
    required this.poste,
    required this.typeProbabilities,
  });

  /// Probability that at least one alert of any type occurs.
  double get anyProbability {
    var noAlert = 1.0;
    for (final p in typeProbabilities.values) {
      noAlert *= (1.0 - p);
    }
    return (1.0 - noAlert).clamp(0.0, 1.0);
  }

  String get topType {
    var best = kLstmAlertTypes.first;
    var bestP = -1.0;
    typeProbabilities.forEach((k, v) {
      if (v > bestP) {
        bestP = v;
        best = k;
      }
    });
    return best;
  }

  double get topTypeProbability => typeProbabilities[topType] ?? 0;

  Map<String, dynamic> toMap() => {
        'usine': usine,
        'convoyeur': convoyeur,
        'poste': poste,
        'probabilities': typeProbabilities,
        'anyProbability': anyProbability,
        'topType': topType,
      };
}

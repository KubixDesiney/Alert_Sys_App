import 'dart:typed_data';

/// Default alert types the forecaster learns when no tenant registry is
/// supplied. Order matters: it defines the output vector layout of the model.
///
/// The forecaster is **type-dynamic**: the active set is threaded in at train
/// time from `AlertTypeRegistry` and persisted into the model metadata, so a
/// deployment that configures its own alert types trains a matching per-type
/// ensemble. This constant is only the fallback / historical standard set.
const List<String> kForecastAlertTypes = [
  'qualite',
  'maintenance',
  'defaut_produit',
  'manque_ressource',
];

/// Daily (machine-day) feature columns for an arbitrary ordered [types] list:
/// one `is_<type>` flag per type, then the four shared columns. Generalizes
/// [kDailyFeatureCols] (its N=4 case). Width = `types.length + 4`.
List<String> dailyFeatureColsFor(List<String> types) => [
      for (final t in types) 'is_$t',
      'critical_count',
      'days_since_failure',
      'hour',
      'dayofweek',
    ];

/// Engineered tabular feature columns for an arbitrary ordered [types] list.
/// Generalizes [kForecastFeatureCols] (its N=4 case). Width = `3 * N + 13`.
List<String> forecastFeatureColsFor(List<String> types) => [
      // Today's machine-day snapshot: per-type counts + shared.
      for (final t in types) '${t}_count',
      'critical_count',
      'days_since_failure',
      'mean_hour',
      'dayofweek',
      // The day being predicted.
      'target_dayofweek',
      'target_is_weekend',
      // Short-term any-type lags.
      'total_today',
      'total_yesterday',
      'total_2d_ago',
      // Per-type 7-day rolling counts.
      for (final t in types) '${t}_7d',
      // Rolling totals and tempo trend.
      'total_7d',
      'total_14d',
      'trend_7d',
      // Per-type recency (days since last occurrence, capped).
      for (final t in types) '${t}_days_since',
      // Critical pressure.
      'critical_7d',
    ];

/// Feature-vector width for a given number of alert types (`3 * N + 13`).
int forecastFeatureCountFor(int typeCount) => 3 * typeCount + 13;

/// Base per-day feature columns of a machine-day row. Mirrors the worker's
/// `_LSTM_FEATURE_COLS` daily schema so daily rows stay interchangeable with
/// edge tooling.
const List<String> kDailyFeatureCols = [
  'is_qualite',
  'is_maintenance',
  'is_defaut_produit',
  'is_manque_ressource',
  'critical_count',
  'days_since_failure',
  'hour',
  'dayofweek',
];

/// Engineered tabular feature columns consumed by the gradient-boosted trees.
/// Trees are scale-invariant, so these are raw counts/days — no normalization
/// is needed or persisted.
const List<String> kForecastFeatureCols = [
  // Today's machine-day snapshot.
  'qualite_count',
  'maintenance_count',
  'defaut_produit_count',
  'manque_ressource_count',
  'critical_count',
  'days_since_failure',
  'mean_hour',
  'dayofweek',
  // The day being predicted (tomorrow's calendar context).
  'target_dayofweek',
  'target_is_weekend',
  // Short-term lags (any-type totals).
  'total_today',
  'total_yesterday',
  'total_2d_ago',
  // Per-type 7-day rolling counts.
  'qualite_7d',
  'maintenance_7d',
  'defaut_produit_7d',
  'manque_ressource_7d',
  // Rolling totals and tempo trend.
  'total_7d',
  'total_14d',
  'trend_7d',
  // Per-type recency (days since last occurrence, capped).
  'qualite_days_since',
  'maintenance_days_since',
  'defaut_produit_days_since',
  'manque_ressource_days_since',
  // Critical pressure.
  'critical_7d',
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

/// One supervised training sample: an engineered feature row for one
/// machine-day, labelled with the next day's alert types.
class FeatureSample {
  final Float64List features; // aligned with kForecastFeatureCols
  final Float64List target; // aligned with kForecastAlertTypes
  final String machineKey;

  const FeatureSample({
    required this.features,
    required this.target,
    required this.machineKey,
  });
}

/// Gradient-boosting hyperparameters. [auto] picks values from the dataset
/// shape so operators can just upload data and train — every value stays
/// visible and editable in the console.
class ForecastTrainingConfig {
  /// Boosting rounds; each round grows one tree per alert type.
  final int rounds;
  final double learningRate;
  final int maxDepth;
  final int minSamplesLeaf;

  /// Row subsample ratio per tree (stochastic gradient boosting).
  final double subsample;

  /// Feature subsample ratio per tree.
  final double colsample;

  /// L2 regularization on leaf weights (XGBoost lambda).
  final double l2;
  final double valSplit;
  final int patience;
  final int seed;

  /// Upper bound on the positive-class weight applied to minority alert days
  /// (neg/pos ratio, clamped to this cap). Raising this makes the loss punish
  /// missed alerts much harder than false alarms — the main lever for severely
  /// imbalanced datasets where alert days are rare.
  final double posWeightCap;

  const ForecastTrainingConfig({
    required this.rounds,
    required this.learningRate,
    required this.maxDepth,
    required this.minSamplesLeaf,
    this.subsample = 0.85,
    this.colsample = 0.9,
    this.l2 = 1.0,
    this.valSplit = 0.2,
    this.patience = 25,
    this.seed = 42,
    this.posWeightCap = 50.0,
  });

  factory ForecastTrainingConfig.auto(int sampleCount) {
    if (sampleCount < 400) {
      return const ForecastTrainingConfig(
        rounds: 120,
        learningRate: 0.08,
        maxDepth: 3,
        minSamplesLeaf: 8,
        subsample: 0.9,
        colsample: 1.0,
        l2: 1.0,
        patience: 20,
        posWeightCap: 50.0,
      );
    }
    if (sampleCount < 3000) {
      return const ForecastTrainingConfig(
        rounds: 200,
        learningRate: 0.06,
        maxDepth: 4,
        minSamplesLeaf: 16,
        subsample: 0.85,
        colsample: 0.9,
        l2: 1.0,
        patience: 25,
        posWeightCap: 50.0,
      );
    }
    return const ForecastTrainingConfig(
      rounds: 300,
      learningRate: 0.05,
      maxDepth: 5,
      minSamplesLeaf: 24,
      subsample: 0.8,
      colsample: 0.8,
      l2: 1.5,
      patience: 30,
      posWeightCap: 75.0,
    );
  }

  ForecastTrainingConfig copyWith({
    int? rounds,
    double? learningRate,
    int? maxDepth,
    int? minSamplesLeaf,
    double? subsample,
    double? colsample,
    double? l2,
    double? valSplit,
    int? patience,
    int? seed,
    double? posWeightCap,
  }) {
    return ForecastTrainingConfig(
      rounds: rounds ?? this.rounds,
      learningRate: learningRate ?? this.learningRate,
      maxDepth: maxDepth ?? this.maxDepth,
      minSamplesLeaf: minSamplesLeaf ?? this.minSamplesLeaf,
      subsample: subsample ?? this.subsample,
      colsample: colsample ?? this.colsample,
      l2: l2 ?? this.l2,
      valSplit: valSplit ?? this.valSplit,
      patience: patience ?? this.patience,
      seed: seed ?? this.seed,
      posWeightCap: posWeightCap ?? this.posWeightCap,
    );
  }

  Map<String, dynamic> toMap() => {
        'rounds': rounds,
        'learningRate': learningRate,
        'maxDepth': maxDepth,
        'minSamplesLeaf': minSamplesLeaf,
        'subsample': subsample,
        'colsample': colsample,
        'l2': l2,
        'valSplit': valSplit,
        'patience': patience,
        'seed': seed,
        'posWeightCap': posWeightCap,
      };

  factory ForecastTrainingConfig.fromMap(Map<String, dynamic> m) =>
      ForecastTrainingConfig(
        rounds: (m['rounds'] as num?)?.toInt() ?? 200,
        learningRate: (m['learningRate'] as num?)?.toDouble() ?? 0.06,
        maxDepth: (m['maxDepth'] as num?)?.toInt() ?? 4,
        minSamplesLeaf: (m['minSamplesLeaf'] as num?)?.toInt() ?? 16,
        subsample: (m['subsample'] as num?)?.toDouble() ?? 0.85,
        colsample: (m['colsample'] as num?)?.toDouble() ?? 0.9,
        l2: (m['l2'] as num?)?.toDouble() ?? 1.0,
        valSplit: (m['valSplit'] as num?)?.toDouble() ?? 0.2,
        patience: (m['patience'] as num?)?.toInt() ?? 25,
        seed: (m['seed'] as num?)?.toInt() ?? 42,
        posWeightCap: (m['posWeightCap'] as num?)?.toDouble() ?? 50.0,
      );
}

/// Metrics produced after each boosting round — these feed the live learning
/// curves in the SuperAdmin console. Round 0 is the pre-boosting baseline
/// (prior log-odds only), so the curves show the real improvement the trees
/// deliver.
class RoundStat {
  final int round;
  final double trainLoss;
  final double valLoss;
  final double valAccuracy;
  final double valF1;

  const RoundStat({
    required this.round,
    required this.trainLoss,
    required this.valLoss,
    required this.valAccuracy,
    required this.valF1,
  });

  Map<String, dynamic> toMap() => {
        'round': round,
        'trainLoss': trainLoss,
        'valLoss': valLoss,
        'valAccuracy': valAccuracy,
        'valF1': valF1,
      };
}

enum ForecastTrainingPhase { preparing, training, evaluating, done, stopped, failed }

/// Streamed progress update from the trainer.
class ForecastTrainingUpdate {
  final ForecastTrainingPhase phase;

  /// 0..1 overall progress across all planned rounds.
  final double progress;
  final List<RoundStat> rounds;
  final String message;

  /// True once the loss trajectory proves the model is genuinely learning
  /// (validation loss materially below its pre-boosting baseline).
  final bool isLearning;

  const ForecastTrainingUpdate({
    required this.phase,
    required this.progress,
    required this.rounds,
    required this.message,
    required this.isLearning,
  });
}

/// A per-machine forecast for the next 24 hours.
class MachineForecast {
  final String usine;
  final int convoyeur;
  final int poste;

  /// Probability per canonical type, aligned with [kForecastAlertTypes].
  final Map<String, double> typeProbabilities;

  const MachineForecast({
    required this.usine,
    required this.convoyeur,
    required this.poste,
    required this.typeProbabilities,
  });

  String get machineKey => '$usine|$convoyeur|$poste';

  /// Probability that at least one alert of any type occurs.
  double get anyProbability {
    var noAlert = 1.0;
    for (final p in typeProbabilities.values) {
      noAlert *= (1.0 - p);
    }
    return (1.0 - noAlert).clamp(0.0, 1.0);
  }

  String get topType {
    var best = kForecastAlertTypes.first;
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

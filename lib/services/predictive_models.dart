class MorningBriefing {
  final String date;
  final String summary;
  final String? generatedAt;
  final String? model;
  final int resolutionRate;
  final Map<String, dynamic> stats;
  final String? topType;
  final int? topTypeCount;
  final String? topFactory;
  final int? topFactoryCount;

  MorningBriefing({
    required this.date,
    required this.summary,
    this.generatedAt,
    this.model,
    this.resolutionRate = 0,
    this.stats = const {},
    this.topType,
    this.topTypeCount,
    this.topFactory,
    this.topFactoryCount,
  });

  factory MorningBriefing.fromMap(Map<String, dynamic> m) {
    final tt = m['topType'];
    final tf = m['topFactory'];
    return MorningBriefing(
      date: (m['date'] ?? '').toString(),
      summary: (m['summary'] ?? '').toString(),
      generatedAt: m['generatedAt']?.toString(),
      model: m['model']?.toString(),
      resolutionRate: (m['resolutionRate'] as num?)?.toInt() ?? 0,
      stats: m['stats'] is Map
          ? Map<String, dynamic>.from(m['stats'] as Map)
          : const {},
      topType: tt is Map ? tt['type']?.toString() : null,
      topTypeCount: tt is Map ? (tt['count'] as num?)?.toInt() : null,
      topFactory: tf is Map ? tf['name']?.toString() : null,
      topFactoryCount: tf is Map ? (tf['count'] as num?)?.toInt() : null,
    );
  }

  bool get isFresh {
    if (generatedAt == null) return false;
    final ts = DateTime.tryParse(generatedAt!);
    if (ts == null) return false;
    return DateTime.now().difference(ts).inHours < 26;
  }
}

class PredictiveModel {
  final Map<String, RiskCurve> curves;
  final List<PredictedFailure> predictions;
  final List<FactoryRisk> factoryRisk;
  final DateTime? generatedAt;

  PredictiveModel({
    required this.curves,
    required this.predictions,
    required this.factoryRisk,
    this.generatedAt,
  });

  factory PredictiveModel.fromMap(Map<String, dynamic> m) {
    final curvesRaw = m['curves'];
    final preds = m['predictions'];
    final fact = m['factoryRisk'];
    return PredictiveModel(
      curves: curvesRaw is Map
          ? curvesRaw.map((k, v) => MapEntry(
                k.toString(),
                RiskCurve.fromMap(Map<String, dynamic>.from(v as Map)),
              ))
          : const {},
      predictions: preds is List
          ? preds
              .whereType<Map>()
              .map(
                  (e) => PredictedFailure.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      factoryRisk: fact is List
          ? fact
              .whereType<Map>()
              .map((e) => FactoryRisk.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      generatedAt: DateTime.tryParse((m['generatedAt'] ?? '').toString()),
    );
  }
}

class RiskCurve {
  final List<RiskBucket> buckets;
  final double total24h;
  final double hourlyRate;
  final int peakHour;
  final double peakProbability;
  final double avgProbability;
  final int sampleSize;

  RiskCurve({
    required this.buckets,
    required this.total24h,
    required this.hourlyRate,
    required this.peakHour,
    required this.peakProbability,
    required this.avgProbability,
    required this.sampleSize,
  });

  factory RiskCurve.fromMap(Map<String, dynamic> m) {
    final raw = m['buckets'];
    return RiskCurve(
      buckets: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => RiskBucket.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      total24h: (m['total24h'] as num?)?.toDouble() ?? 0,
      hourlyRate: (m['hourlyRate'] as num?)?.toDouble() ?? 0,
      peakHour: (m['peakHour'] as num?)?.toInt() ?? 0,
      peakProbability: (m['peakProbability'] as num?)?.toDouble() ?? 0,
      avgProbability: (m['avgProbability'] as num?)?.toDouble() ?? 0,
      sampleSize: (m['sampleSize'] as num?)?.toInt() ?? 0,
    );
  }
}

class RiskBucket {
  final int offsetHours;
  final int startHour;
  final int endHour;
  final double probability;
  final double expected;

  RiskBucket({
    required this.offsetHours,
    required this.startHour,
    required this.endHour,
    required this.probability,
    required this.expected,
  });

  factory RiskBucket.fromMap(Map<String, dynamic> m) => RiskBucket(
        offsetHours: (m['offsetHours'] as num?)?.toInt() ?? 0,
        startHour: (m['startHour'] as num?)?.toInt() ?? 0,
        endHour: (m['endHour'] as num?)?.toInt() ?? 0,
        probability: (m['probability'] as num?)?.toDouble() ?? 0,
        expected: (m['expected'] as num?)?.toDouble() ?? 0,
      );
}

class PredictedFailure {
  final String factoryId;
  final String usine;
  final int convoyeur;
  final int poste;
  final String type;
  final int confidence;
  final int pastCount;
  final int criticalCount;
  final DateTime? lastTs;
  final double? etaHours;

  PredictedFailure({
    required this.factoryId,
    required this.usine,
    required this.convoyeur,
    required this.poste,
    required this.type,
    required this.confidence,
    required this.pastCount,
    required this.criticalCount,
    this.lastTs,
    this.etaHours,
  });

  factory PredictedFailure.fromMap(Map<String, dynamic> m) => PredictedFailure(
        factoryId: (m['factoryId'] ?? '').toString(),
        usine: (m['usine'] ?? '').toString(),
        convoyeur: (m['convoyeur'] as num?)?.toInt() ?? 0,
        poste: (m['poste'] as num?)?.toInt() ?? 0,
        type: (m['type'] ?? '').toString(),
        confidence: (m['confidence'] as num?)?.toInt() ?? 0,
        pastCount: (m['pastCount'] as num?)?.toInt() ?? 0,
        criticalCount: (m['criticalCount'] as num?)?.toInt() ?? 0,
        lastTs: DateTime.tryParse((m['lastTs'] ?? '').toString()),
        etaHours: (m['etaHours'] as num?)?.toDouble(),
      );
}

class FactoryRisk {
  final String id;
  final String name;
  final double score;
  final int count;
  FactoryRisk({
    required this.id,
    required this.name,
    required this.score,
    required this.count,
  });
  factory FactoryRisk.fromMap(Map<String, dynamic> m) => FactoryRisk(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        score: (m['score'] as num?)?.toDouble() ?? 0,
        count: (m['count'] as num?)?.toInt() ?? 0,
      );
}

class AssigneeSuggestion {
  final String alertId;
  final String? bestUid;
  final String? bestName;
  final List<String> reasons;
  final int confidencePct;
  final int candidateCount;
  final bool busy;
  final List<RunnerUp> runners;

  AssigneeSuggestion({
    required this.alertId,
    this.bestUid,
    this.bestName,
    this.reasons = const [],
    this.confidencePct = 0,
    this.candidateCount = 0,
    this.busy = false,
    this.runners = const [],
  });

  factory AssigneeSuggestion.fromMap(Map<String, dynamic> m) {
    final best = m['best'];
    final runnersRaw = m['runners'];
    return AssigneeSuggestion(
      alertId: (m['alertId'] ?? '').toString(),
      bestUid: best is Map ? best['uid']?.toString() : null,
      bestName: best is Map ? best['name']?.toString() : null,
      reasons: best is Map && best['reasons'] is List
          ? (best['reasons'] as List).map((e) => e.toString()).toList()
          : const [],
      confidencePct: (m['confidencePct'] as num?)?.toInt() ?? 0,
      candidateCount: (m['candidateCount'] as num?)?.toInt() ?? 0,
      busy: best is Map ? (best['busy'] == true) : false,
      runners: runnersRaw is List
          ? runnersRaw
              .whereType<Map>()
              .map((e) => RunnerUp.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class RunnerUp {
  final String uid;
  final String name;
  final double score;
  final bool busy;
  RunnerUp({
    required this.uid,
    required this.name,
    required this.score,
    required this.busy,
  });
  factory RunnerUp.fromMap(Map<String, dynamic> m) => RunnerUp(
        uid: (m['uid'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        score: (m['score'] as num?)?.toDouble() ?? 0,
        busy: m['busy'] == true,
      );
}

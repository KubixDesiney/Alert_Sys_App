import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'predictive_models.dart';

/// Aggregated accuracy of past predictive snapshots, written by the worker's
/// validatePredictions() to ai_predictions/performance/latest.
class PredictiveAccuracy {
  final int totalSnapshots;
  final double averageAccuracy; // 0.0 – 1.0
  final String? lastValidatedUtc;
  const PredictiveAccuracy({
    required this.totalSnapshots,
    required this.averageAccuracy,
    this.lastValidatedUtc,
  });

  factory PredictiveAccuracy.fromMap(Map<String, dynamic> m) =>
      PredictiveAccuracy(
        totalSnapshots: (m['totalSnapshots'] as num?)?.toInt() ?? 0,
        averageAccuracy:
            (m['averageAccuracy'] as num?)?.toDouble() ?? 0.0,
        lastValidatedUtc: m['lastValidatedUtc'] as String?,
      );
}

class PredictiveIntelStreamService {
  PredictiveIntelStreamService._({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  static final PredictiveIntelStreamService instance =
      PredictiveIntelStreamService._();

  final FirebaseDatabase _db;
  StreamSubscription<DatabaseEvent>? _briefingSub;
  StreamSubscription<DatabaseEvent>? _predictionsSub;
  StreamSubscription<DatabaseEvent>? _accuracySub;
  final _briefingController = StreamController<MorningBriefing?>.broadcast();
  final _predictionsController = StreamController<PredictiveModel?>.broadcast();
  final _accuracyController =
      StreamController<PredictiveAccuracy?>.broadcast();
  MorningBriefing? _lastBriefing;
  PredictiveModel? _lastPredictions;
  PredictiveAccuracy? _lastAccuracy;

  Stream<MorningBriefing?> briefingStream() {
    _ensureBriefingSubscription();
    return _briefingController.stream;
  }

  Stream<PredictiveModel?> predictionsStream() {
    _ensurePredictionsSubscription();
    return _predictionsController.stream;
  }

  Stream<PredictiveAccuracy?> accuracyStream() {
    _ensureAccuracySubscription();
    return _accuracyController.stream;
  }

  PredictiveAccuracy? get lastAccuracy => _lastAccuracy;

  void _ensureBriefingSubscription() {
    _briefingSub ??= _db.ref('ai_briefing/latest').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is Map) {
        _lastBriefing =
            MorningBriefing.fromMap(Map<String, dynamic>.from(value));
      } else {
        _lastBriefing = null;
      }
      _briefingController.add(_lastBriefing);
    });
  }

  void _ensurePredictionsSubscription() {
    _predictionsSub ??=
        _db.ref('ai_predictions/latest').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is Map) {
        _lastPredictions =
            PredictiveModel.fromMap(Map<String, dynamic>.from(value));
      } else {
        _lastPredictions = null;
      }
      _predictionsController.add(_lastPredictions);
    });
  }

  void _ensureAccuracySubscription() {
    _accuracySub ??=
        _db.ref('ai_predictions/performance/latest').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is Map) {
        _lastAccuracy =
            PredictiveAccuracy.fromMap(Map<String, dynamic>.from(value));
      } else {
        _lastAccuracy = null;
      }
      _accuracyController.add(_lastAccuracy);
    });
  }

  void dispose() {
    _briefingSub?.cancel();
    _predictionsSub?.cancel();
    _accuracySub?.cancel();
    _briefingController.close();
    _predictionsController.close();
    _accuracyController.close();
  }
}

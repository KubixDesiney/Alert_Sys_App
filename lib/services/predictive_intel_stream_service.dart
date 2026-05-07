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
  // Per-factory subscriptions and controllers (null key = global).
  final Map<String?, StreamSubscription<DatabaseEvent>> _briefingSubs = {};
  final Map<String?, StreamController<MorningBriefing?>> _briefingControllers = {};
  final Map<String?, MorningBriefing?> _lastBriefings = {};
  StreamSubscription<DatabaseEvent>? _predictionsSub;
  StreamSubscription<DatabaseEvent>? _accuracySub;
  final _predictionsController = StreamController<PredictiveModel?>.broadcast();
  final _accuracyController =
      StreamController<PredictiveAccuracy?>.broadcast();
  PredictiveModel? _lastPredictions;
  PredictiveAccuracy? _lastAccuracy;

  Stream<MorningBriefing?> briefingStream({String? factory}) {
    final key = (factory == null || factory.isEmpty || factory == 'all') ? null : factory;
    _ensureBriefingSubscription(key);
    return _briefingControllers[key]!.stream;
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

  static String _briefingDbPath(String? key) {
    if (key == null) return 'ai_briefing/latest';
    final slug = key.toLowerCase().replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return 'ai_briefing/factory/$slug/latest';
  }

  void _ensureBriefingSubscription(String? key) {
    if (_briefingSubs.containsKey(key)) return;
    final ctrl = StreamController<MorningBriefing?>.broadcast();
    _briefingControllers[key] = ctrl;
    _briefingSubs[key] = _db.ref(_briefingDbPath(key)).onValue.listen((event) {
      final value = event.snapshot.value;
      MorningBriefing? briefing;
      if (value is Map) {
        briefing = MorningBriefing.fromMap(Map<String, dynamic>.from(value));
      }
      _lastBriefings[key] = briefing;
      ctrl.add(briefing);
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
    for (final sub in _briefingSubs.values) {
      sub.cancel();
    }
    for (final ctrl in _briefingControllers.values) {
      ctrl.close();
    }
    _briefingSubs.clear();
    _briefingControllers.clear();
    _lastBriefings.clear();
    _predictionsSub?.cancel();
    _accuracySub?.cancel();
    _predictionsController.close();
    _accuracyController.close();
  }
}

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'predictive_models.dart';
import 'predictive_scope.dart';

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
        averageAccuracy: (m['averageAccuracy'] as num?)?.toDouble() ?? 0.0,
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
  final Map<String?, StreamController<MorningBriefing?>> _briefingControllers =
      {};
  final Map<String?, MorningBriefing?> _lastBriefings = {};
  final Map<String?, StreamSubscription<DatabaseEvent>> _predictionsSubs = {};
  final Map<String?, StreamController<PredictiveModel?>>
  _predictionsControllers = {};
  final Map<String?, PredictiveModel?> _lastPredictions = {};
  StreamSubscription<DatabaseEvent>? _accuracySub;
  final _accuracyController = StreamController<PredictiveAccuracy?>.broadcast();
  PredictiveAccuracy? _lastAccuracy;

  Stream<MorningBriefing?> briefingStream({String? factory}) {
    final key = predictiveFactorySlug(factory);
    _ensureBriefingSubscription(key);
    return (() async* {
      if (_lastBriefings.containsKey(key)) {
        yield _lastBriefings[key];
      }
      yield* _briefingControllers[key]!.stream;
    })();
  }

  Stream<PredictiveModel?> predictionsStream({String? factory}) {
    final key = predictiveFactorySlug(factory);
    _ensurePredictionsSubscription(key);
    return (() async* {
      if (_lastPredictions.containsKey(key)) {
        yield _lastPredictions[key];
      }
      yield* _predictionsControllers[key]!.stream;
    })();
  }

  Stream<PredictiveAccuracy?> accuracyStream() {
    _ensureAccuracySubscription();
    return (() async* {
      if (_lastAccuracy != null) {
        yield _lastAccuracy;
      }
      yield* _accuracyController.stream;
    })();
  }

  PredictiveAccuracy? get lastAccuracy => _lastAccuracy;

  static String _briefingDbPath(String? key) => predictiveBriefingPath(key);

  static String _predictionDbPath(String? key) =>
      predictivePredictionsPath(key);

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

  void _ensurePredictionsSubscription(String? key) {
    if (_predictionsSubs.containsKey(key)) return;
    final ctrl = StreamController<PredictiveModel?>.broadcast();
    _predictionsControllers[key] = ctrl;
    _predictionsSubs[key] = _db.ref(_predictionDbPath(key)).onValue.listen((
      event,
    ) {
      final value = event.snapshot.value;
      PredictiveModel? predictions;
      if (value is Map) {
        predictions = PredictiveModel.fromMap(Map<String, dynamic>.from(value));
      }
      _lastPredictions[key] = predictions;
      ctrl.add(predictions);
    });
  }

  void _ensureAccuracySubscription() {
    _accuracySub ??= _db
        .ref('ai_predictions/performance/latest')
        .onValue
        .listen((event) {
          final value = event.snapshot.value;
          if (value is Map) {
            _lastAccuracy = PredictiveAccuracy.fromMap(
              Map<String, dynamic>.from(value),
            );
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
    for (final sub in _predictionsSubs.values) {
      sub.cancel();
    }
    for (final ctrl in _predictionsControllers.values) {
      ctrl.close();
    }
    _predictionsSubs.clear();
    _predictionsControllers.clear();
    _lastPredictions.clear();
    _accuracySub?.cancel();
    _accuracyController.close();
  }
}

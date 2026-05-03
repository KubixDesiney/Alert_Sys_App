import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'predictive_models.dart';

class PredictiveIntelStreamService {
  PredictiveIntelStreamService._({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  static final PredictiveIntelStreamService instance =
      PredictiveIntelStreamService._();

  final FirebaseDatabase _db;
  StreamSubscription<DatabaseEvent>? _briefingSub;
  StreamSubscription<DatabaseEvent>? _predictionsSub;
  final _briefingController = StreamController<MorningBriefing?>.broadcast();
  final _predictionsController = StreamController<PredictiveModel?>.broadcast();
  MorningBriefing? _lastBriefing;
  PredictiveModel? _lastPredictions;

  Stream<MorningBriefing?> briefingStream() {
    _ensureBriefingSubscription();
    return _briefingController.stream;
  }

  Stream<PredictiveModel?> predictionsStream() {
    _ensurePredictionsSubscription();
    return _predictionsController.stream;
  }

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

  void dispose() {
    _briefingSub?.cancel();
    _predictionsSub?.cancel();
    _briefingController.close();
    _predictionsController.close();
  }
}

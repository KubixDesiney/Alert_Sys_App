import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import 'predictive_models.dart';

class PredictiveRepository {
  PredictiveRepository({FirebaseDatabase? database, http.Client? client})
      : _db = database ?? FirebaseDatabase.instance,
        _client = client ?? http.Client();

  final FirebaseDatabase _db;
  final http.Client _client;

  static const String workerBase =
      'https://alert-notifier.aziz-nagati01.workers.dev';
  static const Duration requestTimeout = Duration(seconds: 8);
  static const Duration cacheTtl = Duration(minutes: 5);

  MorningBriefing? _briefingCache;
  DateTime? _briefingCachedAt;
  PredictiveModel? _predictionsCache;
  DateTime? _predictionsCachedAt;
  AssigneeSuggestion? _suggestionCache;
  DateTime? _suggestionCachedAt;

  Stream<MorningBriefing?> briefingStream() {
    return _db.ref('ai_briefing/latest').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return MorningBriefing.fromMap(Map<String, dynamic>.from(value));
    });
  }

  Stream<PredictiveModel?> predictionsStream() {
    return _db.ref('ai_predictions/latest').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return PredictiveModel.fromMap(Map<String, dynamic>.from(value));
    });
  }

  Future<MorningBriefing?> getBriefing({bool force = false}) async {
    if (!force && _isFresh(_briefingCachedAt)) return _briefingCache;
    final result =
        await _fetchJson('$workerBase/briefing${force ? '?force=1' : ''}');
    if (result is Map) {
      final briefing =
          MorningBriefing.fromMap(Map<String, dynamic>.from(result));
      _briefingCache = briefing;
      _briefingCachedAt = DateTime.now();
      return briefing;
    }
    return _briefingCache;
  }

  Future<PredictiveModel?> getPredictions({bool force = false}) async {
    if (!force && _isFresh(_predictionsCachedAt)) return _predictionsCache;
    final result = await _fetchJson('$workerBase/predict');
    if (result is Map) {
      final model = PredictiveModel.fromMap(Map<String, dynamic>.from(result));
      _predictionsCache = model;
      _predictionsCachedAt = DateTime.now();
      return model;
    }
    return _predictionsCache;
  }

  Future<AssigneeSuggestion?> suggestAssignee(String alertId) async {
    if (_suggestionCache != null &&
        _suggestionCachedAt != null &&
        DateTime.now().difference(_suggestionCachedAt!) < cacheTtl &&
        _suggestionCache!.alertId == alertId) {
      return _suggestionCache;
    }

    final result =
        await _fetchJson('$workerBase/suggest-assignee?alertId=$alertId');
    if (result is Map) {
      final suggestion =
          AssigneeSuggestion.fromMap(Map<String, dynamic>.from(result));
      _suggestionCache = suggestion;
      _suggestionCachedAt = DateTime.now();
      return suggestion;
    }
    return null;
  }

  Future<Object?> _fetchJson(String url) async {
    try {
      final response =
          await _client.get(Uri.parse(url)).timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  bool _isFresh(DateTime? cachedAt) {
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < cacheTtl;
  }
}

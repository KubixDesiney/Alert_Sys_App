import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../models/alert_model.dart';
import '../alert_type_registry.dart';
import '../predictive_models.dart';
import 'alert_record_parser.dart';
import 'forecast_engine.dart';
import 'forecast_learning_service.dart';
import 'forecast_model_store.dart';
import 'forecast_types.dart';

/// Feeds the Production Manager overview with on-device gradient-boosting
/// forecasts.
///
/// Streams the SuperAdmin-deployed ensemble from `ai_forecast/model`, re-runs
/// inference over the dashboard's alert stream (throttled), keeps the shared
/// `ai_predictions/forecast` snapshot fresh, and adapts the per-machine
/// output into the [PredictiveModel] shape that the Predictive Failure Alerts
/// card and the Predictive Risk heatmap already render — so once a model is
/// deployed, those two cards switch from the statistical edge model to real
/// machine-learning forecasts.
///
/// It also drives the continuous-learning loop: graded forecast outcomes and
/// periodic adaptation boosting both piggyback on the dashboards that are
/// already holding the model and the live alert stream.
class ForecastOverviewEngine extends ChangeNotifier {
  ForecastOverviewEngine({ForecastModelStore? store})
      : _store = store ?? ForecastModelStore(),
        _learner = ForecastContinuousLearner(store: store) {
    _modelSub = _store.modelStream().listen((m) {
      _model = m;
      _recompute(force: true);
    }, onError: (_) {});
  }

  final ForecastModelStore _store;
  final ForecastContinuousLearner _learner;
  StreamSubscription<TrainedForecastModel?>? _modelSub;

  TrainedForecastModel? _model;
  List<AlertRecord> _records = const [];
  List<MachineForecast> _forecasts = const [];
  DateTime? _computedAt;
  String _lastAlertSignature = '';
  bool _publishedRecently = false;

  // Overlay memo — rebuilding the adapter output on every widget build would
  // re-scan the alert history for nothing.
  String? _overlayKey;
  PredictiveModel? _overlayValue;

  TrainedForecastModel? get model => _model;
  List<MachineForecast> get forecasts => _forecasts;
  DateTime? get computedAt => _computedAt;

  /// True when a model is deployed but its learned type set no longer matches
  /// the live [AlertTypeRegistry] (a type was added/removed/reordered since
  /// training). The forecaster then cleanly falls back to the statistical model
  /// until a retrain, rather than mis-indexing the feature vector.
  bool get modelStale {
    final m = _model;
    return m != null && _isStale(m);
  }

  static bool _isStale(TrainedForecastModel m) =>
      !listEquals(m.types, AlertTypeRegistry.instance.codes);

  /// Push the dashboard's current alert stream in; inference re-runs at most
  /// once per 15s unless the deployed model itself changed.
  void updateAlerts(List<AlertModel> alerts) {
    // Cheap change signature: count plus newest timestamp, so a same-length
    // stream update (one resolved + one created) still retriggers inference.
    DateTime? newest;
    for (final a in alerts) {
      if (newest == null || a.timestamp.isAfter(newest)) newest = a.timestamp;
    }
    final signature = '${alerts.length}|${newest?.millisecondsSinceEpoch ?? 0}';
    if (signature == _lastAlertSignature && _model != null) return;
    _records = [
      for (final a in alerts)
        AlertRecord(
          timestamp: a.timestamp,
          // Live alerts must speak the same canonical type vocabulary the
          // model was trained on, or per-type features silently zero out.
          // Normalize through the tenant registry's synonyms.
          type: AlertRecordParser.normalizeType(a.type,
              types: AlertTypeRegistry.instance.types),
          usine: a.usine,
          convoyeur: a.convoyeur,
          poste: a.poste,
          isCritical: a.isCritical,
        ),
    ];
    _lastAlertSignature = signature;
    _recompute();
  }

  void _recompute({bool force = false}) {
    final model = _model;
    // No usable model, or a stale one whose type set drifted from the live
    // registry: clear forecasts so the cards fall back to the statistical model.
    if (model == null || _isStale(model)) {
      if (_forecasts.isNotEmpty || force) {
        _forecasts = const [];
        _invalidateOverlay();
        notifyListeners();
      }
      return;
    }
    if (!force &&
        _computedAt != null &&
        DateTime.now().difference(_computedAt!) <
            const Duration(seconds: 15)) {
      return;
    }
    if (_records.isEmpty) return;
    _forecasts = ForecastEngine.computeForecasts(model, _records);
    _computedAt = DateTime.now();
    _invalidateOverlay();
    notifyListeners();
    _maybePublish(_forecasts);
    // Self-evaluation + adaptation ride along, self-throttled and silent.
    unawaited(_learner.maybeRun(
      deployed: model,
      forecasts: _forecasts,
      records: _records,
    ));
  }

  void _invalidateOverlay() {
    _overlayKey = null;
    _overlayValue = null;
  }

  /// Keeps `ai_predictions/forecast` fresh for the rest of the platform
  /// without letting every open dashboard spam writes.
  Future<void> _maybePublish(List<MachineForecast> forecasts) async {
    if (_publishedRecently || forecasts.isEmpty) return;
    _publishedRecently = true;
    Timer(const Duration(minutes: 10), () => _publishedRecently = false);
    try {
      final snap = await FirebaseDatabase.instance
          .ref('ai_predictions/forecast/generatedAt')
          .get();
      final last = DateTime.tryParse((snap.value ?? '').toString());
      if (last != null &&
          DateTime.now().toUtc().difference(last.toUtc()) <
              const Duration(minutes: 10)) {
        return;
      }
      await ForecastEngine.publishSnapshot(forecasts);
    } catch (_) {
      // Display stays local-only when the write is not permitted.
    }
  }

  /// Forecast-backed [PredictiveModel] for the selected factory scope, or
  /// null when no model is deployed / no machine in scope has a forecast —
  /// in which case the caller keeps the statistical model.
  PredictiveModel? overlayFor(
      String selectedUsine, PredictiveModel? statistical) {
    if (_model == null || _forecasts.isEmpty) return null;
    final key = '${_computedAt?.millisecondsSinceEpoch}'
        '|$selectedUsine'
        '|${statistical?.generatedAt?.millisecondsSinceEpoch}';
    if (key == _overlayKey) return _overlayValue;

    final scope = selectedUsine.trim().toLowerCase();
    final scopedForecasts = scope == 'all'
        ? _forecasts
        : _forecasts
            .where((f) => f.usine.trim().toLowerCase() == scope)
            .toList();
    final scopedRecords = scope == 'all'
        ? _records
        : _records
            .where((r) => r.usine.trim().toLowerCase() == scope)
            .toList();

    PredictiveModel? overlay;
    if (scopedForecasts.isNotEmpty) {
      // Even when no machine crosses the failure floor the risk curves are
      // still the model's real day-level probabilities — keep the overlay so
      // the PM always sees live AI output instead of a "not enough data"
      // fallback.
      overlay = buildPredictiveModel(
        forecasts: scopedForecasts,
        records: scopedRecords,
        statistical: statistical,
        generatedAt: _computedAt,
      );
    }
    _overlayKey = key;
    _overlayValue = overlay;
    return overlay;
  }

  @override
  void dispose() {
    _modelSub?.cancel();
    super.dispose();
  }

  // ── Adapter: MachineForecast → PredictiveModel ───────────────────────────

  /// Minimum per-type probability for a machine to surface as a predicted
  /// failure entry.
  static const double kFailureFloor = 0.2;

  /// Relaxed floor used when no machine crosses [kFailureFloor]: the plant is
  /// calm, but the PM still sees the highest-ranked (low) risks instead of an
  /// empty "not enough data" card.
  static const double kQuietFloor = 0.01;

  /// Converts per-machine next-24h probabilities into the [PredictiveModel]
  /// consumed by the overview cards.
  ///
  /// Failure entries: one per (machine, type) above [kFailureFloor], enriched
  /// with history facts (past/critical counts, last occurrence) from the
  /// alert records. Risk curves: the per-type plant-wide day probability
  /// (1 - Π(1 - p_machine)) decomposed over twelve 2h buckets along the
  /// historical hour-of-day shape, so 1 - Π(1 - bucket) reproduces the
  /// model's day-level probability exactly.
  @visibleForTesting
  static PredictiveModel buildPredictiveModel({
    required List<MachineForecast> forecasts,
    required List<AlertRecord> records,
    PredictiveModel? statistical,
    DateTime? generatedAt,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();

    // Index machine history once.
    final byMachine = <String, List<AlertRecord>>{};
    for (final r in records) {
      byMachine.putIfAbsent(r.machineKey, () => []).add(r);
    }

    // ── Predicted failures ──
    // First pass keeps entries above the floor; when the whole plant is calm
    // (nothing crosses it) we still surface the top-ranked machines so the
    // dashboard shows live forecasts instead of an empty state.
    var floor = kFailureFloor;
    final anyAboveFloor = forecasts.any((f) =>
        f.typeProbabilities.values.any((p) => p >= kFailureFloor));
    if (!anyAboveFloor) floor = kQuietFloor;

    final failures = <PredictedFailure>[];
    for (final f in forecasts) {
      final history =
          byMachine['${f.usine}|${f.convoyeur}|${f.poste}'] ?? const [];
      f.typeProbabilities.forEach((type, p) {
        if (p < floor) return;
        var past = 0;
        var critical = 0;
        DateTime? lastTs;
        DateTime? lastAny;
        for (final r in history) {
          if (lastAny == null || r.timestamp.isAfter(lastAny)) {
            lastAny = r.timestamp;
          }
          if (r.type != type) continue;
          past++;
          if (r.isCritical) critical++;
          if (lastTs == null || r.timestamp.isAfter(lastTs)) {
            lastTs = r.timestamp;
          }
        }
        failures.add(PredictedFailure(
          factoryId: '',
          usine: f.usine,
          convoyeur: f.convoyeur,
          poste: f.poste,
          type: type,
          confidence: (p * 100).round().clamp(0, 99),
          pastCount: past,
          criticalCount: critical,
          lastTs: lastTs ?? lastAny,
          // Higher probability ⇒ sooner inside the 24h horizon.
          etaHours: ((1 - p) * 24).clamp(0.5, 24.0).toDouble(),
        ));
      });
    }
    failures.sort((a, b) => b.confidence.compareTo(a.confidence));
    final topFailures = failures.take(10).toList();

    // ── Risk curves per type ──
    // Types come from the forecasts themselves (the deployed model's set), so
    // the curves adapt to a tenant's configured type list.
    final curveTypes = forecasts.isEmpty
        ? const <String>[]
        : forecasts.first.typeProbabilities.keys.toList();
    final curves = <String, RiskCurve>{};
    for (final type in curveTypes) {
      // Plant-wide probability that at least one machine alerts with this
      // type in the next 24h.
      var noAlert = 1.0;
      for (final f in forecasts) {
        noAlert *= 1.0 - (f.typeProbabilities[type] ?? 0).clamp(0.0, 1.0);
      }
      final dayProb = (1.0 - noAlert).clamp(0.0, 0.99);

      final weights = _bucketWeights(
        statistical?.curves[type],
        records.where((r) => r.type == type),
        clock,
      );

      final buckets = <RiskBucket>[];
      var peakIdx = 0;
      var probSum = 0.0;
      for (var i = 0; i < 12; i++) {
        // Exact decomposition: 1 - Π(1 - b_i) == dayProb.
        final b = 1.0 - math.pow(1.0 - dayProb, weights[i]).toDouble();
        final startHour = (clock.hour + i * 2) % 24;
        buckets.add(RiskBucket(
          offsetHours: i * 2,
          startHour: startHour,
          endHour: (startHour + 2) % 24,
          probability: b,
          expected: dayProb * weights[i],
        ));
        probSum += b;
        if (b > buckets[peakIdx].probability) peakIdx = i;
      }

      curves[type] = RiskCurve(
        buckets: buckets,
        total24h: dayProb,
        hourlyRate: dayProb / 24,
        peakHour: buckets[peakIdx].startHour,
        peakProbability: buckets[peakIdx].probability,
        avgProbability: probSum / 12,
        sampleSize: forecasts.length,
      );
    }

    return PredictiveModel(
      curves: curves,
      predictions: topFailures,
      factoryRisk: statistical?.factoryRisk ?? const [],
      generatedAt: generatedAt ?? clock,
    );
  }

  /// Normalized intra-day shape (12 weights summing to 1) used to spread the
  /// model's day-level probability over 2h buckets. Prefers the statistical
  /// model's curve shape, falls back to the historical hour-of-day histogram,
  /// then uniform.
  static List<double> _bucketWeights(
    RiskCurve? statCurve,
    Iterable<AlertRecord> typeHistory,
    DateTime now,
  ) {
    var raw = List<double>.filled(12, 0);
    if (statCurve != null && statCurve.buckets.length == 12) {
      for (var i = 0; i < 12; i++) {
        raw[i] = math.max(0, statCurve.buckets[i].probability);
      }
    }
    if (raw.fold<double>(0, (a, b) => a + b) <= 0) {
      // Hour-of-day histogram mapped onto now-relative buckets.
      final byHour = List<int>.filled(24, 0);
      for (final r in typeHistory) {
        byHour[r.timestamp.toLocal().hour]++;
      }
      raw = List<double>.generate(12, (i) {
        final h0 = (now.hour + i * 2) % 24;
        return (byHour[h0] + byHour[(h0 + 1) % 24]).toDouble();
      });
    }
    final sum = raw.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return List<double>.filled(12, 1 / 12);
    return [for (final w in raw) w / sum];
  }
}

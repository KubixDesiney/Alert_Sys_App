import 'dart:math' as math;

import '../app_logger.dart';
import 'forecast_feature_engineer.dart';
import 'forecast_model_store.dart';
import 'forecast_trainer.dart';
import 'forecast_types.dart';

/// The continuous-learning loop behind the deployed forecaster.
///
/// Two responsibilities, both driven opportunistically from open dashboards
/// (no server component needed):
///
/// 1. **Self-evaluation** — every day the engine snapshots what the model
///    predicted for tomorrow; once that day has elapsed, the snapshot is
///    graded against the alerts that actually happened (hit/miss + Brier
///    score) and folded into a rolling accuracy ledger every console can see.
/// 2. **Adaptation** — at most once per ~day (cross-dashboard lock), a small
///    number of extra trees are boosted onto the deployed ensemble using the
///    most recent production alerts, so the model keeps tracking the plant's
///    current regime between full retrainings.
class ForecastContinuousLearner {
  ForecastContinuousLearner({
    ForecastModelStore? store,
    String? sessionId,
  })  : _store = store ?? ForecastModelStore(),
        _sessionId = sessionId ??
            'cl-${DateTime.now().microsecondsSinceEpoch}-'
                '${math.Random().nextInt(0x7fffffff)}';

  static const AppLogger _log = AppLogger();

  /// Probability threshold above which a forecast counts as "called".
  static const double kCallThreshold = 0.5;

  /// Machines persisted per pending-outcome snapshot (bounds blob size).
  static const int kMaxSnapshotMachines = 80;

  /// Minimum gap between two adaptations of the deployed model.
  static const Duration kAdaptationInterval = Duration(hours: 20);

  /// Adaptation stops appending once this many extra rounds accumulated;
  /// a full retrain in the console resets the budget.
  static const int kMaxAdaptedRounds = 60;

  /// Trees boosted per adaptation pass (per type).
  static const int kAdaptationRounds = 6;

  /// Days of recent history the adaptation pass learns from.
  static const int kAdaptationWindowDays = 120;

  final ForecastModelStore _store;
  final String _sessionId;

  DateTime _lastCycleAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _running = false;

  /// Runs one continuous-learning cycle (grade + snapshot + maybe adapt).
  /// Cheap to call often — it self-throttles to once per 30 minutes.
  Future<void> maybeRun({
    required TrainedForecastModel deployed,
    required List<MachineForecast> forecasts,
    required List<AlertRecord> records,
    DateTime? now,
  }) async {
    final clock = (now ?? DateTime.now()).toUtc();
    if (_running ||
        clock.difference(_lastCycleAt) < const Duration(minutes: 30)) {
      return;
    }
    _running = true;
    _lastCycleAt = clock;
    try {
      await _gradeElapsedOutcomes(deployed, records, clock);
      await _snapshotTomorrow(deployed, forecasts, clock);
      await _maybeAdapt(deployed, records, clock);
    } catch (e) {
      _log.warning('Forecast continuous-learning cycle failed: $e');
    } finally {
      _running = false;
    }
  }

  // ── 1. Grade elapsed forecasts against reality ───────────────────────────

  Future<void> _gradeElapsedOutcomes(TrainedForecastModel deployed,
      List<AlertRecord> records, DateTime now) async {
    final pending = await _store.loadPendingOutcomes();
    if (pending == null || pending.isEmpty) return;
    final todayKey = ForecastModelStore.dayKey(now);

    // Index reality once: machineKey~type occurrences per day key.
    final occurred = <String, Set<String>>{};
    for (final r in records) {
      final key = ForecastModelStore.dayKey(r.timestamp);
      occurred
          .putIfAbsent(key, () => <String>{})
          .add('${r.machineKey.replaceAll('|', '~')}~${r.type}');
    }

    for (final entry in pending.entries) {
      final dateKey = entry.key;
      // Only grade days that have fully elapsed.
      if (dateKey.compareTo(todayKey) >= 0) continue;
      final snapshot = entry.value;
      if (snapshot is! Map) {
        await _store.removePendingOutcome(dateKey);
        continue;
      }
      final machines = snapshot['machines'];
      if (machines is! Map) {
        await _store.removePendingOutcome(dateKey);
        continue;
      }

      var pairs = 0;
      var brierSum = 0.0;
      var tp = 0, fp = 0, fn = 0;
      final dayReality = occurred[dateKey] ?? const <String>{};
      final thresholds = deployed.model.thresholds;
      final types = deployed.model.types;
      machines.forEach((machineKey, probs) {
        if (probs is! Map) return;
        for (var ti = 0; ti < types.length; ti++) {
          final type = types[ti];
          final p = (probs[type] as num?)?.toDouble();
          if (p == null) continue;
          final happened = dayReality.contains('$machineKey~$type');
          pairs++;
          final actual = happened ? 1.0 : 0.0;
          brierSum += (p - actual) * (p - actual);
          final threshold =
              ti < thresholds.length ? thresholds[ti] : kCallThreshold;
          final called = p >= threshold;
          if (called && happened) tp++;
          if (called && !happened) fp++;
          if (!called && happened) fn++;
        }
      });

      if (pairs > 0) {
        await _store.recordGradedDay(
          dateKey: dateKey,
          pairs: pairs,
          brierSum: brierSum,
          tp: tp,
          fp: fp,
          fn: fn,
        );
        _log.info(
            'Forecast outcomes graded for $dateKey: $pairs pairs, $tp hits.');
      }
      await _store.removePendingOutcome(dateKey);
    }
  }

  // ── 2. Snapshot what the model predicts for tomorrow ─────────────────────

  Future<void> _snapshotTomorrow(
    TrainedForecastModel deployed,
    List<MachineForecast> forecasts,
    DateTime now,
  ) async {
    if (forecasts.isEmpty) return;
    final tomorrow = DateTime.utc(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final key = ForecastModelStore.dayKey(tomorrow);
    final pending = await _store.loadPendingOutcomes();
    if (pending != null && pending.containsKey(key)) return; // first write wins

    final top = forecasts.take(kMaxSnapshotMachines);
    await _store.savePendingOutcome(
      targetDay: tomorrow,
      modelVersion: deployed.version,
      machineProbabilities: {
        for (final f in top) f.machineKey: f.typeProbabilities,
      },
    );
  }

  // ── 3. Boost adaptation trees on recent production data ─────────────────

  Future<void> _maybeAdapt(
    TrainedForecastModel deployed,
    List<AlertRecord> records,
    DateTime now,
  ) async {
    // The SuperAdmin can pause adaptation from the AI Agents console without
    // undeploying the model.
    if (!await _store.predictiveAgentFlag('adaptationEnabled')) return;
    final lastAdapted = deployed.lastAdaptedAt ?? deployed.trainedAt;
    if (lastAdapted != null &&
        now.difference(lastAdapted.toUtc()) < kAdaptationInterval) {
      return;
    }
    if (deployed.model.adaptedRounds >= kMaxAdaptedRounds) return;

    final cutoff = now.subtract(const Duration(days: kAdaptationWindowDays));
    final recent =
        records.where((r) => r.timestamp.toUtc().isAfter(cutoff)).toList();
    final samples = ForecastFeatureEngineer.buildSamples(
        ForecastFeatureEngineer.buildDailyRows(recent));
    if (samples.length < 60) return;

    if (!await _store.tryClaimAdaptationLock(_sessionId)) return;
    try {
      // Re-read after winning the lock: another dashboard may have adapted
      // between our stream snapshot and now.
      final fresh = await _store.loadModel();
      if (fresh == null) return;
      final freshLast = fresh.lastAdaptedAt ?? fresh.trainedAt;
      if (freshLast != null &&
          now.difference(freshLast.toUtc()) < kAdaptationInterval) {
        return;
      }
      if (fresh.model.adaptedRounds >= kMaxAdaptedRounds) return;

      final adapted = await ForecastTrainer.adapt(
        model: fresh.model,
        samples: samples,
        rounds: kAdaptationRounds,
        seed: now.millisecondsSinceEpoch & 0x7fffffff,
      );
      if (adapted == null) return;
      await _store.saveAdaptedModel(
        model: adapted,
        previousVersion: fresh.version,
      );
      _log.info(
          'Forecast model adapted: +$kAdaptationRounds rounds on '
          '${samples.length} recent samples (v${fresh.version + 1}).');
    } finally {
      await _store.releaseAdaptationLock(_sessionId);
    }
  }
}

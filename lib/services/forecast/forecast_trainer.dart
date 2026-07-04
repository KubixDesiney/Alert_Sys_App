import 'dart:math' as math;
import 'dart:typed_data';

import 'gradient_boost.dart';
import 'forecast_types.dart';

/// Result of a finished (or stopped) training run.
class ForecastTrainingResult {
  /// Best-round model (early-stopping snapshot).
  final GradientBoostModel model;
  final List<RoundStat> rounds;
  final bool isLearning;
  final double bestValLoss;
  final double bestValAccuracy;
  final int sampleCount;

  const ForecastTrainingResult({
    required this.model,
    required this.rounds,
    required this.isLearning,
    required this.bestValLoss,
    required this.bestValAccuracy,
    required this.sampleCount,
  });
}

/// Orchestrates genuine gradient-boosting training over engineered samples.
///
/// Runs cooperatively on the calling isolate (works on web too): the boosting
/// loop yields to the event loop regularly so the UI stays at 60fps while the
/// trees grow. Emits a [ForecastTrainingUpdate] after every round with real
/// loss-curve data, starting from a round-0 baseline (prior log-odds only) so
/// the curves show exactly how much the trees improve on doing nothing.
class ForecastTrainer {
  bool _cancelRequested = false;

  /// Live references to the in-flight ensemble, refreshed after every round
  /// so the training controller can checkpoint a resumable snapshot mid-run.
  GradientBoostModel? liveModel;
  int liveBestRound = 0;

  void cancel() => _cancelRequested = true;

  /// Populated when the stream finishes.
  ForecastTrainingResult? result;

  /// Starts (or resumes) a training run.
  ///
  /// When [resumeModel] is provided together with [startRound] and
  /// [resumeStats], the run continues from a checkpoint: the dataset is
  /// re-split deterministically (same [ForecastTrainingConfig.seed]), the
  /// trees grown so far are restored, and boosting picks up where it left
  /// off.
  Stream<ForecastTrainingUpdate> train({
    required List<FeatureSample> samples,
    required ForecastTrainingConfig config,
    List<String> types = kForecastAlertTypes,
    GradientBoostModel? resumeModel,
    int startRound = 1,
    List<RoundStat> resumeStats = const [],
  }) async* {
    _cancelRequested = false;
    result = null;
    if (samples.length < 30) {
      yield ForecastTrainingUpdate(
        phase: ForecastTrainingPhase.failed,
        progress: 0,
        rounds: const [],
        message: 'Not enough training samples (${samples.length}). Upload '
            'more history — each machine contributes one sample per day '
            'after its first week.',
        isLearning: false,
      );
      return;
    }

    yield const ForecastTrainingUpdate(
      phase: ForecastTrainingPhase.preparing,
      progress: 0,
      rounds: [],
      message: 'Shuffling dataset and splitting train/validation…',
      isLearning: false,
    );
    // Let the spinner paint before matrix building starts.
    await Future<void>.delayed(Duration.zero);

    final rng = math.Random(config.seed);
    final shuffled = List<FeatureSample>.of(samples)..shuffle(rng);
    final valCount = math.max(8, (shuffled.length * config.valSplit).round());
    final valSet =
        shuffled.sublist(0, math.min(valCount, shuffled.length ~/ 2));
    final trainSet = shuffled.sublist(valSet.length);

    final booster = GbdtBooster(
      trainX: [for (final s in trainSet) s.features],
      trainY: [for (final s in trainSet) s.target],
      valX: [for (final s in valSet) s.features],
      valY: [for (final s in valSet) s.target],
      config: config,
      resume: resumeModel,
      types: types,
    );

    final stats = List<RoundStat>.of(resumeStats);
    if (stats.isEmpty) {
      // Round-0 baseline: prior log-odds only (or the resumed trees' state).
      final trainEval = booster.evalTrain();
      final valEval = booster.evalVal();
      final tunedThresholds0 = booster.bestValThresholds();
      stats.add(RoundStat(
        round: math.max(0, startRound - 1),
        trainLoss: trainEval.loss,
        valLoss: valEval.loss,
        valAccuracy: valEval.accuracy,
        valF1: booster.evalVal(thresholds: tunedThresholds0).f1,
      ));
    }

    var bestValLoss = double.infinity;
    var bestValAccuracy = 0.0;
    var bestRound = stats.first.round;
    for (final s in stats) {
      if (s.valLoss < bestValLoss) {
        bestValLoss = s.valLoss;
        bestValAccuracy = s.valAccuracy;
        bestRound = s.round;
      }
    }
    var badRounds = stats.isEmpty ? 0 : stats.last.round - bestRound;
    final firstValLoss = stats.first.valLoss;
    liveModel = booster.model;
    liveBestRound = bestRound;

    final yieldClock = Stopwatch()..start();
    final firstRound = math.max(1, startRound);
    for (var round = firstRound; round <= config.rounds; round++) {
      if (_cancelRequested) break;

      final rows = booster.sampleRows();
      for (var t = 0; t < types.length; t++) {
        booster.boostType(t, rows);
        // Yield to the event loop after ~10ms of compute so UI animation
        // stays smooth without paying an event-loop round trip per tree.
        if (yieldClock.elapsedMilliseconds >= 10) {
          await Future<void>.delayed(Duration.zero);
          yieldClock.reset();
        }
        if (_cancelRequested) break;
      }
      if (_cancelRequested) break;

      final trainEval = booster.evalTrain();
      final valEval = booster.evalVal();
      final tunedThresholds = booster.bestValThresholds();
      stats.add(RoundStat(
        round: round,
        trainLoss: trainEval.loss,
        valLoss: valEval.loss,
        valAccuracy: valEval.accuracy,
        valF1: booster.evalVal(thresholds: tunedThresholds).f1,
      ));

      if (valEval.loss < bestValLoss - 1e-5) {
        bestValLoss = valEval.loss;
        bestValAccuracy = valEval.accuracy;
        bestRound = round;
        badRounds = 0;
      } else {
        badRounds++;
      }
      liveModel = booster.model;
      liveBestRound = bestRound;

      final learning = isLearningFromStats(stats);
      yield ForecastTrainingUpdate(
        phase: ForecastTrainingPhase.training,
        progress: round / config.rounds,
        rounds: List.unmodifiable(stats),
        message:
            'Round $round/${config.rounds} — train ${trainEval.loss.toStringAsFixed(4)}'
            ' · val ${valEval.loss.toStringAsFixed(4)}'
            ' · acc ${(valEval.accuracy * 100).toStringAsFixed(1)}%',
        isLearning: learning,
      );

      if (badRounds >= config.patience) {
        yield ForecastTrainingUpdate(
          phase: ForecastTrainingPhase.training,
          progress: round / config.rounds,
          rounds: List.unmodifiable(stats),
          message:
              'Early stop: validation loss plateaued for ${config.patience} '
              'rounds. Keeping the best ensemble '
              '(round $bestRound, val ${bestValLoss.toStringAsFixed(4)}).',
          isLearning: learning,
        );
        break;
      }
    }

    final learning = isLearningFromStats(stats);
    final finalModel = booster.model.truncated(bestRound);
    finalModel.thresholds = booster.bestValThresholds();
    result = ForecastTrainingResult(
      model: finalModel,
      rounds: stats,
      isLearning: learning,
      bestValLoss: bestValLoss.isFinite ? bestValLoss : 0,
      bestValAccuracy: bestValAccuracy,
      sampleCount: samples.length,
    );

    yield ForecastTrainingUpdate(
      phase: _cancelRequested
          ? ForecastTrainingPhase.stopped
          : ForecastTrainingPhase.done,
      progress: 1,
      rounds: List.unmodifiable(stats),
      message: _cancelRequested
          ? 'Training stopped — the best ensemble so far was kept.'
          : learning
              ? 'Training complete. The model is learning: validation loss '
                  'dropped from ${firstValLoss.toStringAsFixed(4)} to '
                  '${bestValLoss.toStringAsFixed(4)}.'
              : 'Training finished but the validation loss barely moved below '
                  'the baseline. Upload more (or more varied) history and '
                  'retrain.',
      isLearning: learning,
    );
  }

  /// Learning verdict: the model counts as "learning" once validation loss
  /// dropped at least 3% below its round-0 baseline with 3+ boosting rounds
  /// observed.
  static bool isLearningFromStats(List<RoundStat> stats) {
    if (stats.length < 3) return false;
    final first = stats.first.valLoss;
    if (first <= 0) return false;
    final best = stats.map((e) => e.valLoss).reduce(math.min);
    return best <= first * 0.97;
  }

  /// Explains a NOT-LEARNING verdict in operator terms: what the data and the
  /// loss trajectory show, and what to change. Returns an ordered list of
  /// human-readable reasons (most fundamental first).
  static List<String> diagnose({
    required List<FeatureSample> samples,
    required List<RoundStat> rounds,
    required ForecastTrainingConfig config,
    List<String> types = kForecastAlertTypes,
    DatasetSummary? summary,
    bool cancelled = false,
  }) {
    final reasons = <String>[];

    if (cancelled) {
      reasons.add(
          'The run was stopped before completion — the learning verdict only '
          'reflects a finished run.');
    }

    // ── Dataset volume ──
    if (samples.length < 150) {
      reasons.add(
          'Only ${samples.length} training samples were available. Each '
          'machine contributes one sample per day after its first week — '
          'aim for 300+ samples (several months across machines).');
    }
    if (summary != null) {
      if (summary.daySpan > 0 && summary.daySpan < 45) {
        reasons.add(
            'The history spans only ${summary.daySpan} days. The trees rely '
            'on weekly rhythms and 14-day rollups — upload 2–3+ months of '
            'history so those patterns exist in the data.');
      }
      if (summary.machineCount < 3) {
        reasons.add(
            'Only ${summary.machineCount} machine(s) in the dataset — '
            'cross-machine variety is what gives the model patterns to '
            'generalize from.');
      }
    }

    // ── Label balance ──
    if (samples.isNotEmpty) {
      final typeCount = samples.first.target.length;
      final names = types.length == typeCount ? types : kForecastAlertTypes;
      final pos = List<int>.filled(typeCount, 0);
      for (final s in samples) {
        for (var k = 0; k < typeCount; k++) {
          if (s.target[k] >= 0.5) pos[k]++;
        }
      }
      final rates = [for (final p in pos) p / samples.length];
      final maxRate = rates.reduce(math.max);
      final minRate = rates.reduce(math.min);
      final missing = <String>[
        for (var k = 0; k < typeCount; k++)
          if (pos[k] == 0) (k < names.length ? names[k] : 'type$k'),
      ];
      if (missing.isNotEmpty && missing.length < typeCount) {
        reasons.add(
            'No positive examples at all for: ${missing.join(', ')} — those '
            'outputs cannot be learned from this file.');
      }
      if (maxRate < 0.05) {
        reasons.add(
            'Alert days are very sparse: even the most common type occurs on '
            'under 5% of next-day labels, so predicting "no alert" is almost '
            'always right and the loss has little signal to learn from. '
            'Denser or longer history helps.');
      } else if (minRate > 0.9) {
        reasons.add(
            'Nearly every day carries every alert type — uniform labels have '
            'no contrast for the model to discriminate.');
      }
    }

    // ── Loss trajectory ──
    if (rounds.length < 3) {
      reasons.add(
          'Only ${rounds.length} round(s) completed — too few to establish a '
          'learning trend (the verdict needs at least 3).');
    } else {
      final first = rounds.first.valLoss;
      final best = rounds.map((e) => e.valLoss).reduce(math.min);
      if (first > 0) {
        final improvement = (first - best) / first;
        if (improvement <= 0) {
          reasons.add(
              'Validation loss never dropped below its starting baseline '
              '(${first.toStringAsFixed(4)}). The trees found no day-to-day '
              'pattern to split on — either the history is effectively '
              'random, or the learning rate (try 0.03–0.08) and max depth '
              '(try 3–4) need a smaller setting for this dataset.');
        } else {
          reasons.add(
              'Validation loss improved only '
              '${(improvement * 100).toStringAsFixed(1)}% '
              '(${first.toStringAsFixed(4)} → ${best.toStringAsFixed(4)}); '
              'the verdict needs at least 3%. More (or more varied) history '
              'usually moves this the most.');
        }
      }
      if (!cancelled && rounds.last.round < config.rounds) {
        reasons.add(
            'Early stopping ended the run at round ${rounds.last.round}/'
            '${config.rounds} after ${config.patience} rounds without '
            'validation improvement.');
      }
    }

    if (reasons.isEmpty) {
      reasons.add(
          'No single cause stands out — the loss moved, just not enough. '
          'Retraining with more history, a lower learning rate, or shallower '
          'trees is the usual fix.');
    }
    return reasons;
  }

  /// Continues boosting an already-deployed model on fresh samples — the
  /// continuous-learning path. Yields to the event loop between rounds so a
  /// Production Manager dashboard never stutters while the model adapts.
  /// Returns the adapted model (the input is not mutated), or null when
  /// [samples] are too few to adapt safely.
  static Future<GradientBoostModel?> adapt({
    required GradientBoostModel model,
    required List<FeatureSample> samples,
    required int rounds,
    double learningRate = 0.03,
    int seed = 1,
  }) async {
    if (samples.length < 60 || rounds <= 0) return null;
    final config = ForecastTrainingConfig(
      rounds: rounds,
      learningRate: learningRate,
      maxDepth: 3,
      minSamplesLeaf: math.max(8, samples.length ~/ 50),
      subsample: 0.8,
      colsample: 0.9,
      l2: 2.0, // stiffer regularization: adaptation must not thrash the base
      seed: seed,
    );
    final booster = GbdtBooster(
      trainX: [for (final s in samples) s.features],
      trainY: [for (final s in samples) s.target],
      valX: const <Float64List>[],
      valY: const <Float64List>[],
      config: config,
      resume: model,
      types: model.types,
    );
    for (var r = 0; r < rounds; r++) {
      booster.boostOneRound();
      await Future<void>.delayed(Duration.zero);
    }
    final adapted = booster.model;
    adapted.adaptedRounds = model.adaptedRounds + rounds;
    adapted.baseRounds = model.baseRounds;
    return adapted;
  }
}

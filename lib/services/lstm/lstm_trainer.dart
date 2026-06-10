import 'dart:math' as math;
import 'dart:typed_data';

import 'lstm_feature_engineer.dart';
import 'lstm_network.dart';
import 'lstm_types.dart';

/// Result of a finished (or stopped) training run.
class LstmTrainingResult {
  final LstmNetwork network;
  final FeatureScaler scaler;
  final List<EpochStat> epochs;
  final bool isLearning;
  final double bestValLoss;
  final double bestValAccuracy;
  final int sampleCount;

  const LstmTrainingResult({
    required this.network,
    required this.scaler,
    required this.epochs,
    required this.isLearning,
    required this.bestValLoss,
    required this.bestValAccuracy,
    required this.sampleCount,
  });
}

/// Orchestrates genuine LSTM training over engineered samples.
///
/// Runs cooperatively on the calling isolate (works on web too): the batch
/// loop yields to the event loop regularly so the UI stays at 60fps while
/// the network learns. Emits an [LstmTrainingUpdate] after every epoch with
/// real loss-curve data.
class LstmTrainer {
  bool _cancelRequested = false;

  void cancel() => _cancelRequested = true;

  Stream<LstmTrainingUpdate> train({
    required List<TrainingSample> samples,
    required FeatureScaler scaler,
    required LstmTrainingConfig config,
  }) async* {
    _cancelRequested = false;
    if (samples.length < 20) {
      yield LstmTrainingUpdate(
        phase: LstmTrainingPhase.failed,
        progress: 0,
        epochs: const [],
        message:
            'Not enough sequence windows (${samples.length}). Upload more '
            'history — at least ~${config.seqLen + 20} days per machine.',
        isLearning: false,
      );
      return;
    }

    yield const LstmTrainingUpdate(
      phase: LstmTrainingPhase.preparing,
      progress: 0,
      epochs: [],
      message: 'Shuffling dataset and splitting train/validation…',
      isLearning: false,
    );

    final rng = math.Random(config.seed);
    final shuffled = List<TrainingSample>.of(samples)..shuffle(rng);
    final valCount =
        math.max(8, (shuffled.length * config.valSplit).round());
    final valSet = shuffled.sublist(0, math.min(valCount, shuffled.length ~/ 2));
    final trainSet = shuffled.sublist(valSet.length);

    // Positive-class weights from the *training* split only.
    final posWeights = Float64List(kLstmAlertTypes.length);
    for (var k = 0; k < kLstmAlertTypes.length; k++) {
      var pos = 0;
      for (final s in trainSet) {
        if (s.target[k] >= 0.5) pos++;
      }
      final neg = trainSet.length - pos;
      posWeights[k] = pos == 0 ? 1 : (neg / pos).clamp(1.0, 10.0).toDouble();
    }

    final network = LstmNetwork(
      inputSize: kLstmFeatureCols.length,
      hiddenSize: config.hiddenSize,
      outputSize: kLstmAlertTypes.length,
      seed: config.seed,
    );

    final epochStats = <EpochStat>[];
    var bestValLoss = double.infinity;
    var bestValAccuracy = 0.0;
    LstmNetwork best = network.clone();
    var badEpochs = 0;
    double? firstValLoss;

    for (var epoch = 1; epoch <= config.epochs; epoch++) {
      if (_cancelRequested) break;
      trainSet.shuffle(rng);

      var lossSum = 0.0;
      var batchCount = 0;
      for (var start = 0; start < trainSet.length; start += config.batchSize) {
        if (_cancelRequested) break;
        final end = math.min(start + config.batchSize, trainSet.length);
        lossSum += network.trainBatch(
          trainSet.sublist(start, end),
          config.learningRate,
          posWeights,
        );
        batchCount++;
        // Yield to the event loop so UI animation stays smooth.
        await Future<void>.delayed(Duration.zero);
      }
      if (_cancelRequested) break;

      final trainLoss = batchCount == 0 ? 0.0 : lossSum / batchCount;
      final eval = network.evaluate(valSet, posWeights);
      firstValLoss ??= eval.loss;

      epochStats.add(EpochStat(
        epoch: epoch,
        trainLoss: trainLoss,
        valLoss: eval.loss,
        valAccuracy: eval.accuracy,
        valF1: eval.f1,
      ));

      if (eval.loss < bestValLoss - 1e-5) {
        bestValLoss = eval.loss;
        bestValAccuracy = eval.accuracy;
        best = network.clone();
        badEpochs = 0;
      } else {
        badEpochs++;
      }

      final learning = _isLearning(epochStats, firstValLoss);
      yield LstmTrainingUpdate(
        phase: LstmTrainingPhase.training,
        progress: epoch / config.epochs,
        epochs: List.unmodifiable(epochStats),
        message:
            'Epoch $epoch/${config.epochs} — train ${trainLoss.toStringAsFixed(4)}'
            ' · val ${eval.loss.toStringAsFixed(4)}'
            ' · acc ${(eval.accuracy * 100).toStringAsFixed(1)}%',
        isLearning: learning,
      );

      if (badEpochs >= config.patience) {
        yield LstmTrainingUpdate(
          phase: LstmTrainingPhase.training,
          progress: epoch / config.epochs,
          epochs: List.unmodifiable(epochStats),
          message:
              'Early stop: validation loss plateaued for ${config.patience} '
              'epochs. Keeping best weights (val ${bestValLoss.toStringAsFixed(4)}).',
          isLearning: learning,
        );
        break;
      }
    }

    final learning = _isLearning(epochStats, firstValLoss);
    result = LstmTrainingResult(
      network: best,
      scaler: scaler,
      epochs: epochStats,
      isLearning: learning,
      bestValLoss: bestValLoss.isFinite ? bestValLoss : 0,
      bestValAccuracy: bestValAccuracy,
      sampleCount: samples.length,
    );

    yield LstmTrainingUpdate(
      phase: _cancelRequested ? LstmTrainingPhase.stopped : LstmTrainingPhase.done,
      progress: 1,
      epochs: List.unmodifiable(epochStats),
      message: _cancelRequested
          ? 'Training stopped — best weights so far were kept.'
          : learning
              ? 'Training complete. The LSTM is learning: validation loss '
                  'dropped from ${firstValLoss?.toStringAsFixed(4)} to '
                  '${bestValLoss.toStringAsFixed(4)}.'
              : 'Training finished but the validation loss barely moved. '
                  'Upload more (or more varied) history and retrain.',
      isLearning: learning,
    );
  }

  /// Populated when the stream finishes.
  LstmTrainingResult? result;

  /// Learning verdict: the model counts as "learning" once validation loss
  /// dropped at least 3% below its starting value with 3+ epochs observed.
  static bool _isLearning(List<EpochStat> stats, double? firstValLoss) {
    if (stats.length < 3 || firstValLoss == null || firstValLoss == 0) {
      return false;
    }
    final best = stats.map((e) => e.valLoss).reduce(math.min);
    return best <= firstValLoss * 0.97;
  }
}

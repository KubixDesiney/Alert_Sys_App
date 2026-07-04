import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'forecast_types.dart';

/// A real, dependency-free gradient-boosting engine implemented in pure Dart.
///
/// Architecture: one boosted ensemble of regression trees per canonical alert
/// type, trained with second-order (Newton) gradient boosting on logistic
/// loss — the same formulation XGBoost/LightGBM use: histogram split finding,
/// leaf weights `-G/(H+λ)`, L2 regularization, row/feature subsampling and
/// shrinkage. Nothing here is simulated — the loss curves shown in the
/// SuperAdmin console come straight from these updates.

double _sigmoid(double x) {
  if (x >= 0) {
    final z = math.exp(-x);
    return 1.0 / (1.0 + z);
  }
  final z = math.exp(x);
  return z / (1.0 + z);
}

/// One regression tree stored as flat parallel arrays.
/// `feature[i] < 0` marks node `i` as a leaf with value `weight[i]`
/// (shrinkage already folded in). Split rule: go left when `x[f] <= thr`.
class BoostTree {
  final Int32List feature;
  final Float64List threshold;
  final Int32List left;
  final Int32List right;
  final Float64List weight;

  const BoostTree({
    required this.feature,
    required this.threshold,
    required this.left,
    required this.right,
    required this.weight,
  });

  double predict(Float64List x) {
    var node = 0;
    while (feature[node] >= 0) {
      node = x[feature[node]] <= threshold[node] ? left[node] : right[node];
    }
    return weight[node];
  }

  int get nodeCount => feature.length;

  Map<String, dynamic> toJson() => {
        'f': feature.toList(),
        't': [for (final v in threshold) _compact(v)],
        'l': left.toList(),
        'r': right.toList(),
        'w': [for (final v in weight) _compact(v)],
      };

  static double _compact(double v) =>
      double.parse(v.toStringAsPrecision(7));

  factory BoostTree.fromJson(Map<String, dynamic> json) => BoostTree(
        feature: Int32List.fromList(
            (json['f'] as List).map((e) => (e as num).toInt()).toList()),
        threshold: Float64List.fromList(
            (json['t'] as List).map((e) => (e as num).toDouble()).toList()),
        left: Int32List.fromList(
            (json['l'] as List).map((e) => (e as num).toInt()).toList()),
        right: Int32List.fromList(
            (json['r'] as List).map((e) => (e as num).toInt()).toList()),
        weight: Float64List.fromList(
            (json['w'] as List).map((e) => (e as num).toDouble()).toList()),
      );
}

/// The trained forecaster: per-type tree ensembles plus prior log-odds.
class GradientBoostModel {
  final int featureCount;

  /// Prior log-odds per type (margin before any tree).
  final Float64List baseScores;

  /// trees[k] is the boosted sequence for type k.
  final List<List<BoostTree>> trees;

  /// Ordered alert-type codes this model learned (one ensemble per entry).
  /// Persisted so inference rebuilds the identical feature vector and labels
  /// each output; defaults to [kForecastAlertTypes] for legacy models.
  final List<String> types;

  /// Rounds contributed by the original console training run.
  int baseRounds;

  /// Rounds appended afterwards by continuous learning.
  int adaptedRounds;

  /// Per-type decision thresholds for "alert called" classification, tuned
  /// post-training via validation-set F1 grid search. Defaults to 0.5 for
  /// untuned/legacy models.
  Float64List thresholds;

  GradientBoostModel({
    required this.featureCount,
    required this.baseScores,
    required this.trees,
    this.baseRounds = 0,
    this.adaptedRounds = 0,
    List<String>? types,
    Float64List? thresholds,
  })  : types = types ?? kForecastAlertTypes,
        thresholds = thresholds ??
            Float64List.fromList(
                List.filled((types ?? kForecastAlertTypes).length, 0.5));

  factory GradientBoostModel.empty({
    required int featureCount,
    required Float64List baseScores,
    List<String> types = kForecastAlertTypes,
  }) =>
      GradientBoostModel(
        featureCount: featureCount,
        baseScores: baseScores,
        types: types,
        trees: [for (var k = 0; k < types.length; k++) <BoostTree>[]],
      );

  int get outputSize => trees.length;

  /// Total trees across all types.
  int get treeCount => trees.fold(0, (a, t) => a + t.length);

  /// Rounds present per type (all types boost in lockstep).
  int get roundsPerType => trees.isEmpty ? 0 : trees.first.length;

  double margin(int type, Float64List x) {
    var m = baseScores[type];
    for (final tree in trees[type]) {
      m += tree.predict(x);
    }
    return m;
  }

  /// Per-type probabilities for one engineered feature row.
  Float64List predict(Float64List x) {
    final out = Float64List(outputSize);
    for (var k = 0; k < outputSize; k++) {
      out[k] = _sigmoid(margin(k, x));
    }
    return out;
  }

  /// Copy truncated to the first [roundsPerType] trees of every type — used
  /// to snapshot the best early-stopping round without re-training.
  GradientBoostModel truncated(int rounds) => GradientBoostModel(
        featureCount: featureCount,
        baseScores: Float64List.fromList(baseScores),
        types: types,
        trees: [
          for (final seq in trees) seq.sublist(0, math.min(rounds, seq.length))
        ],
        baseRounds: math.min(rounds, roundsPerType),
        adaptedRounds: 0,
        thresholds: Float64List.fromList(thresholds),
      );

  GradientBoostModel clone() => GradientBoostModel(
        featureCount: featureCount,
        baseScores: Float64List.fromList(baseScores),
        types: types,
        trees: [for (final seq in trees) List<BoostTree>.of(seq)],
        baseRounds: baseRounds,
        adaptedRounds: adaptedRounds,
        thresholds: Float64List.fromList(thresholds),
      );

  Map<String, dynamic> toJson() => {
        'algo': 'gbdt',
        'featureCount': featureCount,
        'types': types,
        'base': [for (final b in baseScores) BoostTree._compact(b)],
        'baseRounds': baseRounds,
        'adaptedRounds': adaptedRounds,
        'thresholds': [for (final v in thresholds) BoostTree._compact(v)],
        'trees': [
          for (final seq in trees) [for (final t in seq) t.toJson()]
        ],
      };

  String toJsonString() => jsonEncode(toJson());

  factory GradientBoostModel.fromJson(Map<String, dynamic> json) {
    final treesJson = json['trees'] as List;
    final thresholdsJson = json['thresholds'] as List?;
    final typesJson = json['types'] as List?;
    return GradientBoostModel(
      featureCount: (json['featureCount'] as num).toInt(),
      types: typesJson != null
          ? typesJson.map((e) => e.toString()).toList()
          : null,
      baseScores: Float64List.fromList(
          (json['base'] as List).map((e) => (e as num).toDouble()).toList()),
      trees: [
        for (final seq in treesJson)
          [
            for (final t in (seq as List))
              BoostTree.fromJson(Map<String, dynamic>.from(t as Map))
          ]
      ],
      baseRounds: (json['baseRounds'] as num?)?.toInt() ?? 0,
      adaptedRounds: (json['adaptedRounds'] as num?)?.toInt() ?? 0,
      thresholds: thresholdsJson != null
          ? Float64List.fromList(
              thresholdsJson.map((e) => (e as num).toDouble()).toList())
          : null,
    );
  }

  factory GradientBoostModel.fromJsonString(String json) =>
      GradientBoostModel.fromJson(
          jsonDecode(json) as Map<String, dynamic>);
}

/// Histogram-based booster operating over a fixed train/validation split.
///
/// The trainer owns the split and the round loop; this class owns the math:
/// gradients/hessians from the current margins, histogram split search, leaf
/// weights, margin updates, and loss/accuracy/F1 evaluation.
class GbdtBooster {
  final List<Float64List> trainX;
  final List<Float64List> trainY;
  final List<Float64List> valX;
  final List<Float64List> valY;
  final ForecastTrainingConfig config;
  final GradientBoostModel model;

  /// Weight applied to positive examples per type (class imbalance).
  final Float64List posWeights;

  // Margins cached per type per row, updated after every tree.
  late final List<Float64List> _trainMargins;
  late final List<Float64List> _valMargins;

  // Per-feature histogram binning of the training matrix.
  static const int _maxBins = 64;
  late final List<Uint8List> _binned; // [feature][row] -> bin
  late final List<Float64List> _binEdges; // [feature][bin] -> upper edge

  final math.Random _rng;

  GbdtBooster({
    required this.trainX,
    required this.trainY,
    required this.valX,
    required this.valY,
    required this.config,
    GradientBoostModel? resume,
    List<String> types = kForecastAlertTypes,
  })  : posWeights = _computePosWeights(trainY, config.posWeightCap),
        model = resume?.clone() ??
            GradientBoostModel.empty(
              featureCount: trainX.isEmpty
                  ? forecastFeatureCountFor(types.length)
                  : trainX.first.length,
              baseScores: _priorLogOdds(trainY, types.length),
              types: types,
            ),
        _rng = math.Random(config.seed) {
    _trainMargins = _replayMargins(trainX);
    _valMargins = _replayMargins(valX);
    _buildBins();
  }

  static Float64List _computePosWeights(List<Float64List> y, double cap) {
    final k = y.isEmpty ? 0 : y.first.length;
    final out = Float64List(k);
    for (var t = 0; t < k; t++) {
      var pos = 0;
      for (final row in y) {
        if (row[t] >= 0.5) pos++;
      }
      final neg = y.length - pos;
      out[t] = pos == 0 ? 1 : (neg / pos).clamp(1.0, cap).toDouble();
    }
    return out;
  }

  static Float64List _priorLogOdds(List<Float64List> y, int k) {
    final out = Float64List(k);
    for (var t = 0; t < k; t++) {
      var pos = 0;
      for (final row in y) {
        if (row[t] >= 0.5) pos++;
      }
      // Laplace-smoothed prior keeps the margin finite for absent classes.
      final p = (pos + 0.5) / (y.length + 1.0);
      out[t] = math.log(p / (1 - p)).clamp(-6.0, 6.0).toDouble();
    }
    return out;
  }

  List<Float64List> _replayMargins(List<Float64List> x) {
    final k = model.outputSize;
    final out = [for (var t = 0; t < k; t++) Float64List(x.length)];
    for (var i = 0; i < x.length; i++) {
      for (var t = 0; t < k; t++) {
        out[t][i] = model.margin(t, x[i]);
      }
    }
    return out;
  }

  void _buildBins() {
    final nFeatures = model.featureCount;
    final n = trainX.length;
    _binned = [for (var f = 0; f < nFeatures; f++) Uint8List(n)];
    _binEdges = List.generate(nFeatures, (_) => Float64List(0));
    if (n == 0) return;

    final values = Float64List(n);
    for (var f = 0; f < nFeatures; f++) {
      for (var i = 0; i < n; i++) {
        values[i] = trainX[i][f];
      }
      final sorted = Float64List.fromList(values)..sort();
      // Quantile edges over distinct values, at most [_maxBins] bins.
      final edges = <double>[];
      for (var b = 1; b < _maxBins; b++) {
        final q = sorted[(b * (n - 1)) ~/ _maxBins];
        if (edges.isEmpty || q > edges.last) edges.add(q);
      }
      final edgeArr = Float64List.fromList(edges);
      _binEdges[f] = edgeArr;
      for (var i = 0; i < n; i++) {
        _binned[f][i] = _binOf(edgeArr, values[i]);
      }
    }
  }

  static int _binOf(Float64List edges, double v) {
    // Upper-bound binary search: first edge >= v; values above all edges land
    // in the overflow bin (edges.length).
    var lo = 0;
    var hi = edges.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (v <= edges[mid]) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Draws the row subsample shared by one boosting round's trees.
  List<int> sampleRows() {
    final n = trainX.length;
    if (config.subsample >= 0.999) {
      return List<int>.generate(n, (i) => i);
    }
    final rows = <int>[];
    for (var i = 0; i < n; i++) {
      if (_rng.nextDouble() < config.subsample) rows.add(i);
    }
    if (rows.length < 8) return List<int>.generate(n, (i) => i);
    return rows;
  }

  /// Grows one tree for alert type [t] against the current margins, folds the
  /// shrunken tree into the model, and refreshes the cached margins. Split
  /// per type so the trainer can yield to the event loop mid-round.
  void boostType(int t, List<int> rows) {
    final n = trainX.length;
    if (n == 0) return;

    final grad = Float64List(n);
    final hess = Float64List(n);
    final w = posWeights[t];
    for (var i = 0; i < n; i++) {
      final p = _sigmoid(_trainMargins[t][i]);
      final y = trainY[i][t];
      final sw = y >= 0.5 ? w : 1.0;
      grad[i] = sw * (p - y);
      hess[i] = math.max(sw * p * (1 - p), 1e-9);
    }

    final tree = _growTree(rows, grad, hess);
    model.trees[t].add(tree);

    for (var i = 0; i < n; i++) {
      _trainMargins[t][i] += tree.predict(trainX[i]);
    }
    for (var i = 0; i < valX.length; i++) {
      _valMargins[t][i] += tree.predict(valX[i]);
    }
  }

  /// Grows one tree per alert type (one full boosting round).
  void boostOneRound() {
    final rows = sampleRows();
    for (var t = 0; t < model.outputSize; t++) {
      boostType(t, rows);
    }
  }

  BoostTree _growTree(List<int> rows, Float64List grad, Float64List hess) {
    final features = <int>[];
    final thresholds = <double>[];
    final lefts = <int>[];
    final rights = <int>[];
    final weights = <double>[];

    // Feature subsample per tree.
    final nFeatures = model.featureCount;
    var candidateFeatures = List<int>.generate(nFeatures, (f) => f);
    if (config.colsample < 0.999) {
      candidateFeatures.shuffle(_rng);
      final keep =
          math.max(1, (nFeatures * config.colsample).round());
      candidateFeatures = candidateFeatures.sublist(0, keep)..sort();
    }

    int build(List<int> nodeRows, int depth) {
      final idx = features.length;
      features.add(-1);
      thresholds.add(0);
      lefts.add(-1);
      rights.add(-1);
      weights.add(0);

      var gSum = 0.0;
      var hSum = 0.0;
      for (final i in nodeRows) {
        gSum += grad[i];
        hSum += hess[i];
      }

      double leafWeight() =>
          -gSum / (hSum + config.l2) * config.learningRate;

      if (depth >= config.maxDepth ||
          nodeRows.length < 2 * config.minSamplesLeaf) {
        weights[idx] = leafWeight();
        return idx;
      }

      // Histogram split search.
      var bestGain = 1e-6;
      var bestFeature = -1;
      var bestBin = -1;
      final parentScore = gSum * gSum / (hSum + config.l2);
      final histG = Float64List(_maxBins);
      final histH = Float64List(_maxBins);
      final histC = Int32List(_maxBins);

      for (final f in candidateFeatures) {
        final edges = _binEdges[f];
        if (edges.isEmpty) continue;
        final bins = edges.length + 1;
        for (var b = 0; b < bins; b++) {
          histG[b] = 0;
          histH[b] = 0;
          histC[b] = 0;
        }
        final col = _binned[f];
        for (final i in nodeRows) {
          final b = col[i];
          histG[b] += grad[i];
          histH[b] += hess[i];
          histC[b]++;
        }
        var gl = 0.0;
        var hl = 0.0;
        var cl = 0;
        for (var b = 0; b < bins - 1; b++) {
          gl += histG[b];
          hl += histH[b];
          cl += histC[b];
          final cr = nodeRows.length - cl;
          if (cl < config.minSamplesLeaf || cr < config.minSamplesLeaf) {
            continue;
          }
          final gr = gSum - gl;
          final hr = hSum - hl;
          final gain = gl * gl / (hl + config.l2) +
              gr * gr / (hr + config.l2) -
              parentScore;
          if (gain > bestGain) {
            bestGain = gain;
            bestFeature = f;
            bestBin = b;
          }
        }
      }

      if (bestFeature < 0) {
        weights[idx] = leafWeight();
        return idx;
      }

      final leftRows = <int>[];
      final rightRows = <int>[];
      final col = _binned[bestFeature];
      for (final i in nodeRows) {
        (col[i] <= bestBin ? leftRows : rightRows).add(i);
      }

      features[idx] = bestFeature;
      thresholds[idx] = _binEdges[bestFeature][bestBin];
      lefts[idx] = build(leftRows, depth + 1);
      rights[idx] = build(rightRows, depth + 1);
      return idx;
    }

    build(rows, 0);
    return BoostTree(
      feature: Int32List.fromList(features),
      threshold: Float64List.fromList(thresholds),
      left: Int32List.fromList(lefts),
      right: Int32List.fromList(rights),
      weight: Float64List.fromList(weights),
    );
  }

  ({double loss, double accuracy, double f1}) evalTrain(
          {Float64List? thresholds}) =>
      _eval(_trainMargins, trainY, thresholds ?? _defaultThresholds);

  ({double loss, double accuracy, double f1}) evalVal(
          {Float64List? thresholds}) =>
      _eval(_valMargins, valY, thresholds ?? _defaultThresholds);

  Float64List get _defaultThresholds =>
      Float64List.fromList(List.filled(model.outputSize, 0.5));

  /// Grid-searches a per-type decision threshold (0.05–0.95) that maximizes
  /// validation F1 for that type. Types with no positive examples in the
  /// validation set keep the default 0.5 (nothing to tune against).
  Float64List bestValThresholds() {
    final k = model.outputSize;
    final out = _defaultThresholds;
    if (valY.isEmpty) return out;
    for (var t = 0; t < k; t++) {
      var hasPositive = false;
      for (final row in valY) {
        if (row[t] >= 0.5) {
          hasPositive = true;
          break;
        }
      }
      if (!hasPositive) continue;

      var bestThr = 0.5;
      var bestF1 = -1.0;
      for (var step = 1; step <= 37; step++) {
        final thr = 0.05 + step * 0.025;
        var tp = 0, fp = 0, fn = 0;
        for (var i = 0; i < valY.length; i++) {
          final p = _sigmoid(_valMargins[t][i]);
          final pred = p >= thr;
          final truth = valY[i][t] >= 0.5;
          if (pred && truth) tp++;
          if (pred && !truth) fp++;
          if (!pred && truth) fn++;
        }
        final denom = 2 * tp + fp + fn;
        final f1 = denom == 0 ? 0.0 : 2 * tp / denom;
        if (f1 > bestF1) {
          bestF1 = f1;
          bestThr = thr;
        }
      }
      out[t] = bestThr;
    }
    return out;
  }

  /// Weighted BCE / accuracy / macro-F1 from cached margins — the same metric
  /// semantics the previous forecaster reported, so verdicts stay comparable.
  /// [thresholds] selects the per-type "alert called" cutoff used for
  /// accuracy/F1; loss is threshold-independent.
  ({double loss, double accuracy, double f1}) _eval(
    List<Float64List> margins,
    List<Float64List> y,
    Float64List thresholds,
  ) {
    final n = y.length;
    final k = model.outputSize;
    if (n == 0) return (loss: 0, accuracy: 0, f1: 0);
    var loss = 0.0;
    var correct = 0;
    var total = 0;
    final tp = List<int>.filled(k, 0);
    final fp = List<int>.filled(k, 0);
    final fn = List<int>.filled(k, 0);

    for (var i = 0; i < n; i++) {
      for (var t = 0; t < k; t++) {
        final target = y[i][t];
        final p = _sigmoid(margins[t][i]).clamp(1e-7, 1 - 1e-7);
        final w = posWeights[t];
        loss += -(w * target * math.log(p) + (1 - target) * math.log(1 - p));
        final pred = p >= thresholds[t];
        final truth = target >= 0.5;
        if (pred == truth) correct++;
        if (pred && truth) tp[t]++;
        if (pred && !truth) fp[t]++;
        if (!pred && truth) fn[t]++;
        total++;
      }
    }
    var f1Sum = 0.0;
    var f1Count = 0;
    for (var t = 0; t < k; t++) {
      final denom = 2 * tp[t] + fp[t] + fn[t];
      if (tp[t] + fn[t] == 0) continue; // class absent in this set
      f1Sum += denom == 0 ? 0 : 2 * tp[t] / denom;
      f1Count++;
    }
    return (
      loss: loss / (n * k),
      accuracy: total == 0 ? 0 : correct / total,
      f1: f1Count == 0 ? 0 : f1Sum / f1Count,
    );
  }
}

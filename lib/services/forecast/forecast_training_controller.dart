import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../models/alert_type.dart';
import '../alert_type_registry.dart';
import '../app_logger.dart';
import 'alert_record_parser.dart';
import 'forecast_engine.dart';
import 'forecast_feature_engineer.dart';
import 'forecast_model_store.dart';
import 'forecast_trainer.dart';
import 'forecast_types.dart';
import 'gradient_boost.dart';

const List<String> _adaptivePalette = [
  '#7C3AED',
  '#EA580C',
  '#0891B2',
  '#4F46E5',
  '#DB2777',
  '#0F766E',
  '#9333EA',
  '#B45309',
];

/// Converts previously unseen type buckets from uploaded buyer history into
/// real tenant alert definitions. The parser has already normalized labels to
/// safe snake_case; limits prevent accidental high-cardinality columns from
/// exploding the per-type ensemble.
List<AlertTypeDef> inferAdaptiveAlertTypeDefs({
  required List<AlertTypeDef> existing,
  required Map<String, int> typeCounts,
  int maxNewTypes = 24,
}) {
  final existingCodes = existing.map((type) => type.code).toSet();
  final candidates = typeCounts.entries
      .where(
        (entry) =>
            entry.value > 0 &&
            entry.key != 'unknown' &&
            !existingCodes.contains(entry.key) &&
            RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(entry.key),
      )
      .toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  final firstOrder = existing.isEmpty
      ? 0
      : existing
              .map((type) => type.order)
              .reduce((left, right) => left > right ? left : right) +
          1;
  return [
    for (final indexed in candidates.take(maxNewTypes).indexed)
      AlertTypeDef(
        code: indexed.$2.key,
        label: indexed.$2.key
            .split('_')
            .where((part) => part.isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' '),
        colorHex: _adaptivePalette[indexed.$1 % _adaptivePalette.length],
        icon: 'sensors',
        synonyms: [indexed.$2.key.replaceAll('_', ' ')],
        severityDefault:
            RegExp(r'critical|emergency|safety|fire').hasMatch(indexed.$2.key)
                ? 'critical'
                : 'normal',
        order: firstOrder + indexed.$1,
      ),
  ];
}

/// App-global owner of the forecast-model training lifecycle.
///
/// The SuperAdmin training tab is just a *view* of this controller, so a run
/// keeps learning when the operator switches tabs, navigates anywhere else in
/// the console, or signs out while the app stays open. On top of that the
/// controller checkpoints the run (trees + round stats + dataset) to
/// `ai_forecast/training/*`, so if the browser tab or app is closed mid-run,
/// the next SuperAdmin session picks the run back up from the last checkpoint
/// and finishes it.
class ForecastTrainingController extends ChangeNotifier {
  ForecastTrainingController._()
      : _sessionId =
            'sa-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(0x7fffffff)}';

  static final ForecastTrainingController instance =
      ForecastTrainingController._();

  static const AppLogger _log = AppLogger();
  final ForecastModelStore _store = ForecastModelStore();
  final ForecastTrainer _trainer = ForecastTrainer();
  final String _sessionId;

  // ── Dataset state ─────────────────────────────────────────────────────────
  bool _parsing = false;
  ParsedDataset? _dataset;
  List<FeatureSample> _samples = const [];
  String? _error;
  ForecastTrainingConfig _config = ForecastTrainingConfig.auto(0);

  /// The ordered alert-type set this run trains on. Captured from the live
  /// registry at upload time (or restored from a resumed model), and baked into
  /// the deployed model's metadata so inference rebuilds the identical schema.
  List<String> _trainTypes = List<String>.of(kForecastAlertTypes);

  static List<String> _activeTypes() {
    final codes = AlertTypeRegistry.instance.codes;
    return codes.isEmpty ? List<String>.of(kForecastAlertTypes) : codes;
  }

  // ── Run state ─────────────────────────────────────────────────────────────
  bool _training = false;
  bool _resumedRun = false;
  ForecastTrainingUpdate? _lastUpdate;
  ForecastTrainingResult? _result;
  List<MachineForecast> _previewForecasts = const [];
  List<String> _diagnostics = const [];

  // ── Deploy state ──────────────────────────────────────────────────────────
  bool _deploying = false;
  String? _deployMessage;

  // ── Resume / spectate state ───────────────────────────────────────────────
  bool _resumeChecked = false;
  bool _restoring = false;
  bool _remoteActive = false;
  ForecastTrainingUpdate? _remoteUpdate;
  DateTime? _remoteSeenAt;
  StreamSubscription<Map<String, dynamic>?>? _remoteSub;
  Timer? _takeoverTimer;
  DateTime _lastTelemetryAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCheckpointAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get parsing => _parsing;
  ParsedDataset? get dataset => _dataset;
  List<FeatureSample> get samples => _samples;
  String? get error => _error;
  ForecastTrainingConfig get config => _config;
  bool get training => _training;

  /// True when the visible run was restored from a checkpoint (closed tab or
  /// another session) rather than started here.
  bool get resumedRun => _resumedRun;
  ForecastTrainingResult? get result => _result;
  List<MachineForecast> get previewForecasts => _previewForecasts;

  /// Operator-readable reasons behind a NOT-LEARNING verdict (empty while the
  /// run is in flight or when the model learned).
  List<String> get diagnostics => _diagnostics;
  bool get deploying => _deploying;
  String? get deployMessage => _deployMessage;
  bool get restoring => _restoring;

  /// Another console session currently owns a live run.
  bool get remoteActive => _remoteActive && !_training;

  /// What the monitor should render: local run first, then remote telemetry.
  ForecastTrainingUpdate? get lastUpdate =>
      _training || _lastUpdate != null ? _lastUpdate : _remoteUpdate;

  /// True when any run (local or remote) is in flight.
  bool get runActive => _training || remoteActive;

  void setConfig(ForecastTrainingConfig config) {
    _config = config;
    notifyListeners();
  }

  // ── Upload / parse ────────────────────────────────────────────────────────

  Future<void> loadDataset({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (_parsing || _training) return;
    _parsing = true;
    _error = null;
    _dataset = null;
    _result = null;
    _previewForecasts = const [];
    _diagnostics = const [];
    _lastUpdate = null;
    _deployMessage = null;
    notifyListeners();
    // Let the spinner paint before heavy parsing starts.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      _trainTypes = _activeTypes();
      var parsed = await AlertRecordParser.parse(
        fileName: fileName,
        bytes: bytes,
        types: AlertTypeRegistry.instance.types,
      );
      if (await _adaptiveSchemaEnabled()) {
        final inferred = inferAdaptiveAlertTypeDefs(
          existing: AlertTypeRegistry.instance.types,
          typeCounts: parsed.summary.typeCounts,
        );
        if (inferred.isNotEmpty) {
          await AlertTypeRegistry.instance.saveMissing(inferred);
          _trainTypes = [..._trainTypes, ...inferred.map((type) => type.code)];
          parsed = ParsedDataset(
            records: parsed.records,
            warnings: [
              ...parsed.warnings,
              'Adaptive schema added ${inferred.length} ${inferred.length == 1 ? 'alert type' : 'alert types'} from this dataset.',
            ],
            summary: parsed.summary,
          );
        }
      }
      final rows = ForecastFeatureEngineer.buildDailyRows(
        parsed.records,
        types: _trainTypes,
      );
      final samples = ForecastFeatureEngineer.buildSamples(rows);
      _dataset = parsed;
      _samples = samples;
      _config = ForecastTrainingConfig.auto(samples.length);
      _parsing = false;
      notifyListeners();
      // Persist the dataset so a closed tab can resume an interrupted run.
      unawaited(_persistDataset(parsed));
    } catch (e) {
      _parsing = false;
      _error = e is FormatException ? e.message : e.toString();
      notifyListeners();
    }
  }

  Future<bool> _adaptiveSchemaEnabled() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('app_config/entitlements/adaptiveAlertSchema')
          .get();
      return snapshot.value == true;
    } catch (_) {
      // Entitlements fail closed: a Starter/offline client must never expand
      // the tenant schema merely because a file was selected.
      return false;
    }
  }

  Future<void> _persistDataset(ParsedDataset parsed) async {
    try {
      await _store.saveDatasetBlob(
        name: parsed.summary.sourceName,
        kind: parsed.summary.sourceKind,
        blob: _encodeRecords(parsed.records),
        recordCount: parsed.records.length,
      );
    } catch (e) {
      _log.warning('Forecast dataset persistence failed: $e');
    }
  }

  // ── Training ──────────────────────────────────────────────────────────────

  void startTraining(ForecastTrainingConfig config) {
    if (_samples.isEmpty || _training) return;
    _config = config;
    _resumedRun = false;
    unawaited(_run());
  }

  void cancelTraining() => _trainer.cancel();

  Future<void> _run({
    GradientBoostModel? resumeModel,
    int startRound = 1,
    List<RoundStat> resumeStats = const [],
  }) async {
    if (_samples.isEmpty || _training) return;
    _stopSpectating();
    _training = true;
    _result = null;
    _previewForecasts = const [];
    _diagnostics = const [];
    _deployMessage = null;
    _error = null;
    if (resumeStats.isNotEmpty) {
      // Show the checkpoint's real progress immediately instead of an empty
      // monitor while the first resumed round computes.
      _lastUpdate = ForecastTrainingUpdate(
        phase: ForecastTrainingPhase.training,
        progress: (resumeStats.last.round / _config.rounds)
            .clamp(0.0, 1.0)
            .toDouble(),
        rounds: resumeStats,
        message:
            'Resumed from checkpoint — continuing at round $startRound/${_config.rounds}.',
        isLearning: ForecastTrainer.isLearningFromStats(resumeStats),
      );
    }
    notifyListeners();

    final datasetName = _dataset?.summary.sourceName ?? 'dataset';
    unawaited(
      _store.writeTrainingStatus(
        status: 'running',
        progress: resumeStats.isEmpty
            ? 0
            : (resumeStats.last.round / _config.rounds)
                .clamp(0.0, 1.0)
                .toDouble(),
        message: startRound > 1
            ? 'Resumed from checkpoint at round ${startRound - 1} ($datasetName)'
            : 'Training started on $datasetName',
        rounds: resumeStats,
      ),
    );

    try {
      await for (final update in _trainer.train(
        samples: _samples,
        config: _config,
        types: _trainTypes,
        resumeModel: resumeModel,
        startRound: startRound,
        resumeStats: resumeStats,
      )) {
        _lastUpdate = update;
        notifyListeners();
        if (update.phase == ForecastTrainingPhase.training) {
          _maybeWriteTelemetry(update);
          _maybeCheckpoint(update, datasetName);
        }
      }

      final result = _trainer.result;
      _training = false;
      _result = result;
      if (result != null && _dataset != null) {
        _previewForecasts = ForecastEngine.computeForecasts(
          TrainedForecastModel(model: result.model),
          _dataset!.records,
          now: _dataset!.summary.lastTimestamp,
        );
      }
      final stopped = _lastUpdate?.phase == ForecastTrainingPhase.stopped;
      if (result != null && !result.isLearning) {
        _diagnostics = ForecastTrainer.diagnose(
          samples: _samples,
          rounds: result.rounds,
          config: _config,
          types: _trainTypes,
          summary: _dataset?.summary,
          cancelled: stopped,
        );
      }
      notifyListeners();

      unawaited(
        _store.writeTrainingStatus(
          status: result == null ? 'failed' : (stopped ? 'stopped' : 'done'),
          progress: 1,
          message: _lastUpdate?.message ?? 'finished',
          rounds: _lastUpdate?.rounds ?? const [],
        ),
      );
      // Final checkpoint: a finished-but-undeployed model survives a closed
      // tab and is offered for deployment on the next console session.
      if (result != null) {
        await _writeCheckpoint(
          status: stopped ? 'stopped' : 'done',
          model: result.model,
          bestRound: result.model.roundsPerType,
          rounds: result.rounds,
          isLearning: result.isLearning,
          datasetName: datasetName,
        );
      } else {
        unawaited(_safeClearCheckpoint());
      }
    } catch (e) {
      _training = false;
      _error = 'Training failed: $e';
      notifyListeners();
      unawaited(
        _store.writeTrainingStatus(
          status: 'failed',
          progress: 0,
          message: '$e',
        ),
      );
      unawaited(_safeClearCheckpoint());
    }
  }

  void _maybeWriteTelemetry(ForecastTrainingUpdate update) {
    final now = DateTime.now();
    if (now.difference(_lastTelemetryAt).inMilliseconds < 2000) return;
    _lastTelemetryAt = now;
    unawaited(
      _store.writeTrainingStatus(
        status: 'running',
        progress: update.progress,
        message: update.message,
        rounds: update.rounds,
      ),
    );
  }

  void _maybeCheckpoint(ForecastTrainingUpdate update, String datasetName) {
    final now = DateTime.now();
    if (now.difference(_lastCheckpointAt).inSeconds < 10) return;
    _lastCheckpointAt = now;
    final model = _trainer.liveModel;
    if (model == null) return;
    unawaited(
      _writeCheckpoint(
        status: 'running',
        model: model,
        bestRound: _trainer.liveBestRound,
        rounds: update.rounds,
        isLearning: update.isLearning,
        datasetName: datasetName,
      ),
    );
  }

  Future<void> _writeCheckpoint({
    required String status,
    required GradientBoostModel model,
    required int bestRound,
    required List<RoundStat> rounds,
    required bool isLearning,
    required String datasetName,
  }) async {
    try {
      await _store.saveCheckpoint(
        status: status,
        owner: _sessionId,
        model: model,
        bestRound: bestRound,
        config: _config,
        rounds: rounds,
        datasetName: datasetName,
        sampleCount: _samples.length,
        isLearning: isLearning,
      );
    } catch (e) {
      // Offline or signed out: training continues in memory; the next
      // successful checkpoint write re-establishes durability.
      _log.warning('Forecast checkpoint write failed: $e');
    }
  }

  Future<void> _safeClearCheckpoint() async {
    try {
      await _store.clearCheckpoint();
    } catch (_) {}
  }

  // ── Deploy ────────────────────────────────────────────────────────────────

  Future<void> deploy() async {
    final result = _result;
    if (result == null || _deploying) return;
    _deploying = true;
    _deployMessage = null;
    notifyListeners();
    try {
      await _store.saveModel(
        model: result.model,
        datasetName: _dataset?.summary.sourceName ?? 'dataset',
        sampleCount: result.sampleCount,
        valLoss: result.bestValLoss,
        valAccuracy: result.bestValAccuracy,
        learning: result.isLearning,
        rounds: result.rounds,
      );

      // Publish a live snapshot computed from production alerts so the rest
      // of the platform sees forecasts immediately.
      List<MachineForecast> live = _previewForecasts;
      try {
        final snap = await FirebaseDatabase.instance.ref('alerts').get();
        if (snap.value is Map) {
          final records = ForecastEngine.recordsFromAlertMaps(
            (snap.value as Map).values.whereType<Map>(),
          );
          if (records.isNotEmpty) {
            live = ForecastEngine.computeForecasts(
              TrainedForecastModel(model: result.model),
              records,
            );
          }
        }
      } catch (_) {
        // fall back to dataset-based preview snapshot
      }
      await ForecastEngine.publishSnapshot(live);
      unawaited(_safeClearCheckpoint());

      _deploying = false;
      _deployMessage =
          'Model deployed. ${live.length} machines forecast live on every '
          'Production Manager dashboard.';
      notifyListeners();
    } catch (e) {
      _deploying = false;
      _deployMessage = 'Deploy failed: $e';
      notifyListeners();
    }
  }

  // ── Resume after restart / spectate other sessions ───────────────────────

  /// Called once per app session when the SuperAdmin console opens. Restores
  /// the persisted dataset, resumes an interrupted run from its checkpoint,
  /// or spectates a run that another live session currently owns.
  Future<void> ensureResumed() async {
    if (_resumeChecked || _training) return;
    _resumeChecked = true;
    _restoring = true;
    notifyListeners();
    try {
      final cp = await _store.loadCheckpoint();
      if (cp == null) {
        await _restoreDatasetOnly();
        return;
      }
      final status = (cp['status'] ?? '').toString();
      if (status == 'running') {
        final updatedAt = DateTime.tryParse((cp['updatedAt'] ?? '').toString());
        final fresh = updatedAt != null &&
            DateTime.now().toUtc().difference(updatedAt.toUtc()).inSeconds <
                120;
        if (fresh && cp['owner'] != _sessionId) {
          // A live session elsewhere owns this run — watch it instead of
          // double-training. If its heartbeat dies, we take over below.
          await _restoreDatasetOnly();
          _startSpectating();
        } else {
          await _resumeFromCheckpoint(cp);
        }
      } else if (status == 'done' || status == 'stopped') {
        await _restoreFinished(cp);
      } else {
        await _restoreDatasetOnly();
      }
    } catch (e) {
      _log.warning('Forecast resume check failed: $e');
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<bool> _restoreDatasetOnly() async {
    if (_dataset != null) return true;
    final stored = await _store.loadDatasetBlob();
    final blob = stored?['blob'];
    if (blob is! String || blob.isEmpty) return false;
    try {
      final records = _decodeRecords(blob);
      if (records.isEmpty) return false;
      final parsed = ParsedDataset(
        records: records,
        summary: _summarize(
          (stored?['name'] ?? 'dataset').toString(),
          (stored?['kind'] ?? 'restored').toString(),
          records,
        ),
        warnings: const [],
      );
      _trainTypes = _activeTypes();
      final rows = ForecastFeatureEngineer.buildDailyRows(
        records,
        types: _trainTypes,
      );
      _dataset = parsed;
      _samples = ForecastFeatureEngineer.buildSamples(rows);
      _config = ForecastTrainingConfig.auto(_samples.length);
      notifyListeners();
      return true;
    } catch (e) {
      _log.warning('Forecast dataset restore failed: $e');
      return false;
    }
  }

  /// Switches the run's training type set (e.g. after restoring a model whose
  /// types differ from the current registry) and rebuilds samples to match.
  void _adoptTrainTypes(List<String> types) {
    if (types.isEmpty) return;
    final same = _trainTypes.length == types.length &&
        () {
          for (var i = 0; i < types.length; i++) {
            if (_trainTypes[i] != types[i]) return false;
          }
          return true;
        }();
    _trainTypes = List<String>.of(types);
    if (!same && _dataset != null) {
      final rows = ForecastFeatureEngineer.buildDailyRows(
        _dataset!.records,
        types: _trainTypes,
      );
      _samples = ForecastFeatureEngineer.buildSamples(rows);
    }
  }

  Future<void> _resumeFromCheckpoint(Map<String, dynamic> cp) async {
    final restored = await _restoreCommon(cp);
    if (!restored) return;
    final weights = cp['weights']?.toString();
    if (weights == null || weights.isEmpty) return;
    final stats = _parseRoundStats(cp['roundStats']);
    final round = (cp['round'] as num?)?.toInt() ??
        (stats.isEmpty ? 0 : stats.last.round);
    if (round >= _config.rounds) {
      // Nothing left to train — treat as finished.
      await _restoreFinished(cp);
      return;
    }
    try {
      final model = GradientBoostModel.fromJsonString(weights);
      // Resume with the model's own type schema, rebuilding samples to match if
      // the current registry drifted since the run started.
      _adoptTrainTypes(model.types);
      _resumedRun = true;
      _log.info(
        'Resuming interrupted forecast run from round $round/${_config.rounds}',
      );
      unawaited(
        _run(resumeModel: model, startRound: round + 1, resumeStats: stats),
      );
    } catch (e) {
      _log.warning('Forecast checkpoint resume failed: $e');
    }
  }

  Future<void> _restoreFinished(Map<String, dynamic> cp) async {
    if (_result != null || _training) return;
    final restored = await _restoreCommon(cp);
    if (!restored) return;
    final weights = cp['weights']?.toString();
    if (weights == null || weights.isEmpty) return;
    try {
      var model = GradientBoostModel.fromJsonString(weights);
      _adoptTrainTypes(model.types);
      final bestRound = (cp['bestRound'] as num?)?.toInt();
      if (bestRound != null && bestRound < model.roundsPerType) {
        model = model.truncated(bestRound);
      }
      final stats = _parseRoundStats(cp['roundStats']);
      var bestValLoss = double.infinity;
      var bestValAccuracy = 0.0;
      for (final s in stats) {
        if (s.valLoss < bestValLoss) {
          bestValLoss = s.valLoss;
          bestValAccuracy = s.valAccuracy;
        }
      }
      _resumedRun = true;
      final learning = cp['isLearning'] == true;
      _result = ForecastTrainingResult(
        model: model,
        rounds: stats,
        isLearning: learning,
        bestValLoss: bestValLoss.isFinite ? bestValLoss : 0,
        bestValAccuracy: bestValAccuracy,
        sampleCount: (cp['sampleCount'] as num?)?.toInt() ?? _samples.length,
      );
      _diagnostics = learning
          ? const []
          : ForecastTrainer.diagnose(
              samples: _samples,
              rounds: stats,
              config: _config,
              types: _trainTypes,
              summary: _dataset?.summary,
              cancelled: (cp['status'] ?? '') == 'stopped',
            );
      _lastUpdate = ForecastTrainingUpdate(
        phase: (cp['status'] ?? '') == 'stopped'
            ? ForecastTrainingPhase.stopped
            : ForecastTrainingPhase.done,
        progress: 1,
        rounds: stats,
        message:
            'Run recovered from checkpoint — trained while this console was '
            'closed. Review the curves and deploy when ready.',
        isLearning: cp['isLearning'] == true,
      );
      if (_dataset != null) {
        _previewForecasts = ForecastEngine.computeForecasts(
          TrainedForecastModel(model: model),
          _dataset!.records,
          now: _dataset!.summary.lastTimestamp,
        );
      }
      notifyListeners();
    } catch (e) {
      _log.warning('Forecast finished-run restore failed: $e');
    }
  }

  /// Restores the dataset + config that a checkpoint references.
  Future<bool> _restoreCommon(Map<String, dynamic> cp) async {
    final ok = await _restoreDatasetOnly();
    if (!ok) return false;
    // Apply the checkpoint's config after the dataset restore — restoring the
    // dataset auto-tunes a fresh config, which must not win over the run's.
    final cfg = cp['config'];
    if (cfg is Map) {
      _config = ForecastTrainingConfig.fromMap(Map<String, dynamic>.from(cfg));
    }
    notifyListeners();
    return _samples.isNotEmpty;
  }

  void _startSpectating() {
    if (_remoteSub != null) return;
    _remoteSub = _store.trainingStatusStream().listen((m) {
      if (_training) return;
      if (m == null) {
        _remoteActive = false;
        _remoteUpdate = null;
        notifyListeners();
        return;
      }
      final status = (m['status'] ?? '').toString();
      _remoteSeenAt = DateTime.now();
      if (status == 'running') {
        final stats = _parseRoundStats(m['rounds']);
        _remoteActive = true;
        _remoteUpdate = ForecastTrainingUpdate(
          phase: ForecastTrainingPhase.training,
          progress: (m['progress'] as num?)?.toDouble() ?? 0,
          rounds: stats,
          message: '${m['message'] ?? 'Training in another session…'}',
          isLearning: ForecastTrainer.isLearningFromStats(stats),
        );
      } else {
        final wasActive = _remoteActive;
        _remoteActive = false;
        if (wasActive && (status == 'done' || status == 'stopped')) {
          // The remote run finished — pull its result for deployment here.
          unawaited(
            _store.loadCheckpoint().then((cp) {
              if (cp != null) return _restoreFinished(cp);
              return null;
            }),
          );
        }
      }
      notifyListeners();
    }, onError: (_) {});

    // Heartbeat watchdog: if the owning session dies mid-run, take over.
    _takeoverTimer?.cancel();
    _takeoverTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (_training || !_remoteActive) return;
      final seen = _remoteSeenAt;
      if (seen != null && DateTime.now().difference(seen).inSeconds < 150) {
        return;
      }
      final cp = await _store.loadCheckpoint();
      if (cp != null && (cp['status'] ?? '') == 'running') {
        _stopSpectating();
        await _resumeFromCheckpoint(cp);
      }
    });
  }

  void _stopSpectating() {
    _remoteSub?.cancel();
    _remoteSub = null;
    _takeoverTimer?.cancel();
    _takeoverTimer = null;
    _remoteActive = false;
    _remoteUpdate = null;
  }

  // ── Serialization helpers ─────────────────────────────────────────────────

  static String _encodeRecords(List<AlertRecord> records) {
    final usines = <String>[];
    final usineIndex = <String, int>{};
    final types = <String>[];
    final typeIndex = <String, int>{};
    final rows = <List<int>>[];
    for (final r in records) {
      final ui = usineIndex.putIfAbsent(r.usine, () {
        usines.add(r.usine);
        return usines.length - 1;
      });
      final ti = typeIndex.putIfAbsent(r.type, () {
        types.add(r.type);
        return types.length - 1;
      });
      rows.add([
        r.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000,
        ti,
        ui,
        r.convoyeur,
        r.poste,
        r.isCritical ? 1 : 0,
      ]);
    }
    return jsonEncode({'v': 1, 'usines': usines, 'types': types, 'rows': rows});
  }

  static List<AlertRecord> _decodeRecords(String blob) {
    final decoded = jsonDecode(blob);
    if (decoded is! Map) return const [];
    final usines =
        (decoded['usines'] as List? ?? const []).map((e) => '$e').toList();
    final types =
        (decoded['types'] as List? ?? const []).map((e) => '$e').toList();
    final rows = decoded['rows'];
    if (rows is! List) return const [];
    final records = <AlertRecord>[];
    for (final row in rows) {
      if (row is! List || row.length < 6) continue;
      final sec = (row[0] as num?)?.toInt();
      final ti = (row[1] as num?)?.toInt() ?? -1;
      final ui = (row[2] as num?)?.toInt() ?? -1;
      if (sec == null || ti < 0 || ti >= types.length) continue;
      records.add(
        AlertRecord(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            sec * 1000,
            isUtc: true,
          ),
          type: types[ti],
          usine: ui >= 0 && ui < usines.length ? usines[ui] : '',
          convoyeur: (row[3] as num?)?.toInt() ?? 0,
          poste: (row[4] as num?)?.toInt() ?? 0,
          isCritical: row[5] == 1,
        ),
      );
    }
    return records;
  }

  static DatasetSummary _summarize(
    String name,
    String kind,
    List<AlertRecord> records,
  ) {
    final typeCounts = <String, int>{};
    final factoryCounts = <String, int>{};
    final machines = <String>{};
    DateTime? first;
    DateTime? last;
    for (final r in records) {
      typeCounts[r.type] = (typeCounts[r.type] ?? 0) + 1;
      if (r.usine.isNotEmpty) {
        factoryCounts[r.usine] = (factoryCounts[r.usine] ?? 0) + 1;
      }
      machines.add(r.machineKey);
      if (first == null || r.timestamp.isBefore(first)) first = r.timestamp;
      if (last == null || r.timestamp.isAfter(last)) last = r.timestamp;
    }
    return DatasetSummary(
      sourceName: name,
      sourceKind: kind,
      totalRows: records.length,
      parsedRows: records.length,
      skippedRows: 0,
      typeCounts: typeCounts,
      factoryCounts: factoryCounts,
      firstTimestamp: first,
      lastTimestamp: last,
      machineCount: machines.length,
    );
  }

  static List<RoundStat> _parseRoundStats(Object? raw) {
    if (raw is! List) return const [];
    final stats = <RoundStat>[];
    for (final e in raw) {
      if (e is! Map) continue;
      stats.add(
        RoundStat(
          round: (e['round'] as num?)?.toInt() ?? stats.length,
          trainLoss: (e['trainLoss'] as num?)?.toDouble() ?? 0,
          valLoss: (e['valLoss'] as num?)?.toDouble() ?? 0,
          valAccuracy: (e['valAccuracy'] as num?)?.toDouble() ?? 0,
          valF1: (e['valF1'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    return stats;
  }
}

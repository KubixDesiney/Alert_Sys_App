import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../services/lstm/alert_record_parser.dart';
import '../../services/lstm/lstm_feature_engineer.dart';
import '../../services/lstm/lstm_forecast_engine.dart';
import '../../services/lstm/lstm_model_store.dart';
import '../../services/lstm/lstm_trainer.dart';
import '../../services/lstm/lstm_types.dart';
import 'superadmin_theme.dart';

/// SuperAdmin tab 1: upload historical alert data in any common format,
/// train the on-device LSTM with live learning curves, verify it is actually
/// learning, then deploy the model for every Production Manager dashboard.
class LstmTrainingTab extends StatefulWidget {
  const LstmTrainingTab({super.key});

  @override
  State<LstmTrainingTab> createState() => _LstmTrainingTabState();
}

class _LstmTrainingTabState extends State<LstmTrainingTab> {
  final _store = LstmModelStore();
  final _trainer = LstmTrainer();

  // Deployed model (live from RTDB).
  StreamSubscription<TrainedLstmModel?>? _modelSub;
  TrainedLstmModel? _deployedModel;

  // Upload / parse state.
  bool _parsing = false;
  ParsedDataset? _dataset;
  List<TrainingSample> _samples = const [];
  FeatureScaler? _scaler;
  String? _parseError;

  // Hyperparameters.
  LstmTrainingConfig _config = LstmTrainingConfig.auto(0);
  final _hiddenCtrl = TextEditingController();
  final _epochsCtrl = TextEditingController();
  final _lrCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();

  // Training state.
  bool _training = false;
  LstmTrainingUpdate? _lastUpdate;
  LstmTrainingResult? _result;
  List<MachineForecast> _previewForecasts = const [];

  // Deploy state.
  bool _deploying = false;
  String? _deployMessage;

  @override
  void initState() {
    super.initState();
    _modelSub = _store.modelStream().listen((m) {
      if (mounted) setState(() => _deployedModel = m);
    }, onError: (_) {});
    _syncConfigFields();
  }

  @override
  void dispose() {
    _modelSub?.cancel();
    _trainer.cancel();
    _hiddenCtrl.dispose();
    _epochsCtrl.dispose();
    _lrCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  void _syncConfigFields() {
    _hiddenCtrl.text = '${_config.hiddenSize}';
    _epochsCtrl.text = '${_config.epochs}';
    _lrCtrl.text = '${_config.learningRate}';
    _batchCtrl.text = '${_config.batchSize}';
  }

  LstmTrainingConfig _configFromFields() {
    return _config.copyWith(
      hiddenSize: int.tryParse(_hiddenCtrl.text)?.clamp(4, 96),
      epochs: int.tryParse(_epochsCtrl.text)?.clamp(3, 300),
      learningRate:
          double.tryParse(_lrCtrl.text)?.clamp(0.0001, 0.1).toDouble(),
      batchSize: int.tryParse(_batchCtrl.text)?.clamp(4, 256),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _parseError = null;
    });
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'csv', 'tsv', 'txt', 'json', 'xlsx', 'xls', 'sql', 'dump', 'pdf',
      ],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _parseError = 'Could not read the selected file.');
      return;
    }

    setState(() {
      _parsing = true;
      _dataset = null;
      _result = null;
      _previewForecasts = const [];
      _lastUpdate = null;
      _deployMessage = null;
    });
    // Let the spinner paint before heavy parsing starts.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    try {
      final parsed =
          await AlertRecordParser.parse(fileName: file.name, bytes: bytes);
      final rows = LstmFeatureEngineer.buildDailyRows(parsed.records);
      final scaler = FeatureScaler.fit(rows);
      final samples = LstmFeatureEngineer.buildWindows(rows, scaler, 14);
      setState(() {
        _dataset = parsed;
        _scaler = scaler;
        _samples = samples;
        _config = LstmTrainingConfig.auto(samples.length);
        _syncConfigFields();
        _parsing = false;
      });
    } catch (e) {
      setState(() {
        _parsing = false;
        _parseError = e is FormatException ? e.message : e.toString();
      });
    }
  }

  Future<void> _startTraining() async {
    if (_samples.isEmpty || _scaler == null || _training) return;
    final config = _configFromFields();
    setState(() {
      _config = config;
      _syncConfigFields();
      _training = true;
      _result = null;
      _previewForecasts = const [];
      _deployMessage = null;
    });
    unawaited(_store.writeTrainingStatus(
      status: 'running',
      progress: 0,
      message: 'Training started on ${_dataset?.summary.sourceName}',
    ));

    try {
      await for (final update in _trainer.train(
        samples: _samples,
        scaler: _scaler!,
        config: config,
      )) {
        if (!mounted) return;
        setState(() => _lastUpdate = update);
        if (update.phase == LstmTrainingPhase.training &&
            update.epochs.length % 5 == 0) {
          unawaited(_store.writeTrainingStatus(
            status: 'running',
            progress: update.progress,
            message: update.message,
            epochs: update.epochs,
          ));
        }
      }
      final result = _trainer.result;
      if (!mounted) return;
      setState(() {
        _training = false;
        _result = result;
        if (result != null && _dataset != null) {
          _previewForecasts = LstmForecastEngine.computeForecasts(
            TrainedLstmModel(
              network: result.network,
              scaler: result.scaler,
              seqLen: config.seqLen,
            ),
            _dataset!.records,
            now: _dataset!.summary.lastTimestamp,
          );
        }
      });
      unawaited(_store.writeTrainingStatus(
        status: _result == null ? 'failed' : 'done',
        progress: 1,
        message: _lastUpdate?.message ?? 'finished',
        epochs: _lastUpdate?.epochs ?? const [],
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _training = false;
        _parseError = 'Training failed: $e';
      });
      unawaited(_store.writeTrainingStatus(
        status: 'failed',
        progress: 0,
        message: '$e',
      ));
    }
  }

  Future<void> _deploy() async {
    final result = _result;
    if (result == null || _deploying) return;
    setState(() {
      _deploying = true;
      _deployMessage = null;
    });
    try {
      await _store.saveModel(
        network: result.network,
        scaler: result.scaler,
        seqLen: _config.seqLen,
        datasetName: _dataset?.summary.sourceName ?? 'dataset',
        sampleCount: result.sampleCount,
        valLoss: result.bestValLoss,
        valAccuracy: result.bestValAccuracy,
        learning: result.isLearning,
        epochs: result.epochs,
      );

      // Publish a live snapshot computed from production alerts so the rest
      // of the platform sees forecasts immediately.
      List<MachineForecast> live = _previewForecasts;
      try {
        final snap = await FirebaseDatabase.instance.ref('alerts').get();
        if (snap.value is Map) {
          final records = LstmForecastEngine.recordsFromAlertMaps(
              (snap.value as Map).values.whereType<Map>());
          if (records.isNotEmpty) {
            live = LstmForecastEngine.computeForecasts(
              TrainedLstmModel(
                network: result.network,
                scaler: result.scaler,
                seqLen: _config.seqLen,
              ),
              records,
            );
          }
        }
      } catch (_) {
        // fall back to dataset-based preview snapshot
      }
      await LstmForecastEngine.publishSnapshot(live);

      if (!mounted) return;
      setState(() {
        _deploying = false;
        _deployMessage =
            'Model deployed. ${live.length} machines forecast live on every '
            'Production Manager dashboard.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deploying = false;
        _deployMessage = 'Deploy failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDeployedModelPanel(),
              const SizedBox(height: 16),
              _buildUploadPanel(),
              if (_dataset != null) ...[
                const SizedBox(height: 16),
                _buildHyperparamsPanel(),
              ],
              if (_lastUpdate != null || _training) ...[
                const SizedBox(height: 16),
                _buildTrainingMonitor(),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                _buildForecastPreview(),
              ],
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ── Deployed model status ────────────────────────────────────────────────

  Widget _buildDeployedModelPanel() {
    final m = _deployedModel;
    return GlassPanel(
      accent: m == null ? Sa.amber : (m.learning ? Sa.green : Sa.amber),
      glow: m != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.hub_outlined,
            title: 'DEPLOYED FORECAST MODEL',
            subtitle: m == null
                ? 'No LSTM deployed yet — every dashboard is waiting for its first model.'
                : 'Serving live next-24h forecasts on all Production Manager dashboards.',
            accent: m == null ? Sa.amber : Sa.green,
            trailing: m == null
                ? const GlowChip(label: 'OFFLINE', color: Sa.amber, icon: Icons.cloud_off)
                : GlowChip(
                    label: m.learning ? 'LEARNING VERIFIED' : 'DEPLOYED',
                    color: m.learning ? Sa.green : Sa.cyan,
                    pulse: true,
                  ),
          ),
          if (m != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'val loss',
                  value: m.valLoss.toStringAsFixed(4),
                  icon: Icons.trending_down,
                  color: Sa.cyan,
                ),
                SaStatTile(
                  label: 'val accuracy',
                  value: '${(m.valAccuracy * 100).toStringAsFixed(1)}%',
                  icon: Icons.verified_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'hidden units',
                  value: '${m.network.hiddenSize}',
                  icon: Icons.grain,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'windows trained',
                  value: '${m.sampleCount}',
                  icon: Icons.view_timeline_outlined,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'trained',
                  value: _ago(m.trainedAt),
                  icon: Icons.history,
                  color: Sa.textDim,
                ),
                if (m.datasetName != null)
                  SaStatTile(
                    label: 'dataset',
                    value: m.datasetName!,
                    icon: Icons.dataset_outlined,
                    color: Sa.pink,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime? t) {
    if (t == null) return '—';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 48) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  // ── Upload ───────────────────────────────────────────────────────────────

  Widget _buildUploadPanel() {
    final summary = _dataset?.summary;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.upload_file_outlined,
            title: 'TRAINING DATA INTAKE',
            subtitle:
                'Feed the LSTM with your company\'s alert history. Any structured export works.',
            accent: Sa.violet,
            trailing: _dataset == null
                ? null
                : GlowChip(
                    label: '${summary!.parsedRows} ROWS LOADED',
                    color: Sa.green,
                    icon: Icons.check_circle_outline,
                  ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _parsing || _training ? null : _pickFile,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Sa.violet.withValues(alpha: 0.45),
                  width: 1.4,
                ),
                gradient: LinearGradient(
                  colors: [
                    Sa.violet.withValues(alpha: 0.06),
                    Sa.cyan.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Column(
                children: [
                  if (_parsing) ...[
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Sa.violet),
                    ),
                    const SizedBox(height: 12),
                    Text('Parsing and engineering features…',
                        style: Sa.body(color: Sa.textDim)),
                  ] else ...[
                    const Icon(Icons.cloud_upload_outlined,
                        size: 34, color: Sa.violet),
                    const SizedBox(height: 10),
                    Text(
                      _dataset == null
                          ? 'SELECT A DATA FILE'
                          : 'REPLACE DATASET',
                      style: Sa.heading(size: 14, color: Sa.text),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'CSV · Excel · JSON · MySQL dump (.sql) · PDF',
                      style: Sa.mono(size: 10.5, color: Sa.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_parseError != null) ...[
            const SizedBox(height: 12),
            _InlineNotice(color: Sa.red, icon: Icons.error_outline, text: _parseError!),
          ],
          if (_dataset != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'rows parsed',
                  value: '${summary!.parsedRows}',
                  icon: Icons.table_rows_outlined,
                  color: Sa.cyan,
                ),
                SaStatTile(
                  label: 'machines',
                  value: '${summary.machineCount}',
                  icon: Icons.precision_manufacturing_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'history span',
                  value: '${summary.daySpan} days',
                  icon: Icons.date_range_outlined,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'training windows',
                  value: '${_samples.length}',
                  icon: Icons.view_timeline_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'skipped rows',
                  value: '${summary.skippedRows}',
                  icon: Icons.filter_alt_off_outlined,
                  color: summary.skippedRows > 0 ? Sa.amber : Sa.muted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _TypeDistribution(typeCounts: summary.typeCounts, total: summary.parsedRows),
            for (final w in _dataset!.warnings) ...[
              const SizedBox(height: 10),
              _InlineNotice(color: Sa.amber, icon: Icons.warning_amber_outlined, text: w),
            ],
          ],
        ],
      ),
    );
  }

  // ── Hyperparameters ─────────────────────────────────────────────────────

  Widget _buildHyperparamsPanel() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.tune,
            title: 'HYPERPARAMETERS',
            subtitle:
                'Auto-tuned from the dataset shape (${_samples.length} windows). Adjust if you know what you\'re doing.',
            accent: Sa.cyan,
            trailing: TextButton.icon(
              onPressed: _training
                  ? null
                  : () => setState(() {
                        _config = LstmTrainingConfig.auto(_samples.length);
                        _syncConfigFields();
                      }),
              icon: const Icon(Icons.auto_fix_high, size: 15, color: Sa.violet),
              label: Text('AUTO-TUNE', style: Sa.mono(size: 10.5, color: Sa.violet)),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 760;
            final fields = [
              _paramField('HIDDEN UNITS', _hiddenCtrl, 'LSTM memory width'),
              _paramField('EPOCHS', _epochsCtrl, 'Full passes over the data'),
              _paramField('LEARNING RATE', _lrCtrl, 'Adam step size'),
              _paramField('BATCH SIZE', _batchCtrl, 'Windows per update'),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final f in fields)
                  SizedBox(width: narrow ? constraints.maxWidth : 280, child: f),
              ],
            );
          }),
          const SizedBox(height: 8),
          Text(
            'Fixed: sequence window 14 days · ${kLstmFeatureCols.length} features/day · '
            '4 sigmoid outputs (one per alert type) · weighted BCE loss · '
            'gradient clipping · early stopping (patience ${_config.patience}).',
            style: Sa.mono(size: 10, color: Sa.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SaButton(
                label: _training ? 'TRAINING…' : 'START TRAINING',
                icon: Icons.play_arrow_rounded,
                busy: _training,
                onPressed: _samples.isEmpty || _training ? null : _startTraining,
              ),
              const SizedBox(width: 12),
              if (_training)
                SaButton(
                  label: 'STOP',
                  icon: Icons.stop_rounded,
                  color: Sa.red,
                  outlined: true,
                  onPressed: () => _trainer.cancel(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paramField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Sa.mono(size: 10, color: Sa.textDim)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          enabled: !_training,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Sa.mono(size: 13, color: Sa.cyan),
          cursorColor: Sa.cyan,
          decoration: InputDecoration(
            helperText: hint,
            helperStyle: Sa.body(size: 10, color: Sa.muted),
            filled: true,
            fillColor: Sa.bgRaised.withValues(alpha: 0.7),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Sa.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Sa.cyan),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Sa.border.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Training monitor ────────────────────────────────────────────────────

  Widget _buildTrainingMonitor() {
    final update = _lastUpdate;
    final epochs = update?.epochs ?? const <EpochStat>[];
    final learning = update?.isLearning ?? false;
    final progress = update?.progress ?? 0;
    final running = _training;

    return GlassPanel(
      accent: learning ? Sa.green : Sa.cyan,
      glow: running,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.monitor_heart_outlined,
            title: 'TRAINING MONITOR',
            subtitle: update?.message ?? 'Waiting for first epoch…',
            accent: learning ? Sa.green : Sa.cyan,
            trailing: GlowChip(
              label: running
                  ? (learning ? 'LEARNING' : 'WARMING UP')
                  : (learning ? 'LEARNING VERIFIED' : 'NOT LEARNING'),
              color: learning ? Sa.green : (running ? Sa.amber : Sa.red),
              pulse: running,
            ),
          ),
          const SizedBox(height: 16),
          _GradientProgressBar(progress: progress, active: running),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                epochs.isEmpty
                    ? 'EPOCH 0'
                    : 'EPOCH ${epochs.last.epoch} / ${_config.epochs}',
                style: Sa.mono(size: 10.5, color: Sa.textDim),
              ),
              Text('${(progress * 100).toStringAsFixed(0)}%',
                  style: Sa.mono(size: 10.5, color: Sa.cyan)),
            ],
          ),
          if (epochs.isNotEmpty) ...[
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 860;
              final lossChart = _ChartCard(
                title: 'LOSS CURVES',
                legend: const [
                  (label: 'train', color: Sa.cyan),
                  (label: 'validation', color: Sa.violet),
                ],
                child: _lossChart(epochs),
              );
              final accChart = _ChartCard(
                title: 'VALIDATION ACCURACY / F1',
                legend: const [
                  (label: 'accuracy', color: Sa.green),
                  (label: 'macro-F1', color: Sa.amber),
                ],
                child: _accuracyChart(epochs),
              );
              if (narrow) {
                return Column(children: [
                  lossChart,
                  const SizedBox(height: 12),
                  accChart,
                ]);
              }
              return Row(children: [
                Expanded(child: lossChart),
                const SizedBox(width: 12),
                Expanded(child: accChart),
              ]);
            }),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'train loss',
                  value: epochs.last.trainLoss.toStringAsFixed(4),
                  icon: Icons.south_east,
                  color: Sa.cyan,
                ),
                SaStatTile(
                  label: 'val loss',
                  value: epochs.last.valLoss.toStringAsFixed(4),
                  icon: Icons.south_east,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'val accuracy',
                  value:
                      '${(epochs.last.valAccuracy * 100).toStringAsFixed(1)}%',
                  icon: Icons.verified_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'macro F1',
                  value: epochs.last.valF1.toStringAsFixed(3),
                  icon: Icons.balance,
                  color: Sa.amber,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _lossChart(List<EpochStat> epochs) {
    LineChartBarData line(List<FlSpot> spots, Color color) => LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 2,
          isCurved: true,
          curveSmoothness: 0.25,
          preventCurveOverShooting: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.16), Colors.transparent],
            ),
          ),
        );
    return LineChart(
      LineChartData(
        backgroundColor: Colors.transparent,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Sa.border, strokeWidth: 0.6),
        ),
        titlesData: _chartTitles(),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          line(
            [for (final e in epochs) FlSpot(e.epoch.toDouble(), e.trainLoss)],
            Sa.cyan,
          ),
          line(
            [for (final e in epochs) FlSpot(e.epoch.toDouble(), e.valLoss)],
            Sa.violet,
          ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  Widget _accuracyChart(List<EpochStat> epochs) {
    LineChartBarData line(List<FlSpot> spots, Color color) => LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 2,
          isCurved: true,
          curveSmoothness: 0.25,
          preventCurveOverShooting: true,
          dotData: const FlDotData(show: false),
        );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1,
        backgroundColor: Colors.transparent,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Sa.border, strokeWidth: 0.6),
        ),
        titlesData: _chartTitles(),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          line(
            [
              for (final e in epochs)
                FlSpot(e.epoch.toDouble(), e.valAccuracy)
            ],
            Sa.green,
          ),
          line(
            [for (final e in epochs) FlSpot(e.epoch.toDouble(), e.valF1)],
            Sa.amber,
          ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  FlTitlesData _chartTitles() => FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(v.toInt().toString(),
                  style: Sa.mono(size: 8.5, color: Sa.muted)),
            ),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            getTitlesWidget: (v, _) => Text(
              v.toStringAsFixed(2),
              style: Sa.mono(size: 8.5, color: Sa.muted),
            ),
          ),
        ),
      );

  // ── Forecast preview + deploy ───────────────────────────────────────────

  Widget _buildForecastPreview() {
    final result = _result!;
    final top = _previewForecasts.take(8).toList();
    return GlassPanel(
      accent: Sa.green,
      glow: result.isLearning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.online_prediction,
            title: 'FORECAST PREVIEW — NEXT 24H',
            subtitle:
                'Inference on the uploaded history with the freshly trained weights.',
            accent: Sa.green,
            trailing: GlowChip(
              label: result.isLearning ? 'READY TO DEPLOY' : 'WEAK MODEL',
              color: result.isLearning ? Sa.green : Sa.amber,
              icon: result.isLearning
                  ? Icons.rocket_launch_outlined
                  : Icons.warning_amber_outlined,
            ),
          ),
          const SizedBox(height: 14),
          if (top.isEmpty)
            Text('No machines with enough history to forecast.',
                style: Sa.body(color: Sa.textDim))
          else
            ...top.map((f) => _ForecastRow(forecast: f)),
          const SizedBox(height: 16),
          Row(
            children: [
              SaButton(
                label: _deploying ? 'DEPLOYING…' : 'DEPLOY TO PRODUCTION',
                icon: Icons.rocket_launch_outlined,
                color: Sa.green,
                busy: _deploying,
                onPressed: _deploying ? null : _deploy,
              ),
              const SizedBox(width: 14),
              if (_deployMessage != null)
                Expanded(
                  child: Text(
                    _deployMessage!,
                    style: Sa.body(
                      size: 12,
                      color: _deployMessage!.startsWith('Deploy failed')
                          ? Sa.red
                          : Sa.green,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small shared widgets ─────────────────────────────────────────────────

class _InlineNotice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _InlineNotice({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Sa.body(size: 12, color: color))),
        ],
      ),
    );
  }
}

class _TypeDistribution extends StatelessWidget {
  final Map<String, int> typeCounts;
  final int total;
  const _TypeDistribution({required this.typeCounts, required this.total});

  static const _colors = {
    'qualite': Sa.cyan,
    'maintenance': Sa.amber,
    'defaut_produit': Sa.red,
    'manque_ressource': Sa.violet,
  };

  @override
  Widget build(BuildContext context) {
    final entries = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TYPE DISTRIBUTION', style: Sa.mono(size: 10, color: Sa.textDim)),
        const SizedBox(height: 8),
        for (final e in entries.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Sa.mono(size: 10.5, color: Sa.text)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : e.value / total,
                      minHeight: 7,
                      backgroundColor: Sa.bgRaised,
                      color: _colors[e.key] ?? Sa.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  child: Text('${e.value}',
                      textAlign: TextAlign.right,
                      style: Sa.mono(size: 10.5, color: Sa.textDim)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GradientProgressBar extends StatelessWidget {
  final double progress;
  final bool active;
  const _GradientProgressBar({required this.progress, required this.active});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Stack(
        children: [
          Container(height: 10, color: Sa.bgRaised),
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Sa.cyan, Sa.violet, Sa.pink],
                ),
                boxShadow: active
                    ? [BoxShadow(color: Sa.cyan.withValues(alpha: 0.5), blurRadius: 10)]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<({String label, Color color})> legend;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.legend,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      Text(title, style: Sa.mono(size: 10, color: Sa.textDim))),
              for (final l in legend) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: l.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(l.label, style: Sa.mono(size: 9, color: Sa.muted)),
                const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 190, child: child),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  final MachineForecast forecast;
  const _ForecastRow({required this.forecast});

  static const _typeColors = {
    'qualite': Sa.cyan,
    'maintenance': Sa.amber,
    'defaut_produit': Sa.red,
    'manque_ressource': Sa.violet,
  };

  @override
  Widget build(BuildContext context) {
    final any = forecast.anyProbability;
    final riskColor = any >= 0.66
        ? Sa.red
        : any >= 0.33
            ? Sa.amber
            : Sa.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Column(
              children: [
                Text('${(any * 100).toStringAsFixed(0)}%',
                    style: Sa.mono(
                        size: 15, color: riskColor, weight: FontWeight.w700)),
                Text('RISK', style: Sa.mono(size: 7.5, color: Sa.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${forecast.usine} · Conveyor ${forecast.convoyeur} · Station ${forecast.poste}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 12.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final entry in forecast.typeProbabilities.entries)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message:
                                '${entry.key}: ${(entry.value * 100).toStringAsFixed(1)}%',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: entry.value,
                                minHeight: 5,
                                backgroundColor:
                                    Sa.border.withValues(alpha: 0.4),
                                color: _typeColors[entry.key] ?? Sa.blue,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GlowChip(
            label: forecast.topType.toUpperCase(),
            color: _typeColors[forecast.topType] ?? Sa.blue,
          ),
        ],
      ),
    );
  }
}

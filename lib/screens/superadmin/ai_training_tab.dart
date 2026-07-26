import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/alert_type_registry.dart';
import '../../services/forecast/forecast_model_store.dart';
import '../../services/forecast/forecast_training_controller.dart';
import '../../services/forecast/forecast_types.dart';
import '../../l10n/app_strings.dart';
import 'superadmin_theme.dart';

/// SuperAdmin tab 1: upload historical alert data in any common format,
/// train the on-device gradient-boosting forecaster with live learning
/// curves, verify it is actually learning, then deploy the model for every
/// Production Manager dashboard. Once deployed, the model grades its own
/// forecasts against reality and keeps adapting on fresh production data.
///
/// This widget is a *view* over [ForecastTrainingController]: the run itself
/// lives app-globally, so switching tabs, navigating away or signing out
/// never interrupts learning, and closed-tab runs resume from their
/// checkpoint.
class AiTrainingTab extends StatefulWidget {
  const AiTrainingTab({super.key});

  @override
  State<AiTrainingTab> createState() => _AiTrainingTabState();
}

class _AiTrainingTabState extends State<AiTrainingTab> {
  final _store = ForecastModelStore();
  final _controller = ForecastTrainingController.instance;

  // Deployed model + self-evaluation ledger (live from RTDB).
  StreamSubscription<TrainedForecastModel?>? _modelSub;
  TrainedForecastModel? _deployedModel;
  StreamSubscription<ForecastAccuracy?>? _accuracySub;
  ForecastAccuracy? _accuracy;

  // Hyperparameter editors (view-local; the run config lives in the
  // controller).
  final _roundsCtrl = TextEditingController();
  final _lrCtrl = TextEditingController();
  final _depthCtrl = TextEditingController();
  final _leafCtrl = TextEditingController();
  final _subsampleCtrl = TextEditingController();
  final _l2Ctrl = TextEditingController();
  final _posWeightCapCtrl = TextEditingController();
  ForecastTrainingConfig? _syncedConfig;

  @override
  void initState() {
    super.initState();
    _modelSub = _store.modelStream().listen((m) {
      if (mounted) setState(() => _deployedModel = m);
    }, onError: (_) {});
    _accuracySub = _store.accuracyStream().listen((a) {
      if (mounted) setState(() => _accuracy = a);
    }, onError: (_) {});
    _controller.addListener(_onControllerChanged);
    _syncConfigFields();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _modelSub?.cancel();
    _accuracySub?.cancel();
    _roundsCtrl.dispose();
    _lrCtrl.dispose();
    _depthCtrl.dispose();
    _leafCtrl.dispose();
    _subsampleCtrl.dispose();
    _l2Ctrl.dispose();
    _posWeightCapCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (!identical(_controller.config, _syncedConfig)) _syncConfigFields();
    setState(() {});
  }

  void _syncConfigFields() {
    final config = _controller.config;
    _syncedConfig = config;
    _roundsCtrl.text = '${config.rounds}';
    _lrCtrl.text = '${config.learningRate}';
    _depthCtrl.text = '${config.maxDepth}';
    _leafCtrl.text = '${config.minSamplesLeaf}';
    _subsampleCtrl.text = '${config.subsample}';
    _l2Ctrl.text = '${config.l2}';
    _posWeightCapCtrl.text = '${config.posWeightCap}';
  }

  ForecastTrainingConfig _configFromFields() {
    return _controller.config.copyWith(
      rounds: int.tryParse(_roundsCtrl.text)?.clamp(10, 800),
      learningRate: double.tryParse(_lrCtrl.text)?.clamp(0.005, 0.5).toDouble(),
      maxDepth: int.tryParse(_depthCtrl.text)?.clamp(2, 8),
      minSamplesLeaf: int.tryParse(_leafCtrl.text)?.clamp(2, 200),
      subsample: double.tryParse(
        _subsampleCtrl.text,
      )?.clamp(0.3, 1.0).toDouble(),
      l2: double.tryParse(_l2Ctrl.text)?.clamp(0.0, 50.0).toDouble(),
      posWeightCap: double.tryParse(
        _posWeightCapCtrl.text,
      )?.clamp(1.0, 200.0).toDouble(),
    );
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'csv',
        'tsv',
        'txt',
        'json',
        'xlsx',
        'xls',
        'sql',
        'dump',
        'pdf',
      ],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) return;
    await _controller.loadDataset(fileName: file.name, bytes: bytes);
  }

  @override
  Widget build(BuildContext context) {
    // This tab is also embedded in entitled Production Manager dashboards.
    Sa.setDark(Theme.of(context).brightness == Brightness.dark);
    final c = _controller;
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
              if (c.dataset != null) ...[
                const SizedBox(height: 16),
                _buildHyperparamsPanel(),
              ],
              if (c.lastUpdate != null || c.training || c.remoteActive) ...[
                const SizedBox(height: 16),
                _buildTrainingMonitor(),
              ],
              if (c.result != null) ...[
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
    final acc = _accuracy;
    return GlassPanel(
      accent: m == null ? Sa.amber : (m.learning ? Sa.green : Sa.amber),
      glow: m != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.hub_outlined,
            title: context.tr('DEPLOYED FORECAST MODEL'),
            subtitle: m == null
                ? context.tr(
                    'No model deployed yet — every dashboard is waiting for its first model.',
                  )
                : context.tr(
                    'Gradient-boosted trees serving live next-24h forecasts on all Production Manager dashboards.',
                  ),
            accent: m == null ? Sa.amber : Sa.green,
            trailing: m == null
                ? GlowChip(
                    label: context.tr('OFFLINE'),
                    color: Sa.amber,
                    icon: Icons.cloud_off,
                  )
                : GlowChip(
                    label: m.learning
                        ? context.tr('LEARNING VERIFIED')
                        : context.tr('DEPLOYED'),
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
                  label: context.tr('val loss'),
                  value: m.valLoss.toStringAsFixed(4),
                  icon: Icons.trending_down,
                  color: Sa.cyan,
                ),
                SaStatTile(
                  label: context.tr('val accuracy'),
                  value: '${(m.valAccuracy * 100).toStringAsFixed(1)}%',
                  icon: Icons.verified_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: context.tr('trees'),
                  value: '${m.model.treeCount}',
                  icon: Icons.park_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: context.tr('samples trained'),
                  value: '${m.sampleCount}',
                  icon: Icons.view_timeline_outlined,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: context.tr('trained'),
                  value: _ago(context, m.trainedAt),
                  icon: Icons.history,
                  color: Sa.textDim,
                ),
                if (m.datasetName != null)
                  SaStatTile(
                    label: context.tr('dataset'),
                    value: m.datasetName!,
                    icon: Icons.dataset_outlined,
                    color: Sa.pink,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _buildContinuousLearningStrip(m, acc),
          ],
        ],
      ),
    );
  }

  /// Self-evaluation + adaptation status: the model grades yesterday's
  /// forecasts against what actually happened and keeps boosting new trees
  /// on fresh production data.
  Widget _buildContinuousLearningStrip(
    TrainedForecastModel m,
    ForecastAccuracy? acc,
  ) {
    final graded = acc != null && acc.gradedPairs > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Sa.cyan.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.all_inclusive, size: 16, color: Sa.cyan),
              const SizedBox(width: 8),
              Text(
                context.tr('CONTINUOUS LEARNING'),
                style: Sa.heading(size: 12.5, color: Sa.cyan),
              ),
              const Spacer(),
              GlowChip(
                label: m.model.adaptedRounds > 0
                    ? context.tr('ADAPTED +{rounds} ROUNDS', {
                        'rounds': '${m.model.adaptedRounds}',
                      })
                    : context.tr('ARMED'),
                color: m.model.adaptedRounds > 0 ? Sa.green : Sa.cyan,
                icon: Icons.autorenew,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SaStatTile(
                label: context.tr('forecasts graded'),
                value: graded ? '${acc.gradedPairs}' : '—',
                icon: Icons.fact_check_outlined,
                color: Sa.blue,
              ),
              SaStatTile(
                label: context.tr('live precision'),
                value: graded
                    ? '${(acc.precision * 100).toStringAsFixed(0)}%'
                    : '—',
                icon: Icons.gps_fixed,
                color: Sa.green,
              ),
              SaStatTile(
                label: context.tr('live recall'),
                value:
                    graded ? '${(acc.recall * 100).toStringAsFixed(0)}%' : '—',
                icon: Icons.radar,
                color: Sa.violet,
              ),
              SaStatTile(
                label: context.tr('brier score'),
                value: graded ? acc.brierMean.toStringAsFixed(3) : '—',
                icon: Icons.straighten,
                color: Sa.amber,
              ),
              SaStatTile(
                label: context.tr('last adapted'),
                value: m.lastAdaptedAt == null
                    ? context.tr('not yet')
                    : _ago(context, m.lastAdaptedAt),
                icon: Icons.autorenew,
                color: Sa.textDim,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Every deployed forecast is graded against the alerts that actually happened (hit rate + Brier calibration), and the ensemble boosts a few extra trees per day on fresh production data — no manual retraining needed until you want a full reset.',
            ),
            style: Sa.body(size: 11, color: Sa.textDim),
          ),
        ],
      ),
    );
  }

  static String _ago(BuildContext context, DateTime? t) {
    if (t == null) return '—';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 60) {
      return context.tr('{n}m ago', {'n': '${d.inMinutes}'});
    }
    if (d.inHours < 48) {
      return context.tr('{n}h ago', {'n': '${d.inHours}'});
    }
    return context.tr('{n}d ago', {'n': '${d.inDays}'});
  }

  // ── Upload ───────────────────────────────────────────────────────────────

  Widget _buildUploadPanel() {
    final c = _controller;
    final summary = c.dataset?.summary;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.upload_file_outlined,
            title: context.tr('TRAINING DATA INTAKE'),
            subtitle: context.tr(
              'Dump your company\'s alert history in any structured export — the model handles the rest.',
            ),
            accent: Sa.violet,
            trailing: c.dataset == null
                ? null
                : GlowChip(
                    label: context.tr('{count} ROWS LOADED', {
                      'count': '${summary!.parsedRows}',
                    }),
                    color: Sa.green,
                    icon: Icons.check_circle_outline,
                  ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: c.parsing || c.training ? null : _pickFile,
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
                  if (c.parsing || c.restoring) ...[
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Sa.violet,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      c.restoring
                          ? context.tr('Restoring previous session…')
                          : context.tr('Parsing and engineering features…'),
                      style: Sa.body(color: Sa.textDim),
                    ),
                  ] else ...[
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 34,
                      color: Sa.violet,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      c.dataset == null
                          ? context.tr('SELECT A DATA FILE')
                          : context.tr('REPLACE DATASET'),
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
          if (c.error != null) ...[
            const SizedBox(height: 12),
            _InlineNotice(
              color: Sa.red,
              icon: Icons.error_outline,
              text: c.error!,
            ),
          ],
          if (c.dataset != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: context.tr('rows parsed'),
                  value: '${summary!.parsedRows}',
                  icon: Icons.table_rows_outlined,
                  color: Sa.cyan,
                ),
                SaStatTile(
                  label: context.tr('machines'),
                  value: '${summary.machineCount}',
                  icon: Icons.precision_manufacturing_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: context.tr('history span'),
                  value: context.tr('{days} days', {
                    'days': '${summary.daySpan}',
                  }),
                  icon: Icons.date_range_outlined,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: context.tr('training samples'),
                  value: '${c.samples.length}',
                  icon: Icons.view_timeline_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: context.tr('skipped rows'),
                  value: '${summary.skippedRows}',
                  icon: Icons.filter_alt_off_outlined,
                  color: summary.skippedRows > 0 ? Sa.amber : Sa.muted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _TypeDistribution(
              typeCounts: summary.typeCounts,
              total: summary.parsedRows,
            ),
            for (final w in c.dataset!.warnings) ...[
              const SizedBox(height: 10),
              _InlineNotice(
                color: Sa.amber,
                icon: Icons.warning_amber_outlined,
                text: w,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Hyperparameters ─────────────────────────────────────────────────────

  Widget _buildHyperparamsPanel() {
    final c = _controller;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.tune,
            title: context.tr('HYPERPARAMETERS'),
            subtitle: context.tr(
              'Auto-tuned from the dataset shape ({count} samples). Adjust if you know what you\'re doing.',
              {'count': '${c.samples.length}'},
            ),
            accent: Sa.cyan,
            trailing: TextButton.icon(
              onPressed: c.training
                  ? null
                  : () {
                      c.setConfig(
                        ForecastTrainingConfig.auto(c.samples.length),
                      );
                    },
              icon: Icon(Icons.auto_fix_high, size: 15, color: Sa.violet),
              label: Text(
                context.tr('AUTO-TUNE'),
                style: Sa.mono(size: 10.5, color: Sa.violet),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              final fields = [
                _paramField(
                  context.tr('BOOSTING ROUNDS'),
                  _roundsCtrl,
                  context.tr('Trees grown per alert type'),
                ),
                _paramField(
                  context.tr('LEARNING RATE'),
                  _lrCtrl,
                  context.tr('Shrinkage per tree'),
                ),
                _paramField(
                  context.tr('MAX TREE DEPTH'),
                  _depthCtrl,
                  context.tr('Interaction depth per tree'),
                ),
                _paramField(
                  context.tr('MIN LEAF SAMPLES'),
                  _leafCtrl,
                  context.tr('Smallest allowed leaf'),
                ),
                _paramField(
                  context.tr('SUBSAMPLE'),
                  _subsampleCtrl,
                  context.tr('Row fraction per tree (0.3–1)'),
                ),
                _paramField(
                  context.tr('L2 REGULARIZATION'),
                  _l2Ctrl,
                  context.tr('Leaf-weight damping (λ)'),
                ),
                _paramField(
                  context.tr('POS-CLASS WEIGHT CAP'),
                  _posWeightCapCtrl,
                  context.tr('Max miss-vs-false-alarm penalty ratio (1–200)'),
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final f in fields)
                    SizedBox(
                      width: narrow ? constraints.maxWidth : 280,
                      child: f,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Engine: XGBoost-class gradient-boosted decision trees · {features} engineered features (lags, rolling counts, recency, calendar) · {ensembles} ensembles (one per alert type) · second-order logistic boosting · histogram splits · class-imbalance weighting · early stopping (patience {patience}).',
              {
                'features':
                    '${forecastFeatureCountFor(AlertTypeRegistry.instance.codes.length)}',
                'ensembles': '${AlertTypeRegistry.instance.codes.length}',
                'patience': '${c.config.patience}',
              },
            ),
            style: Sa.mono(size: 10, color: Sa.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SaButton(
                label: c.training
                    ? context.tr('TRAINING…')
                    : context.tr('START TRAINING'),
                icon: Icons.play_arrow_rounded,
                busy: c.training,
                onPressed: c.samples.isEmpty || c.runActive
                    ? null
                    : () => c.startTraining(_configFromFields()),
              ),
              const SizedBox(width: 12),
              if (c.training)
                SaButton(
                  label: context.tr('STOP'),
                  icon: Icons.stop_rounded,
                  color: Sa.red,
                  outlined: true,
                  onPressed: c.cancelTraining,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _InlineNotice(
            color: Sa.cyan,
            icon: Icons.all_inclusive,
            text: context.tr(
              'Training is autonomous: it keeps running if you switch tabs, work elsewhere in the console, or sign out while the app stays open. If this tab or browser is closed mid-run, the checkpoint resumes automatically the next time the command center opens.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramField(String label, TextEditingController ctrl, String hint) {
    final training = _controller.training;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Sa.mono(size: 10, color: Sa.textDim)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          enabled: !training,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Sa.mono(size: 13, color: Sa.cyan),
          cursorColor: Sa.cyan,
          decoration: InputDecoration(
            helperText: hint,
            helperStyle: Sa.body(size: 10, color: Sa.muted),
            filled: true,
            fillColor: Sa.bgRaised.withValues(alpha: 0.7),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Sa.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Sa.cyan),
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
    final c = _controller;
    final update = c.lastUpdate;
    final rounds = update?.rounds ?? const <RoundStat>[];
    final learning = update?.isLearning ?? false;
    final progress = update?.progress ?? 0;
    final running = c.training || c.remoteActive;

    return GlassPanel(
      accent: learning ? Sa.green : Sa.cyan,
      glow: running,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.monitor_heart_outlined,
            title: context.tr('TRAINING MONITOR'),
            subtitle: update?.message ?? context.tr('Waiting for first round…'),
            accent: learning ? Sa.green : Sa.cyan,
            trailing: Wrap(
              spacing: 6,
              children: [
                if (c.remoteActive)
                  GlowChip(
                    label: context.tr('LIVE · ANOTHER SESSION'),
                    color: Sa.blue,
                    pulse: true,
                  )
                else if (c.resumedRun)
                  GlowChip(
                    label: context.tr('RESUMED FROM CHECKPOINT'),
                    color: Sa.violet,
                    icon: Icons.restore,
                  ),
                GlowChip(
                  label: running
                      ? (learning
                          ? context.tr('LEARNING')
                          : context.tr('WARMING UP'))
                      : (learning
                          ? context.tr('LEARNING VERIFIED')
                          : context.tr('NOT LEARNING')),
                  color: learning ? Sa.green : (running ? Sa.amber : Sa.red),
                  pulse: running,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _GradientProgressBar(progress: progress, active: running),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                rounds.isEmpty
                    ? context.tr('ROUND 0')
                    : context.tr('ROUND {round} / {total}', {
                        'round': '${rounds.last.round}',
                        'total': '${c.config.rounds}',
                      }),
                style: Sa.mono(size: 10.5, color: Sa.textDim),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: Sa.mono(size: 10.5, color: Sa.cyan),
              ),
            ],
          ),
          if (rounds.isNotEmpty) ...[
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 860;
                final lossChart = _ChartCard(
                  title: context.tr('LOSS CURVES'),
                  legend: [
                    (label: context.tr('train'), color: Sa.cyan),
                    (label: context.tr('validation'), color: Sa.violet),
                  ],
                  child: _lossChart(rounds),
                );
                final accChart = _ChartCard(
                  title: context.tr('VALIDATION ACCURACY / F1'),
                  legend: [
                    (label: context.tr('accuracy'), color: Sa.green),
                    (label: context.tr('macro-F1'), color: Sa.amber),
                  ],
                  child: _accuracyChart(rounds),
                );
                if (narrow) {
                  return Column(
                    children: [lossChart, const SizedBox(height: 12), accChart],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: lossChart),
                    const SizedBox(width: 12),
                    Expanded(child: accChart),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: context.tr('train loss'),
                  value: rounds.last.trainLoss.toStringAsFixed(4),
                  icon: Icons.south_east,
                  color: Sa.cyan,
                ),
                SaStatTile(
                  label: context.tr('val loss'),
                  value: rounds.last.valLoss.toStringAsFixed(4),
                  icon: Icons.south_east,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: context.tr('val accuracy'),
                  value:
                      '${(rounds.last.valAccuracy * 100).toStringAsFixed(1)}%',
                  icon: Icons.verified_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: context.tr('macro F1'),
                  value: rounds.last.valF1.toStringAsFixed(3),
                  icon: Icons.balance,
                  color: Sa.amber,
                ),
              ],
            ),
          ],
          if (!running &&
              c.result != null &&
              !c.result!.isLearning &&
              c.diagnostics.isNotEmpty) ...[
            const SizedBox(height: 16),
            _DiagnosisPanel(reasons: c.diagnostics),
          ],
        ],
      ),
    );
  }

  Widget _lossChart(List<RoundStat> rounds) {
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
              FlLine(color: Sa.border, strokeWidth: 0.6),
        ),
        titlesData: _chartTitles(),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          line([
            for (final e in rounds) FlSpot(e.round.toDouble(), e.trainLoss),
          ], Sa.cyan),
          line([
            for (final e in rounds) FlSpot(e.round.toDouble(), e.valLoss),
          ], Sa.violet),
        ],
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  Widget _accuracyChart(List<RoundStat> rounds) {
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
              FlLine(color: Sa.border, strokeWidth: 0.6),
        ),
        titlesData: _chartTitles(),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          line([
            for (final e in rounds) FlSpot(e.round.toDouble(), e.valAccuracy),
          ], Sa.green),
          line([
            for (final e in rounds) FlSpot(e.round.toDouble(), e.valF1),
          ], Sa.amber),
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
              child: Text(
                v.toInt().toString(),
                style: Sa.mono(size: 8.5, color: Sa.muted),
              ),
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
    final c = _controller;
    final result = c.result!;
    final top = c.previewForecasts.take(8).toList();
    return GlassPanel(
      accent: Sa.green,
      glow: result.isLearning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.online_prediction,
            title: context.tr('FORECAST PREVIEW — NEXT 24H'),
            subtitle: context.tr(
              'Inference on the uploaded history with the freshly trained ensemble.',
            ),
            accent: Sa.green,
            trailing: GlowChip(
              label: result.isLearning
                  ? context.tr('READY TO DEPLOY')
                  : context.tr('WEAK MODEL'),
              color: result.isLearning ? Sa.green : Sa.amber,
              icon: result.isLearning
                  ? Icons.rocket_launch_outlined
                  : Icons.warning_amber_outlined,
            ),
          ),
          const SizedBox(height: 14),
          if (top.isEmpty)
            Text(
              context.tr('No machines with enough history to forecast.'),
              style: Sa.body(color: Sa.textDim),
            )
          else
            ...top.map((f) => _ForecastRow(forecast: f)),
          const SizedBox(height: 16),
          Row(
            children: [
              SaButton(
                label: c.deploying
                    ? context.tr('DEPLOYING…')
                    : context.tr('DEPLOY TO PRODUCTION'),
                icon: Icons.rocket_launch_outlined,
                color: Sa.green,
                busy: c.deploying,
                onPressed: c.deploying ? null : c.deploy,
              ),
              const SizedBox(width: 14),
              if (c.deployMessage != null)
                Expanded(
                  child: Text(
                    c.deployMessage!,
                    style: Sa.body(
                      size: 12,
                      color: c.deployMessage!.startsWith('Deploy failed')
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

/// Post-run analysis shown when the verdict is NOT LEARNING: what the data
/// and loss trajectory show, and what to change before retraining.
class _DiagnosisPanel extends StatelessWidget {
  final List<String> reasons;
  const _DiagnosisPanel({required this.reasons});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Sa.amber.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.troubleshoot_outlined, size: 16, color: Sa.amber),
              const SizedBox(width: 8),
              Text(
                context.tr("WHY THE MODEL DIDN'T LEARN"),
                style: Sa.heading(size: 13, color: Sa.amber),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Sa.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(r, style: Sa.body(size: 12, color: Sa.text)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Text(
            context.tr(
              'Fix the points above, replace or extend the dataset, and retrain. A model that is not learning is not blocked from deployment, but its forecasts will be close to guesswork.',
            ),
            style: Sa.body(size: 11, color: Sa.textDim),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _InlineNotice({
    required this.color,
    required this.icon,
    required this.text,
  });

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
          Expanded(
            child: Text(text, style: Sa.body(size: 12, color: color)),
          ),
        ],
      ),
    );
  }
}

class _TypeDistribution extends StatelessWidget {
  final Map<String, int> typeCounts;
  final int total;
  const _TypeDistribution({required this.typeCounts, required this.total});

  static Map<String, Color> get _colors => {
        'qualite': Sa.cyan,
        'maintenance': Sa.amber,
        'defaut_produit': Sa.red,
        'manque_ressource': Sa.violet,
      };

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final entries = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('TYPE DISTRIBUTION'),
          style: Sa.mono(size: 10, color: Sa.textDim),
        ),
        const SizedBox(height: 8),
        for (final e in entries.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    e.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.mono(size: 10.5, color: Sa.text),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : e.value / total,
                      minHeight: 7,
                      backgroundColor: Sa.bgRaised,
                      color: colors[e.key] ?? Sa.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${e.value}',
                    textAlign: TextAlign.right,
                    style: Sa.mono(size: 10.5, color: Sa.textDim),
                  ),
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
                gradient: LinearGradient(colors: [Sa.cyan, Sa.violet, Sa.pink]),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Sa.cyan.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ]
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
        color: Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.55 : 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: Sa.mono(size: 10, color: Sa.textDim)),
              ),
              for (final l in legend) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: l.color,
                    shape: BoxShape.circle,
                  ),
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

  static Map<String, Color> get _typeColors => {
        'qualite': Sa.cyan,
        'maintenance': Sa.amber,
        'defaut_produit': Sa.red,
        'manque_ressource': Sa.violet,
      };

  @override
  Widget build(BuildContext context) {
    final typeColors = _typeColors;
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
        color: Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.5 : 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Column(
              children: [
                Text(
                  '${(any * 100).toStringAsFixed(0)}%',
                  style: Sa.mono(
                    size: 15,
                    color: riskColor,
                    weight: FontWeight.w700,
                  ),
                ),
                Text(
                  context.tr('RISK'),
                  style: Sa.mono(size: 7.5, color: Sa.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context
                      .tr('{usine} · Conveyor {convoyeur} · Station {poste}', {
                    'usine': forecast.usine,
                    'convoyeur': '${forecast.convoyeur}',
                    'poste': '${forecast.poste}',
                  }),
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
                                backgroundColor: Sa.border.withValues(
                                  alpha: 0.4,
                                ),
                                color: typeColors[entry.key] ?? Sa.blue,
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
            color: typeColors[forecast.topType] ?? Sa.blue,
          ),
        ],
      ),
    );
  }
}

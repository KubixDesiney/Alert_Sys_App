// Security Sentinel + Predictive Core panels: defense grid toggles, threat
// mix, model identity, accuracy gauges, Brier trend, predictive brain.
//
// This is a part file of ai_agents_tab.dart (one library, split for
// maintainability); private identifiers are shared across all parts.
part of 'ai_agents_tab.dart';

class _SecurityAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _SecurityAgentPanel({
    required this.spec,
    required this.enabled,
    required this.health,
  });

  @override
  State<_SecurityAgentPanel> createState() => _SecurityAgentPanelState();
}

class _SecurityAgentPanelState extends State<_SecurityAgentPanel> {
  StreamSubscription<DatabaseEvent>? _actionsSub;
  StreamSubscription<DatabaseEvent>? _settingsSub;
  List<Map<String, dynamic>> _actions = const [];
  Map<String, dynamic> _settings = const {};
  String? _error;

  static const _defenses = [
    (
      key: 'promptInjection',
      title: 'Prompt-injection shield',
      desc:
          'Scans every user text field for 12 attack signatures before it can reach Llama.',
      icon: Icons.shield_outlined,
    ),
    (
      key: 'rateLimiting',
      title: 'Rate limiting',
      desc:
          'Per-fingerprint sliding-window budgets on every endpoint (DDoS / quota-burn protection).',
      icon: Icons.speed_outlined,
    ),
    (
      key: 'sanitization',
      title: 'Input sanitization',
      desc:
          'Strips control characters and clamps text length so payloads cannot break prompt framing.',
      icon: Icons.cleaning_services_outlined,
    ),
    (
      key: 'anomalyScan',
      title: 'Anomaly scan',
      desc:
          'Every 30 min: alert floods, malformed records, notification backlogs, auth-failure surges.',
      icon: Icons.radar_outlined,
    ),
    (
      key: 'siemExport',
      title: 'SIEM export',
      desc: 'Ships security events to the external Elastic SOC pipeline.',
      icon: Icons.outbox_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _actionsSub = FirebaseDatabase.instance
        .ref('security/actions')
        .limitToLast(50)
        .onValue
        .listen(
          (event) {
            if (mounted) {
              setState(
                () => _actions = _mapToSortedList(event.snapshot.value, 'at'),
              );
            }
          },
          onError: (e) {
            if (mounted) setState(() => _error = '$e');
          },
        );
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/security/settings')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _settings = v is Map
                  ? Map<String, dynamic>.from(v)
                  : const {},
            );
          }
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _actionsSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  bool _defenseOn(String key) => _settings[key] != false;

  Future<void> _setDefense(String key, bool value) async {
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/security/settings/$key')
          .set(value);
      if (!value && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr(
                'Defense disabled. The edge worker drops this shield within 60s — re-arm it when done testing.',
              ),
              style: Sa.body(size: 12.5, color: Sa.amber),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              context.tr('Update failed: {error}', {'error': '$e'}),
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
      }
    }
  }

  Color _kindColor(String kind) {
    if (kind.contains('injection')) return Sa.red;
    if (kind.contains('rate')) return Sa.amber;
    if (kind.contains('flood') || kind.contains('backlog')) return Sa.violet;
    if (kind.contains('auth')) return Sa.pink;
    return Sa.blue;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final dayAgo = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final recent = _actions.where((a) {
      final t = DateTime.tryParse((a['at'] ?? '').toString());
      return t != null && t.toUtc().isAfter(dayAgo);
    }).toList();
    final byKind = <String, int>{};
    for (final a in recent) {
      final k = (a['kind'] ?? 'other').toString();
      byKind[k] = (byKind[k] ?? 0) + 1;
    }
    final maxKind = byKind.values.isEmpty ? 0 : byKind.values.reduce(math.max);
    final armed = _defenses.where((d) => _defenseOn(d.key)).length;

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        GlassPanel(
          accent: spec.accent,
          glow: widget.enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: spec.icon,
                title: context.tr('THREAT CONSOLE'),
                subtitle: context.tr(
                  'Standing guard on every worker endpoint. Blocks are logged with the exact signature that fired.',
                ),
                accent: spec.accent,
                trailing: GlowChip(
                  label: context.tr('{armed}/{total} DEFENSES ARMED', {
                    'armed': '$armed',
                    'total': '${_defenses.length}',
                  }),
                  color: armed == _defenses.length ? Sa.green : Sa.amber,
                  pulse: true,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Blocks · 24h'),
                    value: '${recent.length}',
                    icon: Icons.block_outlined,
                    color: spec.accent,
                  ),
                  SaStatTile(
                    label: context.tr('Actions · last cron'),
                    value:
                        '${(widget.health?['securityActions'] as num?)?.toInt() ?? 0}',
                    icon: Icons.gpp_maybe_outlined,
                    color: Sa.amber,
                  ),
                  SaStatTile(
                    label: context.tr('Attack signatures'),
                    value: '12',
                    icon: Icons.fingerprint,
                    color: Sa.violet,
                  ),
                  SaStatTile(
                    label: context.tr('Last block'),
                    value: _actions.isEmpty
                        ? '—'
                        : _agoIso(context, _actions.first['at']),
                    icon: Icons.schedule,
                    color: Sa.blue,
                  ),
                ],
              ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.tune,
                title: context.tr('DEFENSE GRID'),
                subtitle: context.tr(
                  'Arm or stand down individual shields. Changes reach the edge worker within 60 seconds.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 12),
              for (final d in _defenses)
                _SettingTile(
                  title: context.tr(d.title),
                  description: context.tr(d.desc),
                  icon: d.icon,
                  accent: spec.accent,
                  value: _defenseOn(d.key),
                  onChanged: (v) => _setDefense(d.key, v),
                ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.stacked_bar_chart,
                title: context.tr('THREAT MIX · 24H'),
                subtitle: context.tr('What the sentinel has been deflecting.'),
                accent: spec.accent,
              ),
              const SizedBox(height: 14),
              if (byKind.isEmpty)
                Text(
                  context.tr('Clean skies — no blocks in the last 24 hours.'),
                  style: Sa.body(size: 12, color: Sa.textDim),
                )
              else
                ...byKind.entries.map(
                  (e) => _KindBar(
                    label: e.key,
                    count: e.value,
                    max: maxKind,
                    color: _kindColor(e.key),
                  ),
                ),
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.receipt_long_outlined,
                title: context.tr('ENFORCEMENT LOG'),
                subtitle: context.tr(
                  'Every block with endpoint, fingerprint and matched patterns. Tap for the full record.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 12),
              if (_error != null)
                SaEmptyState(
                  icon: Icons.lock_outline,
                  title: context.tr('Cannot read security actions'),
                  message: _error!,
                  accent: Sa.red,
                )
              else if (_actions.isEmpty)
                SaEmptyState(
                  icon: Icons.verified_user_outlined,
                  title: context.tr('No enforcement actions'),
                  message: context.tr(
                    'The sentinel has not needed to block anything yet.',
                  ),
                  accent: Sa.green,
                )
              else
                ..._actions.take(30).map((a) {
                  final kind = (a['kind'] ?? 'action').toString();
                  final fp = (a['fingerprint'] ?? '').toString();
                  return _LogTile(
                    kind: kind,
                    color: _kindColor(kind),
                    title:
                        '${a['endpoint'] ?? '—'} · ${fp.length > 10 ? fp.substring(fp.length - 10) : fp}',
                    at: (a['at'] ?? '').toString(),
                    details: a,
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-05 · PREDICTIVE CORE
// ═══════════════════════════════════════════════════════════════════════════

class _PredictiveAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  const _PredictiveAgentPanel({required this.spec, required this.enabled});

  @override
  State<_PredictiveAgentPanel> createState() => _PredictiveAgentPanelState();
}

class _PredictiveAgentPanelState extends State<_PredictiveAgentPanel> {
  StreamSubscription<DatabaseEvent>? _accSub;
  StreamSubscription<DatabaseEvent>? _histSub;
  StreamSubscription<DatabaseEvent>? _versionSub;
  StreamSubscription<DatabaseEvent>? _forecastSub;
  StreamSubscription<DatabaseEvent>? _settingsSub;

  Map<String, dynamic>? _accuracy;
  List<Map<String, dynamic>> _gradeHistory = const [];
  Map<String, dynamic> _modelMeta = const {};
  Map<String, dynamic>? _liveForecast;
  Map<String, dynamic> _settings = const {};
  int _view = 0; // 0 = model core, 1 = brain

  @override
  void initState() {
    super.initState();
    _accSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/latest')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _accuracy = v is Map ? Map<String, dynamic>.from(v) : null,
            );
          }
        }, onError: (_) {});
    _histSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/history')
        .limitToLast(30)
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          final list = <Map<String, dynamic>>[];
          if (v is Map) {
            v.forEach((k, val) {
              if (val is Map) {
                final m = Map<String, dynamic>.from(val);
                m['day'] = k.toString();
                list.add(m);
              }
            });
            list.sort(
              (a, b) => (a['day'] ?? '').toString().compareTo(
                (b['day'] ?? '').toString(),
              ),
            );
          }
          if (mounted) setState(() => _gradeHistory = list);
        }, onError: (_) {});
    // Watch the version only; re-fetch the light metadata children when it
    // bumps (the weights blob never enters this screen).
    _versionSub = FirebaseDatabase.instance
        .ref('ai_forecast/model/version')
        .onValue
        .listen((_) => _loadModelMeta(), onError: (_) {});
    _forecastSub = FirebaseDatabase.instance
        .ref('ai_predictions/forecast')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _liveForecast = v is Map
                  ? Map<String, dynamic>.from(v)
                  : null,
            );
          }
        }, onError: (_) {});
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/predictive/settings')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          if (mounted) {
            setState(
              () => _settings = v is Map
                  ? Map<String, dynamic>.from(v)
                  : const {},
            );
          }
        }, onError: (_) {});
  }

  Future<void> _loadModelMeta() async {
    const keys = [
      'version',
      'trainedAt',
      'lastAdaptedAt',
      'datasetName',
      'sampleCount',
      'valLoss',
      'valAccuracy',
      'rounds',
      'adaptedRounds',
      'learning',
      'algo',
    ];
    try {
      final reads = await Future.wait([
        for (final k in keys)
          FirebaseDatabase.instance.ref('ai_forecast/model/$k').get(),
      ]);
      final meta = <String, dynamic>{};
      for (var i = 0; i < keys.length; i++) {
        meta[keys[i]] = reads[i].value;
      }
      if (mounted) setState(() => _modelMeta = meta);
    } catch (_) {}
  }

  Future<void> _setSetting(String key, bool value) async {
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/predictive/settings/$key')
          .set(value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _histSub?.cancel();
    _versionSub?.cancel();
    _forecastSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final deployed = _modelMeta['trainedAt'] != null;
    final version = (_modelMeta['version'] as num?)?.toInt() ?? 0;
    final adapted = (_modelMeta['adaptedRounds'] as num?)?.toInt() ?? 0;
    final pairs = (_accuracy?['gradedPairs'] as num?)?.toInt() ?? 0;
    final tp = (_accuracy?['tp'] as num?)?.toInt() ?? 0;
    final fp = (_accuracy?['fp'] as num?)?.toInt() ?? 0;
    final fn = (_accuracy?['fn'] as num?)?.toInt() ?? 0;
    final precision = (tp + fp) == 0 ? 0.0 : tp / (tp + fp);
    final recall = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
    final brier = pairs == 0
        ? 0.0
        : ((_accuracy?['brierSum'] as num?)?.toDouble() ?? 0) / pairs;
    final machines = (_liveForecast?['machineCount'] as num?)?.toInt() ?? 0;

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        _SegTabs(
          tabs: [context.tr('MODEL CORE'), context.tr('BRAIN')],
          icons: const [Icons.dashboard_customize_outlined, Icons.psychology],
          index: _view,
          accent: spec.accent,
          onChanged: (i) => setState(() => _view = i),
        ),
        if (_view == 1)
          _PredictiveBrainView(
            modelMeta: _modelMeta,
            accuracy: _accuracy,
            gradeHistory: _gradeHistory,
            liveForecast: _liveForecast,
            accent: spec.accent,
            enabled: widget.enabled,
          ),
        if (_view == 0)
          GlassPanel(
            accent: spec.accent,
            glow: widget.enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: spec.icon,
                  leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                  title: context.tr('MODEL CORE'),
                  subtitle: deployed
                      ? context.tr(
                          'On-device gradient-boosted forecaster, live on every Production Manager dashboard.',
                        )
                      : context.tr(
                          'No model deployed yet — train one in the AI Training tab.',
                        ),
                  accent: spec.accent,
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      GlowChip(
                        label: 'SIAS-GBDT v$version',
                        color: spec.accent,
                        icon: Icons.account_tree_outlined,
                      ),
                      if (_modelMeta['learning'] == true)
                        GlowChip(
                          label: context.tr('LEARNING ✓'),
                          color: Sa.green,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SaStatTile(
                      label: context.tr('Dataset'),
                      value: (_modelMeta['datasetName'] ?? '—').toString(),
                      icon: Icons.dataset_outlined,
                      color: spec.accent,
                    ),
                    SaStatTile(
                      label: context.tr('Training samples'),
                      value:
                          '${(_modelMeta['sampleCount'] as num?)?.toInt() ?? 0}',
                      icon: Icons.grain,
                      color: Sa.blue,
                    ),
                    SaStatTile(
                      label: context.tr('Boosted rounds'),
                      value: context.tr('{rounds} + {adapted} adapted', {
                        'rounds':
                            '${(_modelMeta['rounds'] as num?)?.toInt() ?? 0}',
                        'adapted': '$adapted',
                      }),
                      icon: Icons.forest_outlined,
                      color: Sa.green,
                    ),
                    SaStatTile(
                      label: context.tr('Val accuracy'),
                      value:
                          '${(((_modelMeta['valAccuracy'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%',
                      icon: Icons.verified_outlined,
                      color: Sa.violet,
                    ),
                    SaStatTile(
                      label: context.tr('Machines forecast'),
                      value: '$machines',
                      icon: Icons.precision_manufacturing_outlined,
                      color: Sa.amber,
                    ),
                    SaStatTile(
                      label: context.tr('Trained'),
                      value: _agoIso(context, _modelMeta['trainedAt']),
                      icon: Icons.schedule,
                      color: Sa.muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_view == 0)
          GlassPanel(
            accent: spec.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.psychology_outlined,
                  title: context.tr('CONTINUOUS LEARNING'),
                  subtitle: context.tr(
                    'The core snapshots tomorrow’s forecast daily, grades itself against the alerts that really happened, and boosts adaptation trees on fresh data.',
                  ),
                  accent: spec.accent,
                  trailing: GlowChip(
                    label: _accuracy == null
                        ? context.tr('AWAITING FIRST GRADE')
                        : context.tr('{count} DAYS GRADED', {
                            'count':
                                '${(_accuracy?['gradedDays'] as num?)?.toInt() ?? 0}',
                          }),
                    color: _accuracy == null ? Sa.muted : Sa.green,
                    pulse: _accuracy != null,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (ctx, c) {
                    final wide = c.maxWidth >= 760;
                    final gauges = Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RingGauge(
                          label: context.tr('PRECISION'),
                          value: precision,
                          color: spec.accent,
                        ),
                        _RingGauge(
                          label: context.tr('RECALL'),
                          value: recall,
                          color: Sa.cyan,
                        ),
                        _RingGauge(
                          label: context.tr('BRIER'),
                          value: (1 - brier).clamp(0.0, 1.0),
                          display: brier.toStringAsFixed(3),
                          color: Sa.green,
                        ),
                      ],
                    );
                    final chart = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(
                            'FORECAST QUALITY TREND · BRIER PER GRADED DAY',
                          ),
                          style: Sa.mono(size: 8.5, color: Sa.muted),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 110,
                          child: _gradeHistory.isEmpty
                              ? Center(
                                  child: Text(
                                    context.tr(
                                      'Trend appears after the first graded day.',
                                    ),
                                    style: Sa.body(size: 11, color: Sa.muted),
                                  ),
                                )
                              : CustomPaint(
                                  size: Size.infinite,
                                  painter: _BrierTrendPainter(
                                    history: _gradeHistory,
                                    color: spec.accent,
                                    gridColor: Sa.border,
                                    textColor: Sa.muted,
                                  ),
                                ),
                        ),
                      ],
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 330, child: gauges),
                          const SizedBox(width: 20),
                          Expanded(child: chart),
                        ],
                      );
                    }
                    return Column(
                      children: [gauges, const SizedBox(height: 16), chart],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          context.tr('DATA ABSORPTION · ADAPTATION BUDGET'),
                          style: Sa.mono(size: 8.5, color: Sa.muted),
                        ),
                        const Spacer(),
                        Text(
                          context.tr('{adapted} / 60 extra trees per type', {
                            'adapted': '$adapted',
                          }),
                          style: Sa.mono(size: 9.5, color: spec.accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 8,
                        child: Stack(
                          children: [
                            Container(color: Sa.border.withValues(alpha: 0.5)),
                            FractionallySizedBox(
                              widthFactor: (adapted / 60).clamp(0.0, 1.0),
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [spec.accent, Sa.cyan],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr(
                        'Graded {pairs} machine-type pairs · {hits} confirmed hits · last adapted {time} · a full retrain resets the budget.',
                        {
                          'pairs': '$pairs',
                          'hits': '$tp',
                          'time': _agoIso(context, _modelMeta['lastAdaptedAt']),
                        },
                      ),
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_view == 0)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.tune,
                  title: context.tr('LEARNING CONTROLS'),
                  subtitle: context.tr(
                    'Pause parts of the learning loop without undeploying the model.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 12),
                _SettingTile(
                  title: context.tr('Continuous adaptation'),
                  description: context.tr(
                    'Boost a few stiffly-regularized trees onto the live ensemble (~daily) from recent production alerts.',
                  ),
                  icon: Icons.auto_mode,
                  accent: spec.accent,
                  value: _settings['adaptationEnabled'] != false,
                  onChanged: (v) => _setSetting('adaptationEnabled', v),
                ),
                _SettingTile(
                  title: context.tr('Outcome grading'),
                  description: context.tr(
                    'Snapshot tomorrow’s forecast each day and grade it against reality (precision/recall/Brier above).',
                  ),
                  icon: Icons.fact_check_outlined,
                  accent: spec.accent,
                  value: _settings['outcomeGrading'] != false,
                  onChanged: (v) => _setSetting('outcomeGrading', v),
                ),
              ],
            ),
          ),
        if (_view == 0)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.receipt_long_outlined,
                  title: context.tr('GRADED DAYS'),
                  subtitle: context.tr(
                    'Each elapsed forecast day, scored against the alerts that materialized.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 12),
                if (_gradeHistory.isEmpty)
                  SaEmptyState(
                    icon: Icons.pending_actions_outlined,
                    title: context.tr('No graded days yet'),
                    message: context.tr(
                      'The first grade lands the day after a forecast snapshot — fully automatic, server-side.',
                    ),
                    accent: spec.accent,
                  )
                else
                  ..._gradeHistory.reversed
                      .take(20)
                      .map(
                        (g) => _LogTile(
                          kind: 'graded',
                          color: spec.accent,
                          title: context.tr(
                            '{day} · {pairs} pairs · {hits} hits · Brier {brier}',
                            {
                              'day': '${g['day']}',
                              'pairs': '${g['pairs'] ?? 0}',
                              'hits': '${g['tp'] ?? 0}',
                              'brier': ((g['brier'] as num?)?.toDouble() ?? 0)
                                  .toStringAsFixed(3),
                            },
                          ),
                          at: (g['gradedAt'] ?? '').toString(),
                          details: g,
                        ),
                      ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// PREDICTIVE CORE · BRAIN — a 3D neural mesh of the GBDT forecaster.
// ─────────────────────────────────────────────────────────────────────────

/// One engineered feature family the forecaster scores on.
class _Signal {
  final String label;
  final String desc;
  final double weight;
  final Color color;
  const _Signal(this.label, this.desc, this.weight, this.color);
}

const List<_Signal> _kForecastSignals = [
  _Signal(
    'Recent alert rate',
    'Yesterday & the day before (lags t-1, t-2).',
    0.92,
    Color(0xFF378ADD),
  ),
  _Signal(
    '7-day rolling counts',
    'Per-type frequency over the last week.',
    0.85,
    Color(0xFF7F77DD),
  ),
  _Signal(
    '7 / 14-day totals',
    'Short vs medium-term load.',
    0.70,
    Color(0xFF1D9E75),
  ),
  _Signal(
    'Week-over-week trend',
    'Is this machine heating up or cooling down?',
    0.78,
    Color(0xFFBA7517),
  ),
  _Signal(
    'Per-type recency',
    'Days since each type last fired (capped 30).',
    0.66,
    Color(0xFFD4537E),
  ),
  _Signal(
    'Critical pressure',
    'Weight of recent critical alerts.',
    0.60,
    Color(0xFFE24B4A),
  ),
  _Signal(
    'Calendar context',
    'Day-of-week / tomorrow seasonality.',
    0.42,
    Color(0xFF534AB7),
  ),
  _Signal(
    "Today's snapshot",
    'The machine state the forecast starts from.',
    0.55,
    Color(0xFF2AA7A0),
  ),
];

/// The Predictive Core BRAIN sub-view: 3D mesh, anatomy, signals, self-grading.
class _PredictiveBrainView extends StatelessWidget {
  final Map<String, dynamic> modelMeta;
  final Map<String, dynamic>? accuracy;
  final List<Map<String, dynamic>> gradeHistory;
  final Map<String, dynamic>? liveForecast;
  final Color accent;
  final bool enabled;
  const _PredictiveBrainView({
    required this.modelMeta,
    required this.accuracy,
    required this.gradeHistory,
    required this.liveForecast,
    required this.accent,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final deployed = modelMeta['trainedAt'] != null;
    final version = (modelMeta['version'] as num?)?.toInt() ?? 0;
    final rounds = (modelMeta['rounds'] as num?)?.toInt() ?? 0;
    final adapted = (modelMeta['adaptedRounds'] as num?)?.toInt() ?? 0;
    final samples = (modelMeta['sampleCount'] as num?)?.toInt() ?? 0;
    final valAcc = ((modelMeta['valAccuracy'] as num?)?.toDouble() ?? 0) * 100;
    final pairs = (accuracy?['gradedPairs'] as num?)?.toInt() ?? 0;
    final tp = (accuracy?['tp'] as num?)?.toInt() ?? 0;
    final fp = (accuracy?['fp'] as num?)?.toInt() ?? 0;
    final fn = (accuracy?['fn'] as num?)?.toInt() ?? 0;
    final precision = (tp + fp) == 0 ? 0.0 : tp / (tp + fp);
    final recall = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
    final brier = pairs == 0
        ? 0.0
        : ((accuracy?['brierSum'] as num?)?.toDouble() ?? 0) / pairs;
    final gradedDays = (accuracy?['gradedDays'] as num?)?.toInt() ?? 0;
    final machines = (liveForecast?['machineCount'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          accent: accent,
          glow: enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.psychology,
                title: context.tr('INSIDE THE FORECASTER’S MIND'),
                subtitle: deployed
                    ? context.tr(
                        'A gradient-boosted ensemble — hundreds of decision trees, rendered as one rotating neural mesh.',
                      )
                    : context.tr(
                        'No model deployed yet — train one in the AI Training tab to wake the mind.',
                      ),
                accent: accent,
                trailing: GlowChip(
                  label: 'SIAS-GBDT v$version',
                  color: accent,
                  icon: Icons.account_tree_outlined,
                  pulse: enabled && deployed,
                ),
              ),
              const SizedBox(height: 10),
              _CortexHero(
                accent: accent,
                animate: enabled && deployed,
                inputs: [
                  for (final s in _kForecastSignals)
                    _CortexInput(
                      s.label,
                      s.color,
                      s.weight,
                      deployed ? s.weight : 0.15,
                    ),
                ],
                inHeader: 'SIGNALS IT READS',
                coreTop: 'GBDT',
                coreBottom: deployed ? 'FORECASTS' : 'IDLE',
                outIcon: Icons.online_prediction,
                outTop: 'Tomorrow’s',
                outBottom: 'risk · 24h',
                outColor: accent,
              ),
              const SizedBox(height: 8),
              Text(
                deployed
                    ? context.tr(
                        'It studies the last weeks of alerts, learns which machines tend to fail and when, then forecasts each machine’s risk for the next 24 hours — a weather forecast for the factory ({machines} machines covered).',
                        {'machines': '$machines'},
                      )
                    : context.tr(
                        'Once a model is trained, it forecasts each machine’s risk for the next 24 hours — like a weather forecast for the factory.',
                      ),
                style: Sa.body(size: 11.5, color: Sa.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.account_tree,
                title: context.tr('MODEL ANATOMY'),
                subtitle: context.tr(
                  'Four boosted ensembles — one prediction head per alert type.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Boosted rounds'),
                    value: '$rounds',
                    icon: Icons.forest_outlined,
                    color: accent,
                  ),
                  SaStatTile(
                    label: context.tr('Adapted trees'),
                    value: '$adapted',
                    icon: Icons.auto_mode,
                    color: Sa.green,
                  ),
                  SaStatTile(
                    label: context.tr('Training samples'),
                    value: '$samples',
                    icon: Icons.grain,
                    color: Sa.blue,
                  ),
                  SaStatTile(
                    label: context.tr('Val accuracy'),
                    value: '${valAcc.toStringAsFixed(1)}%',
                    icon: Icons.verified_outlined,
                    color: Sa.violet,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TypeHeadChip(label: context.tr('Quality')),
                  _TypeHeadChip(label: context.tr('Maintenance')),
                  _TypeHeadChip(label: context.tr('Damaged Product')),
                  _TypeHeadChip(label: context.tr('Resource Deficiency')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.sensors,
                title: context.tr('SIGNALS IT READS'),
                subtitle: context.tr(
                  'The engineered features each machine-day is scored on.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 12),
              for (final s in _kForecastSignals) _SignalBar(s: s),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.fact_check_outlined,
                title: context.tr('SELF-ASSESSMENT'),
                subtitle: context.tr(
                  'How the model grades its own forecasts against reality.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 14),
              if (accuracy == null)
                SaEmptyState(
                  icon: Icons.pending_actions_outlined,
                  title: context.tr('No grades yet'),
                  message: context.tr(
                    'The first self-grade lands the day after a forecast snapshot — fully automatic.',
                  ),
                  accent: accent,
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SaStatTile(
                      label: context.tr('Precision'),
                      value: '${(precision * 100).round()}%',
                      icon: Icons.center_focus_strong,
                      color: accent,
                    ),
                    SaStatTile(
                      label: context.tr('Recall'),
                      value: '${(recall * 100).round()}%',
                      icon: Icons.radar,
                      color: Sa.cyan,
                    ),
                    SaStatTile(
                      label: context.tr('Brier score'),
                      value: brier.toStringAsFixed(3),
                      icon: Icons.show_chart,
                      color: Sa.green,
                    ),
                    SaStatTile(
                      label: context.tr('Days graded'),
                      value: '$gradedDays',
                      icon: Icons.event_available,
                      color: Sa.amber,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One alert-type prediction head chip.
class _TypeHeadChip extends StatelessWidget {
  final String label;
  const _TypeHeadChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Sa.panelSolid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined, size: 14, color: Sa.muted),
          const SizedBox(width: 8),
          Text(label, style: Sa.body(size: 12, color: Sa.text)),
          const SizedBox(width: 8),
          Text(context.tr('ensemble'), style: Sa.mono(size: 8.5, color: Sa.muted)),
        ],
      ),
    );
  }
}

/// Feature-influence bar (illustrative weighting).
class _SignalBar extends StatelessWidget {
  final _Signal s;
  const _SignalBar({required this.s});

  @override
  Widget build(BuildContext context) {
    final influence = s.weight.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(s.label),
                  style: Sa.body(size: 13, color: Sa.text),
                ),
              ),
              Text(
                '${(influence * 100).round()}%',
                style: Sa.mono(size: 10.5, color: Sa.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              context.tr(s.desc),
              style: Sa.body(size: 11, color: Sa.textDim),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: LayoutBuilder(
              builder: (ctx, cons) => Container(
                height: 7,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Sa.panelSolid,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Container(
                  height: 7,
                  width: cons.maxWidth * influence,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular gauge with a sweeping arc — precision/recall/Brier display.
class _RingGauge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String? display;

  const _RingGauge({
    required this.label,
    required this.value,
    required this.color,
    this.display,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              painter: _RingPainter(value: v, color: color, track: Sa.border),
              child: Center(
                child: Text(
                  display ?? '${(v * 100).round()}%',
                  style: Sa.mono(size: 13, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Sa.mono(size: 8.5, color: Sa.muted)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  _RingPainter({required this.value, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = track.withValues(alpha: 0.6);
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [color.withValues(alpha: 0.5), color],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      arc,
    );
    canvas.drawCircle(
      c,
      r + 4,
      Paint()..color = color.withValues(alpha: 0.06 * value),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

/// Brier-per-day trend: line + soft area + hit markers. Lower is better.
class _BrierTrendPainter extends CustomPainter {
  final List<Map<String, dynamic>> history;
  final Color color;
  final Color gridColor;
  final Color textColor;

  _BrierTrendPainter({
    required this.history,
    required this.color,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    final briers = [
      for (final h in history) ((h['brier'] as num?)?.toDouble() ?? 0),
    ];
    var maxB = briers.reduce(math.max);
    if (maxB <= 0) maxB = 0.1;
    maxB *= 1.2;

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    Offset pt(int i) {
      final x = history.length == 1
          ? size.width / 2
          : size.width * i / (history.length - 1);
      final y = size.height * (1 - (briers[i] / maxB).clamp(0.0, 1.0));
      return Offset(x, y);
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    final area = Path()..moveTo(pt(0).dx, size.height);
    area.lineTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < history.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
      area.lineTo(pt(i).dx, pt(i).dy);
    }
    area.lineTo(pt(history.length - 1).dx, size.height);
    area.close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    for (var i = 0; i < history.length; i++) {
      canvas.drawCircle(pt(i), 2.4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BrierTrendPainter old) =>
      old.history != history || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-06 · GUARDIAN
// ═══════════════════════════════════════════════════════════════════════════


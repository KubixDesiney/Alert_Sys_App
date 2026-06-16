part of 'ai_agents_tab.dart';

class _SecurityAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _SecurityAgentPanel(
      {required this.spec, required this.enabled, required this.health});

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
        .listen((event) {
      if (mounted) {
        setState(
            () => _actions = _mapToSortedList(event.snapshot.value, 'at'));
      }
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/security/settings')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _settings = v is Map ? Map<String, dynamic>.from(v) : const {});
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            'Defense disabled. The edge worker drops this shield within 60s — re-arm it when done testing.',
            style: Sa.body(size: 12.5, color: Sa.amber),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Update failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
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

    return _AgentScroll(children: [
      if (!widget.enabled) _OfflineBanner(spec: spec),
      GlassPanel(
        accent: spec.accent,
        glow: widget.enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: spec.icon,
              title: 'THREAT CONSOLE',
              subtitle:
                  'Standing guard on every worker endpoint. Blocks are logged with the exact signature that fired.',
              accent: spec.accent,
              trailing: GlowChip(
                label: '$armed/${_defenses.length} DEFENSES ARMED',
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
                  label: 'Blocks · 24h',
                  value: '${recent.length}',
                  icon: Icons.block_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Actions · last cron',
                  value:
                      '${(widget.health?['securityActions'] as num?)?.toInt() ?? 0}',
                  icon: Icons.gpp_maybe_outlined,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Attack signatures',
                  value: '12',
                  icon: Icons.fingerprint,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Last block',
                  value: _actions.isEmpty ? '—' : _agoIso(_actions.first['at']),
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
              title: 'DEFENSE GRID',
              subtitle:
                  'Arm or stand down individual shields. Changes reach the edge worker within 60 seconds.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            for (final d in _defenses)
              _SettingTile(
                title: d.title,
                description: d.desc,
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
              title: 'THREAT MIX · 24H',
              subtitle: 'What the sentinel has been deflecting.',
              accent: spec.accent,
            ),
            const SizedBox(height: 14),
            if (byKind.isEmpty)
              Text('Clean skies — no blocks in the last 24 hours.',
                  style: Sa.body(size: 12, color: Sa.textDim))
            else
              ...byKind.entries.map((e) => _KindBar(
                    label: e.key,
                    count: e.value,
                    max: maxKind,
                    color: _kindColor(e.key),
                  )),
          ],
        ),
      ),
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.receipt_long_outlined,
              title: 'ENFORCEMENT LOG',
              subtitle:
                  'Every block with endpoint, fingerprint and matched patterns. Tap for the full record.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SaEmptyState(
                icon: Icons.lock_outline,
                title: 'Cannot read security actions',
                message: _error!,
                accent: Sa.red,
              )
            else if (_actions.isEmpty)
              SaEmptyState(
                icon: Icons.verified_user_outlined,
                title: 'No enforcement actions',
                message: 'The sentinel has not needed to block anything yet.',
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
    ]);
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

  @override
  void initState() {
    super.initState();
    _accSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/latest')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _accuracy = v is Map ? Map<String, dynamic>.from(v) : null);
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
            (a, b) => (a['day'] ?? '').toString().compareTo((b['day'] ?? '').toString()));
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
        setState(() =>
            _liveForecast = v is Map ? Map<String, dynamic>.from(v) : null);
      }
    }, onError: (_) {});
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/predictive/settings')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _settings = v is Map ? Map<String, dynamic>.from(v) : const {});
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

    return _AgentScroll(children: [
      if (!widget.enabled) _OfflineBanner(spec: spec),
      GlassPanel(
        accent: spec.accent,
        glow: widget.enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: spec.icon,
              leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
              title: 'MODEL CORE',
              subtitle: deployed
                  ? 'On-device gradient-boosted forecaster, live on every Production Manager dashboard.'
                  : 'No model deployed yet — train one in the AI Training tab.',
              accent: spec.accent,
              trailing: Wrap(
                spacing: 6,
                children: [
                  GlowChip(
                    label: 'SIA-GBDT v$version',
                    color: spec.accent,
                    icon: Icons.account_tree_outlined,
                  ),
                  if (_modelMeta['learning'] == true)
                    GlowChip(label: 'LEARNING ✓', color: Sa.green),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Dataset',
                  value: (_modelMeta['datasetName'] ?? '—').toString(),
                  icon: Icons.dataset_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Training samples',
                  value: '${(_modelMeta['sampleCount'] as num?)?.toInt() ?? 0}',
                  icon: Icons.grain,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'Boosted rounds',
                  value:
                      '${(_modelMeta['rounds'] as num?)?.toInt() ?? 0} + $adapted adapted',
                  icon: Icons.forest_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'Val accuracy',
                  value:
                      '${(((_modelMeta['valAccuracy'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%',
                  icon: Icons.verified_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Machines forecast',
                  value: '$machines',
                  icon: Icons.precision_manufacturing_outlined,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Trained',
                  value: _agoIso(_modelMeta['trainedAt']),
                  icon: Icons.schedule,
                  color: Sa.muted,
                ),
              ],
            ),
          ],
        ),
      ),
      GlassPanel(
        accent: spec.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.psychology_outlined,
              title: 'CONTINUOUS LEARNING',
              subtitle:
                  'The core snapshots tomorrow’s forecast daily, grades itself against the alerts that really happened, and boosts adaptation trees on fresh data.',
              accent: spec.accent,
              trailing: GlowChip(
                label: _accuracy == null
                    ? 'AWAITING FIRST GRADE'
                    : '${(_accuracy?['gradedDays'] as num?)?.toInt() ?? 0} DAYS GRADED',
                color: _accuracy == null ? Sa.muted : Sa.green,
                pulse: _accuracy != null,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (ctx, c) {
              final wide = c.maxWidth >= 760;
              final gauges = Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RingGauge(
                      label: 'PRECISION',
                      value: precision,
                      color: spec.accent),
                  _RingGauge(label: 'RECALL', value: recall, color: Sa.cyan),
                  _RingGauge(
                    label: 'BRIER',
                    value: (1 - brier).clamp(0.0, 1.0),
                    display: brier.toStringAsFixed(3),
                    color: Sa.green,
                  ),
                ],
              );
              final chart = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FORECAST QUALITY TREND · BRIER PER GRADED DAY',
                      style: Sa.mono(size: 8.5, color: Sa.muted)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 110,
                    child: _gradeHistory.isEmpty
                        ? Center(
                            child: Text(
                              'Trend appears after the first graded day.',
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
              return Column(children: [gauges, const SizedBox(height: 16), chart]);
            }),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('DATA ABSORPTION · ADAPTATION BUDGET',
                        style: Sa.mono(size: 8.5, color: Sa.muted)),
                    const Spacer(),
                    Text('$adapted / 60 extra trees per type',
                        style: Sa.mono(size: 9.5, color: spec.accent)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 8,
                    child: Stack(children: [
                      Container(color: Sa.border.withValues(alpha: 0.5)),
                      FractionallySizedBox(
                        widthFactor: (adapted / 60).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [spec.accent, Sa.cyan]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Graded $pairs machine-type pairs · $tp confirmed hits · last adapted ${_agoIso(_modelMeta['lastAdaptedAt'])} · a full retrain resets the budget.',
                  style: Sa.body(size: 10.5, color: Sa.textDim),
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
              title: 'LEARNING CONTROLS',
              subtitle:
                  'Pause parts of the learning loop without undeploying the model.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            _SettingTile(
              title: 'Continuous adaptation',
              description:
                  'Boost a few stiffly-regularized trees onto the live ensemble (~daily) from recent production alerts.',
              icon: Icons.auto_mode,
              accent: spec.accent,
              value: _settings['adaptationEnabled'] != false,
              onChanged: (v) => _setSetting('adaptationEnabled', v),
            ),
            _SettingTile(
              title: 'Outcome grading',
              description:
                  'Snapshot tomorrow’s forecast each day and grade it against reality (precision/recall/Brier above).',
              icon: Icons.fact_check_outlined,
              accent: spec.accent,
              value: _settings['outcomeGrading'] != false,
              onChanged: (v) => _setSetting('outcomeGrading', v),
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
              title: 'GRADED DAYS',
              subtitle:
                  'Each elapsed forecast day, scored against the alerts that materialized.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_gradeHistory.isEmpty)
              SaEmptyState(
                icon: Icons.pending_actions_outlined,
                title: 'No graded days yet',
                message:
                    'The first grade lands the day after a forecast snapshot — fully automatic, server-side.',
                accent: spec.accent,
              )
            else
              ..._gradeHistory.reversed.take(20).map((g) => _LogTile(
                    kind: 'graded',
                    color: spec.accent,
                    title:
                        '${g['day']} · ${g['pairs'] ?? 0} pairs · ${g['tp'] ?? 0} hits · Brier ${((g['brier'] as num?)?.toDouble() ?? 0).toStringAsFixed(3)}',
                    at: (g['gradedAt'] ?? '').toString(),
                    details: g,
                  )),
          ],
        ),
      ),
    ]);
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
              painter: _RingPainter(
                  value: v, color: color, track: Sa.border),
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
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        math.pi * 2 * value, false, arc);
    canvas.drawCircle(
        c, r + 4, Paint()..color = color.withValues(alpha: 0.06 * value));
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
      for (final h in history) ((h['brier'] as num?)?.toDouble() ?? 0)
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


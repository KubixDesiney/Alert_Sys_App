// Shift Commander panel: activity log, kind breakdown, health-pulse stats,
// the tactical brain (scoring-weight categories, cortex hero, memories).
//
// This is a part file of ai_agents_tab.dart (one library, split for
// maintainability); private identifiers are shared across all parts.
part of 'ai_agents_tab.dart';

class _ShiftAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _ShiftAgentPanel({
    required this.spec,
    required this.enabled,
    required this.health,
  });

  @override
  State<_ShiftAgentPanel> createState() => _ShiftAgentPanelState();
}

class _ShiftAgentPanelState extends State<_ShiftAgentPanel> {
  StreamSubscription<DatabaseEvent>? _sub;
  StreamSubscription<DatabaseEvent>? _fbSub;
  List<Map<String, dynamic>> _logs = const [];
  List<_BrainMemory> _memory = const [];
  String? _error;
  int _view = 0; // 0 = command deck, 1 = brain

  @override
  void initState() {
    super.initState();
    // Learned signals: per-supervisor reinforcement feedback — the commander's memory.
    _fbSub = FirebaseDatabase.instance
        .ref('ai_feedback/summary')
        .onValue
        .listen((event) {
          final v = event.snapshot.value;
          final mem = <_BrainMemory>[];
          if (v is Map) {
            v.forEach((id, row) {
              if (row is Map) mem.add(_BrainMemory.fromMap(id.toString(), row));
            });
            mem.sort((a, b) => b.weight.compareTo(a.weight));
          }
          if (mounted) setState(() => _memory = mem);
        }, onError: (_) {});
    _sub = FirebaseDatabase.instance
        .ref('shift_ai_logs')
        .limitToLast(25)
        .onValue
        .listen(
          (event) {
            final v = event.snapshot.value;
            final flat = <Map<String, dynamic>>[];
            if (v is Map) {
              v.forEach((shiftId, logs) {
                if (logs is Map) {
                  logs.forEach((logId, entry) {
                    if (entry is Map) {
                      final m = Map<String, dynamic>.from(entry);
                      m['id'] = logId.toString();
                      m['shiftId'] = (m['shiftId'] ?? shiftId).toString();
                      flat.add(m);
                    }
                  });
                }
              });
              flat.sort(
                (a, b) => (b['at'] ?? '').toString().compareTo(
                  (a['at'] ?? '').toString(),
                ),
              );
            }
            if (mounted) setState(() => _logs = flat.take(120).toList());
          },
          onError: (e) {
            if (mounted) setState(() => _error = '$e');
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fbSub?.cancel();
    super.dispose();
  }

  String _bucket(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('assign') || k.contains('transfer')) {
      return context.tr('Assignments');
    }
    if (k.contains('collab')) return context.tr('Collaborations');
    if (k.contains('handover')) return context.tr('Handovers');
    if (k.contains('presence')) return context.tr('Presence checks');
    if (k.contains('block') || k.contains('skip')) {
      return context.tr('Blocked / skipped');
    }
    return context.tr('Other');
  }

  Color _kindColor(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('block') || k.contains('skip')) return Sa.amber;
    if (k.contains('handover')) return Sa.violet;
    if (k.contains('collab')) return Sa.blue;
    if (k.contains('presence')) return Sa.muted;
    return Sa.cyan;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final dayAgo = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final last24 = _logs.where((l) {
      final t = DateTime.tryParse((l['at'] ?? '').toString());
      return t != null && t.toUtc().isAfter(dayAgo);
    }).toList();
    final buckets = <String, int>{};
    for (final l in _logs) {
      final b = _bucket((l['kind'] ?? '').toString());
      buckets[b] = (buckets[b] ?? 0) + 1;
    }
    final maxBucket = buckets.values.isEmpty
        ? 0
        : buckets.values.reduce(math.max);
    final health = widget.health;

    return _AgentScroll(
      children: [
        if (!widget.enabled) _OfflineBanner(spec: spec),
        _SegTabs(
          tabs: [context.tr('COMMAND DECK'), context.tr('BRAIN')],
          icons: const [Icons.dashboard_customize_outlined, Icons.psychology],
          index: _view,
          accent: spec.accent,
          onChanged: (i) => setState(() => _view = i),
        ),
        if (_view == 1)
          _ShiftBrainView(
            logs: _logs,
            memory: _memory,
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
                  title: context.tr('COMMAND DECK'),
                  subtitle: context.tr(
                    'Every decision the AI commander takes across active shifts — assignments, collaborations, handovers, presence.',
                  ),
                  accent: spec.accent,
                  trailing: GlowChip(
                    label: context.tr('MODEL ENGINE'),
                    color: spec.accent,
                    icon: Icons.hub_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SaStatTile(
                      label: context.tr('Actions · 24h'),
                      value: '${last24.length}',
                      icon: Icons.bolt_outlined,
                      color: spec.accent,
                    ),
                    SaStatTile(
                      label: context.tr('Assignments · last cron'),
                      value:
                          '${(health?['assignmentsMade'] as num?)?.toInt() ?? 0}',
                      icon: Icons.assignment_turned_in_outlined,
                      color: Sa.green,
                    ),
                    SaStatTile(
                      label: context.tr('Collabs · last cron'),
                      value:
                          '${(health?['collaborationsApproved'] as num?)?.toInt() ?? 0}',
                      icon: Icons.handshake_outlined,
                      color: Sa.blue,
                    ),
                    SaStatTile(
                      label: context.tr('Handovers · last cron'),
                      value:
                          '${(health?['handoversGenerated'] as num?)?.toInt() ?? 0}',
                      icon: Icons.swap_horiz,
                      color: Sa.violet,
                    ),
                    SaStatTile(
                      label: context.tr('Last pulse'),
                      value: _agoIso(context, health?['timestamp']),
                      icon: Icons.monitor_heart_outlined,
                      color: Sa.amber,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_view == 0)
          _ModelEnginePanel(
            agent: 'shift',
            accent: spec.accent,
            enabled: widget.enabled,
          ),
        if (_view == 0)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.stacked_bar_chart,
                  title: context.tr('TASK BREAKDOWN'),
                  subtitle: context.tr(
                    'Distribution of the commander’s recent decisions.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 14),
                if (buckets.isEmpty)
                  Text(
                    context.tr('No shift AI activity recorded yet.'),
                    style: Sa.body(size: 12, color: Sa.textDim),
                  )
                else
                  ...buckets.entries.map(
                    (e) => _KindBar(
                      label: e.key,
                      count: e.value,
                      max: maxBucket,
                      color: spec.accent,
                    ),
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
                  title: context.tr('ACTION LOG'),
                  subtitle: context.tr(
                    'Tap any entry for the full unredacted reasoning, confidence and gate diagnostics.',
                  ),
                  accent: spec.accent,
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  SaEmptyState(
                    icon: Icons.lock_outline,
                    title: context.tr('Cannot read shift AI logs'),
                    message: _error!,
                    accent: Sa.red,
                  )
                else if (_logs.isEmpty)
                  SaEmptyState(
                    icon: Icons.nights_stay_outlined,
                    title: context.tr('No actions yet'),
                    message: context.tr(
                      'The commander logs here the moment a shift with AI Commander enabled goes live.',
                    ),
                    accent: spec.accent,
                  )
                else
                  ..._logs.take(40).map((l) {
                    final kind = (l['kind'] ?? 'action').toString();
                    final who = (l['supervisorName'] ?? '').toString();
                    final alert = (l['alertLabel'] ?? '').toString();
                    final reason = (l['reason'] ?? '').toString();
                    final title = [
                      if (alert.isNotEmpty) alert,
                      if (who.isNotEmpty) '→ $who',
                      if (alert.isEmpty && who.isEmpty) reason,
                    ].join(' ');
                    return _LogTile(
                      kind: kind,
                      color: _kindColor(kind),
                      title: title.isEmpty ? '—' : title,
                      at: (l['at'] ?? '').toString(),
                      details: l,
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
// UNIT-02 · BRIEFING OFFICER
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────
// SHIFT COMMANDER · BRAIN — "inside his head"
// A live visualisation of how the commander weighs supervisors, what it has
// learned (reinforcement memory), and the reasoning behind recent decisions.
// ─────────────────────────────────────────────────────────────────────────

/// Segmented sub-tab control (COMMAND DECK / BRAIN).
class _SegTabs extends StatelessWidget {
  final List<String> tabs;
  final List<IconData> icons;
  final int index;
  final Color accent;
  final ValueChanged<int> onChanged;
  const _SegTabs({
    required this.tabs,
    required this.icons,
    required this.index,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Sa.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == index
                        ? accent.withValues(alpha: Sa.isDark ? 0.18 : 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: i == index
                          ? accent.withValues(alpha: 0.6)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icons[i],
                        size: 16,
                        color: i == index ? accent : Sa.muted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tabs[i],
                        style: Sa.body(
                          size: 12.5,
                          color: i == index ? Sa.text : Sa.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One of the commander's seven scoring signals.
class _BrainFactor {
  final String label;
  final String desc;
  final double
  weight; // 0..1 — the *baseline* influence (also the RTDB default)
  final Color color;
  final List<String> keys; // keywords detected in decision reasons
  final String slug; // stable id used as the RTDB key and worker component key
  const _BrainFactor(
    this.label,
    this.desc,
    this.weight,
    this.color,
    this.keys,
    this.slug,
  );
}

// The [slug]s here MUST mirror `_SHIFT_ASSIGN_DEFAULTS` in cloudflare_ai_worker.js —
// they are the live RTDB keys the worker reads to retune assignment scoring.
const List<_BrainFactor> _kShiftFactors = [
  _BrainFactor(
    'Factory fit',
    'Same plant as the alert.',
    0.95,
    Color(0xFF378ADD),
    ['factory', 'plant', 'usine', 'same site'],
    'factory',
  ),
  _BrainFactor(
    'Type skill',
    'Proven experience with this alert type.',
    0.80,
    Color(0xFF7F77DD),
    ['type', 'experience', 'skill'],
    'type',
  ),
  _BrainFactor(
    'Speed',
    'How fast they resolve, historically.',
    0.62,
    Color(0xFF1D9E75),
    ['fast', 'speed', 'resolution time', 'quick'],
    'speed',
  ),
  _BrainFactor(
    'Station familiarity',
    'Knows this conveyor / workstation.',
    0.55,
    Color(0xFFBA7517),
    ['station', 'conveyor', 'convoyeur', 'workstation', 'poste'],
    'station',
  ),
  _BrainFactor(
    'Load balance',
    'Current workload — avoids overloading.',
    0.70,
    Color(0xFFD4537E),
    ['load', 'workload', 'busy', 'balance'],
    'load',
  ),
  _BrainFactor(
    'Critical record',
    'Track record on critical alerts.',
    0.50,
    Color(0xFFE24B4A),
    ['critical'],
    'critical',
  ),
  _BrainFactor(
    'Reinforcement',
    'Learned bias from accept / reject feedback.',
    0.65,
    Color(0xFF534AB7),
    ['feedback', 'reinforcement', 'adjust', 'learned'],
    'reinforcement',
  ),
];

/// How the commander weighs whether to approve a collaboration and who assists.
const List<_BrainFactor> _kShiftCollabFactors = [
  _BrainFactor(
    'Assistant consensus',
    'Every requested assistant accepted.',
    0.92,
    Color(0xFF378ADD),
    ['accept', 'consensus', 'agreed', 'assistant'],
    'consensus',
  ),
  _BrainFactor(
    'Requester need',
    'How badly the owner needs a hand.',
    0.78,
    Color(0xFF7F77DD),
    ['help', 'request', 'need', 'backup'],
    'need',
  ),
  _BrainFactor(
    'Workload room',
    'The assistant still has capacity to help.',
    0.70,
    Color(0xFFD4537E),
    ['load', 'workload', 'busy', 'capacity'],
    'room',
  ),
  _BrainFactor(
    'Skill overlap',
    'The assistant knows this alert type.',
    0.66,
    Color(0xFF1D9E75),
    ['type', 'skill', 'experience'],
    'skill',
  ),
  _BrainFactor(
    'Same factory',
    'Assistant is in the same plant.',
    0.58,
    Color(0xFFBA7517),
    ['factory', 'plant', 'usine', 'same site'],
    'factory',
  ),
  _BrainFactor(
    'Critical priority',
    'Critical alerts get backup first.',
    0.55,
    Color(0xFFE24B4A),
    ['critical'],
    'critical',
  ),
  _BrainFactor(
    'Commander authority',
    'Can skip PM approval under his command.',
    0.48,
    Color(0xFF534AB7),
    ['approval', 'commander', 'authority', 'pm'],
    'authority',
  ),
];

/// How the commander weighs pulling a supervisor across plants.
const List<_BrainFactor> _kShiftCrossFactors = [
  _BrainFactor(
    'Proximity',
    'Distance from home plant to the alert.',
    0.95,
    Color(0xFF378ADD),
    ['distance', 'km', 'proximity', 'haversine', 'near'],
    'proximity',
  ),
  _BrainFactor(
    'Distance cap',
    'Stays within the shift transfer limit.',
    0.85,
    Color(0xFFE24B4A),
    ['limit', 'cap', 'threshold', 'blocked', 'too far'],
    'cap',
  ),
  _BrainFactor(
    'Roster eligibility',
    'On the active shift roster.',
    0.74,
    Color(0xFF7F77DD),
    ['roster', 'shift', 'rostered'],
    'roster',
  ),
  _BrainFactor(
    'Coverage gap',
    'The target plant is short-handed.',
    0.68,
    Color(0xFFBA7517),
    ['coverage', 'gap', 'short', 'understaffed'],
    'coverage',
  ),
  _BrainFactor(
    'Type skill',
    'Proven on this alert type.',
    0.62,
    Color(0xFF1D9E75),
    ['type', 'skill', 'experience'],
    'skill',
  ),
  _BrainFactor(
    'Availability',
    'Free to take a transfer right now.',
    0.56,
    Color(0xFFD4537E),
    ['available', 'free', 'idle', 'load'],
    'availability',
  ),
  _BrainFactor(
    'Commander authority',
    'Cross-factory transfer is enabled.',
    0.50,
    Color(0xFF1AA8B0),
    ['cross', 'transfer', 'commander', 'authority'],
    'authority',
  ),
];

/// One selectable "mind" of the Shift Commander — a brain visual plus the
/// reasoning factors behind one class of decision (assignments, collaborations,
/// or cross-factory transfers).
class _ShiftBrainCategory {
  final String tab;
  final String slug; // RTDB key: ai_agents/shift/settings/weights/{slug}
  final IconData icon;
  final String brainSubtitle;
  final String description;
  final String coreBottom; // verb shown on the brain core ("DECIDES"…)
  final IconData outIcon;
  final String outTop;
  final String outBottom;
  final Color outColor;
  final String reasoningSubtitle;
  final List<_BrainFactor> factors;
  final bool liveScoring; // true ⇒ the worker reads these weights to score
  const _ShiftBrainCategory({
    required this.tab,
    required this.slug,
    required this.icon,
    required this.brainSubtitle,
    required this.description,
    required this.coreBottom,
    required this.outIcon,
    required this.outTop,
    required this.outBottom,
    required this.outColor,
    required this.reasoningSubtitle,
    required this.factors,
    this.liveScoring = false,
  });
}

// Not const: the per-category [outColor] reads `Sa.*` palette getters.
final List<_ShiftBrainCategory> _kShiftBrains = [
  _ShiftBrainCategory(
    tab: 'Assignments',
    slug: 'assignments',
    liveScoring: true,
    icon: Icons.assignment_ind_outlined,
    brainSubtitle:
        'How the AI weighs every supervisor before it assigns an alert.',
    description:
        'When an alert needs an owner, the commander checks who’s nearby, skilled and free — and remembers who handled similar alerts well — then assigns the best fit automatically.',
    coreBottom: 'DECIDES',
    outIcon: Icons.how_to_reg_outlined,
    outTop: 'Best',
    outBottom: 'supervisor',
    outColor: Sa.green,
    reasoningSubtitle:
        'The seven signals he scores, and how often each drove a recent assignment.',
    factors: _kShiftFactors,
  ),
  _ShiftBrainCategory(
    tab: 'Collaborations',
    slug: 'collaborations',
    icon: Icons.groups_2_outlined,
    brainSubtitle:
        'How the AI decides to approve a collaboration and who assists.',
    description:
        'When a supervisor asks for backup, the commander checks who already agreed, who has room to help and who knows the alert — then approves the collaboration without waiting on a manager.',
    coreBottom: 'APPROVES',
    outIcon: Icons.handshake_outlined,
    outTop: 'Approve',
    outBottom: 'collaboration',
    outColor: Sa.blue,
    reasoningSubtitle:
        'The signals behind every collaboration approval, and how often each fired.',
    factors: _kShiftCollabFactors,
  ),
  _ShiftBrainCategory(
    tab: 'Cross-factory',
    slug: 'crossFactory',
    icon: Icons.swap_horiz,
    brainSubtitle: 'How the AI weighs pulling a supervisor across plants.',
    description:
        'When one plant is short-handed, the commander measures how far each rostered supervisor is, respects the shift distance cap, and transfers only when the help is close and worth it.',
    coreBottom: 'TRANSFERS',
    outIcon: Icons.alt_route,
    outTop: 'Cross-plant',
    outBottom: 'transfer',
    outColor: Sa.amber,
    reasoningSubtitle:
        'The signals behind a cross-factory transfer, and how often each fired.',
    factors: _kShiftCrossFactors,
  ),
];

/// What the commander has learned about one supervisor (reinforcement memory).
class _BrainMemory {
  final String id;
  final String name;
  final int accepted;
  final int rejected;
  final int aborted;
  final int resolved;
  final double adjustment; // rank bias, + favours / - penalises

  const _BrainMemory({
    required this.id,
    required this.name,
    required this.accepted,
    required this.rejected,
    required this.aborted,
    required this.resolved,
    required this.adjustment,
  });

  double get weight =>
      (accepted + rejected + aborted + resolved).toDouble() + adjustment.abs();

  factory _BrainMemory.fromMap(String id, Map row) {
    int n(String k) => (row[k] is num) ? (row[k] as num).round() : 0;
    final rawName = (row['name'] ?? row['supervisorName'] ?? '').toString();
    final accepted = n('accepted');
    final rejected = n('rejected');
    final aborted = n('aborted');
    final resolved = n('resolved');
    double adj;
    if (row['rankAdjustment'] is num) {
      adj = (row['rankAdjustment'] as num).toDouble();
    } else {
      adj = (accepted * 4 + resolved * 2 - rejected * 5 - aborted * 3)
          .toDouble()
          .clamp(-20.0, 20.0);
    }
    final name = rawName.isNotEmpty
        ? rawName
        : (id.length > 6 ? '${id.substring(0, 6)}…' : id);
    return _BrainMemory(
      id: id,
      name: name,
      accepted: accepted,
      rejected: rejected,
      aborted: aborted,
      resolved: resolved,
      adjustment: adj,
    );
  }
}

/// The BRAIN sub-view: cognition core, memory, factors, learned signals, replay.
///
/// The cognition core and the reasoning factors are split into three selectable
/// "minds" — Assignments, Collaborations, Cross-factory transfer — each with its
/// own 3D brain visual and its own weighted reasoning factors. A single shared
/// sub-tab drives both panels so the brain and its factors always agree.
class _ShiftBrainView extends StatefulWidget {
  final List<Map<String, dynamic>> logs;
  final List<_BrainMemory> memory;
  final Color accent;
  final bool enabled;
  const _ShiftBrainView({
    required this.logs,
    required this.memory,
    required this.accent,
    required this.enabled,
  });

  @override
  State<_ShiftBrainView> createState() => _ShiftBrainViewState();
}

class _ShiftBrainViewState extends State<_ShiftBrainView> {
  int _brainTab = 0; // 0=Assignments, 1=Collaborations, 2=Cross-factory

  static const String _kWeightsPath = 'ai_agents/shift/settings/weights';

  // category slug → factor slug → live weight (0..1). Seeded from the factor
  // defaults, kept in sync with RTDB, and the single source the brain visual,
  // the factor bars and the warning checks all read.
  final Map<String, Map<String, double>> _weights = {};
  // Edits not yet flushed to RTDB (keyed 'categorySlug/factorSlug'); they win
  // over incoming stream values so a live drag never fights the echo.
  final Map<String, double> _dirty = {};
  StreamSubscription<DatabaseEvent>? _weightsSub;
  Timer? _writeDebounce;

  @override
  void initState() {
    super.initState();
    for (final c in _kShiftBrains) {
      _weights[c.slug] = {for (final f in c.factors) f.slug: f.weight};
    }
    _weightsSub = FirebaseDatabase.instance.ref(_kWeightsPath).onValue.listen((
      event,
    ) {
      final v = event.snapshot.value;
      if (v is! Map || !mounted) return;
      setState(() {
        v.forEach((catKey, factorMap) {
          if (factorMap is! Map) return;
          final cat = catKey.toString();
          final target = _weights[cat] ??= {};
          factorMap.forEach((slug, val) {
            if (_dirty.containsKey('$cat/$slug')) return; // keep pending edit
            if (val is num) {
              target[slug.toString()] = val.toDouble().clamp(0.0, 1.0);
            }
          });
        });
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _writeDebounce?.cancel();
    if (_dirty.isNotEmpty) _flushWeights(); // best-effort fire-and-forget
    _weightsSub?.cancel();
    super.dispose();
  }

  double _w(String catSlug, String slug) => _weights[catSlug]?[slug] ?? 0.0;

  void _setWeight(String catSlug, String slug, double value) {
    final v = value.clamp(0.0, 1.0);
    setState(() => (_weights[catSlug] ??= {})[slug] = v);
    _dirty['$catSlug/$slug'] = v;
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 350), _flushWeights);
  }

  Future<void> _flushWeights() async {
    if (_dirty.isEmpty) return;
    final batch = Map<String, double>.from(_dirty);
    try {
      await FirebaseDatabase.instance.ref(_kWeightsPath).update(
        <String, Object?>{for (final e in batch.entries) e.key: e.value},
      );
      // Drop only the keys that weren't re-edited mid-flight.
      for (final e in batch.entries) {
        if (_dirty[e.key] == e.value) _dirty.remove(e.key);
      }
    } catch (_) {
      // Leave _dirty intact so the next edit/flush retries.
    }
  }

  void _resetCategory(_ShiftBrainCategory cat) {
    setState(() {
      final m = _weights[cat.slug] ??= {};
      for (final f in cat.factors) {
        m[f.slug] = f.weight;
      }
    });
    for (final f in cat.factors) {
      _dirty['${cat.slug}/${f.slug}'] = f.weight;
    }
    _writeDebounce?.cancel();
    _flushWeights();
  }

  /// Plain-language checks for weightings that would make the commander behave
  /// strangely. Empty ⇒ the current mix is sane.
  List<String> _warningsFor(_ShiftBrainCategory cat) {
    final out = <String>[];
    final vals = [for (final f in cat.factors) _w(cat.slug, f.slug)];
    final avg = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
    if (avg < 0.12) {
      out.add(
        context.tr(
          'Almost every factor is near zero — the commander has little left to weigh, so picks become close to random.',
        ),
      );
    }
    for (final f in cat.factors) {
      if (_w(cat.slug, f.slug) <= 0.02) {
        out.add(
          context.tr(
            '“{label}” is switched off — it no longer sways the decision.',
            {'label': context.tr(f.label)},
          ),
        );
      }
    }
    if (cat.factors.length >= 3) {
      final sorted = [...vals]..sort();
      if (sorted.last >= 0.9 && sorted[sorted.length - 2] <= 0.12) {
        out.add(
          context.tr(
            'One factor dominates everything else — the commander will mostly ignore the rest.',
          ),
        );
      }
    }
    double v(String s) => _w(cat.slug, s);
    switch (cat.slug) {
      case 'assignments':
        if (v('factory') < 0.15) {
          out.add(
            context.tr(
              'Factory fit is near zero — supervisors from any plant score the same, so alerts can land on a distant factory.',
            ),
          );
        }
        if (v('load') < 0.10) {
          out.add(
            context.tr(
              'Load balancing is off — a single supervisor can be piled with every new alert.',
            ),
          );
        }
        break;
      case 'crossFactory':
        if (v('cap') < 0.15) {
          out.add(
            context.tr(
              'Distance cap barely counts — the commander may pull supervisors from far-away plants.',
            ),
          );
        }
        if (v('proximity') < 0.15) {
          out.add(
            context.tr(
              'Proximity barely counts — distant supervisors compete as if they were next door.',
            ),
          );
        }
        break;
      case 'collaborations':
        if (v('consensus') < 0.15) {
          out.add(
            context.tr(
              'Assistant consensus barely counts — collaborations may be approved before everyone agrees.',
            ),
          );
        }
        break;
    }
    final seen = <String>{};
    final dedup = [
      for (final w in out)
        if (seen.add(w)) w,
    ];
    return dedup.take(6).toList();
  }

  void _showWeightWarnings(_ShiftBrainCategory cat, List<String> warnings) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Sa.amber.withValues(alpha: 0.5)),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Sa.amber, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('Check the {tab} weighting', {
                  'tab': context.tr(cat.tab).toLowerCase(),
                }),
                style: Sa.heading(size: 16, color: Sa.text),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'These settings may make the Shift Commander behave in ways you might not expect:',
                ),
                style: Sa.body(size: 12.5, color: Sa.textDim),
              ),
              const SizedBox(height: 14),
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Icon(Icons.circle, size: 7, color: Sa.amber),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          w,
                          style: Sa.body(size: 12.5, color: Sa.text),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetCategory(cat);
            },
            child: Text(
              context.tr('Reset to defaults'),
              style: TextStyle(color: Sa.amber, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.tr('Keep anyway'),
              style: TextStyle(color: Sa.muted),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.logs;
    final memory = widget.memory;
    final accent = widget.accent;
    final enabled = widget.enabled;

    final cat = _kShiftBrains[_brainTab];
    final factors = cat.factors;
    final brainTabs = [for (final b in _kShiftBrains) b.tab];
    final brainIcons = [for (final b in _kShiftBrains) b.icon];

    final confs = <double>[];
    for (final l in logs) {
      final c = l['confidence'];
      if (c is num) {
        confs.add(c.toDouble() > 1 ? c.toDouble() / 100 : c.toDouble());
      }
    }
    final avgConf = confs.isEmpty
        ? 0.0
        : confs.reduce((a, b) => a + b) / confs.length;
    final learned = memory.where((m) => m.adjustment.abs() >= 0.5).length;

    final fireCounts = <int>[for (final _ in factors) 0];
    for (final l in logs) {
      final r = (l['reason'] ?? '').toString().toLowerCase();
      for (var i = 0; i < factors.length; i++) {
        if (factors[i].keys.any((k) => r.contains(k))) fireCounts[i]++;
      }
    }
    final maxFire = fireCounts.isEmpty ? 0 : fireCounts.reduce(math.max);

    void selectBrain(int i) => setState(() => _brainTab = i);

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
                title: context.tr('INSIDE THE COMMANDER’S MIND'),
                subtitle: context.tr(cat.brainSubtitle),
                accent: accent,
                trailing: GlowChip(
                  label: context.tr('COGNITION'),
                  color: accent,
                  icon: Icons.bolt,
                  pulse: enabled,
                ),
              ),
              const SizedBox(height: 12),
              _SegTabs(
                tabs: brainTabs,
                icons: brainIcons,
                index: _brainTab,
                accent: accent,
                onChanged: selectBrain,
              ),
              const SizedBox(height: 12),
              _CortexHero(
                accent: accent,
                animate: enabled,
                inputs: [
                  for (var i = 0; i < factors.length; i++)
                    _CortexInput(
                      factors[i].label,
                      factors[i].color,
                      _w(cat.slug, factors[i].slug),
                      maxFire == 0
                          ? 0.25
                          : (fireCounts[i] / maxFire).clamp(0.0, 1.0),
                    ),
                ],
                inHeader: 'WHAT IT WEIGHS',
                coreTop: 'WEIGHS',
                coreBottom: cat.coreBottom,
                outIcon: cat.outIcon,
                outTop: cat.outTop,
                outBottom: cat.outBottom,
                outColor: cat.outColor,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(cat.description),
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
                icon: Icons.memory,
                title: context.tr('WHAT HE KNOWS'),
                subtitle: context.tr(
                  'The memory the commander carries into each decision.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SaStatTile(
                    label: context.tr('Supervisors profiled'),
                    value: '${memory.length}',
                    icon: Icons.badge_outlined,
                    color: accent,
                  ),
                  SaStatTile(
                    label: context.tr('Decisions in memory'),
                    value: '${logs.length}',
                    icon: Icons.history_toggle_off,
                    color: Sa.blue,
                  ),
                  SaStatTile(
                    label: context.tr('Signals learned'),
                    value: '$learned',
                    icon: Icons.auto_graph,
                    color: Sa.green,
                  ),
                  SaStatTile(
                    label: context.tr('Avg confidence'),
                    value: '${(avgConf * 100).round()}%',
                    icon: Icons.speed,
                    color: Sa.amber,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Builder(
          builder: (context) {
            final warnings = _warningsFor(cat);
            return GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SaSectionHeader(
                    icon: Icons.tune,
                    title: context.tr('REASONING FACTORS'),
                    subtitle: context.tr(cat.reasoningSubtitle),
                    accent: accent,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (warnings.isNotEmpty) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showWeightWarnings(cat, warnings),
                            child: GlowChip(
                              label: warnings.length > 1
                                  ? context.tr('{count} WARNINGS', {
                                      'count': '${warnings.length}',
                                    })
                                  : context.tr('{count} WARNING', {
                                      'count': '${warnings.length}',
                                    }),
                              color: Sa.amber,
                              icon: Icons.warning_amber_rounded,
                              pulse: true,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _ResetWeightsButton(onReset: () => _resetCategory(cat)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.drag_indicator, size: 15, color: Sa.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cat.liveScoring
                              ? context.tr(
                                  'Drag any bar to retune — changes feed the Shift Commander’s live assignment scoring instantly.',
                                )
                              : context.tr(
                                  'Drag any bar to retune — changes save to the Shift Commander instantly.',
                                ),
                          style: Sa.body(size: 11, color: Sa.textDim),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SegTabs(
                    tabs: brainTabs,
                    icons: brainIcons,
                    index: _brainTab,
                    accent: accent,
                    onChanged: selectBrain,
                  ),
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _WeightWarningBanner(
                      message: warnings.first,
                      extra: warnings.length - 1,
                      onTap: () => _showWeightWarnings(cat, warnings),
                    ),
                  ],
                  const SizedBox(height: 6),
                  for (var i = 0; i < factors.length; i++)
                    _BrainFactorRow(
                      factor: factors[i],
                      value: _w(cat.slug, factors[i].slug),
                      fired: fireCounts[i],
                      maxFired: maxFire,
                      onChanged: (v) =>
                          _setWeight(cat.slug, factors[i].slug, v),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.model_training,
                title: context.tr('LEARNED SIGNALS'),
                subtitle: context.tr(
                  'Per-supervisor reinforcement from accepted, rejected and resolved assignments.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 12),
              if (memory.isEmpty)
                SaEmptyState(
                  icon: Icons.school_outlined,
                  title: context.tr('Nothing learned yet'),
                  message: context.tr(
                    'Once supervisors accept or reject AI assignments, the commander starts tuning their rank here.',
                  ),
                  accent: accent,
                )
              else
                ...memory
                    .take(12)
                    .map((m) => _BrainMemoryTile(memory: m, accent: accent)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.alt_route,
                title: context.tr('THOUGHT REPLAY'),
                subtitle: context.tr(
                  'Recent decisions — the situation, the pick, the confidence, the reasoning.',
                ),
                accent: accent,
              ),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                SaEmptyState(
                  icon: Icons.nights_stay_outlined,
                  title: context.tr('No thoughts yet'),
                  message: context.tr(
                    'When a shift with AI Commander goes live, each decision replays here.',
                  ),
                  accent: accent,
                )
              else
                ...logs
                    .take(8)
                    .map((l) => _ThoughtCard(log: l, accent: accent)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// THE CORTEX — a premium, self-explanatory picture of an agent's mind.
//
// The signals it weighs (left, labelled — sized by influence) flow as glowing
// axons into a slowly-rotating anatomical 3D brain: two hemispheres traced by
// meandering gyri fold-lines around glassy lobe volumes, split by a
// longitudinal fissure, with a striated cerebellum, a tapering brainstem,
// interior neural dust and synaptic flashes. The brain integrates the signals
// in a luminous nucleus and emits one confident decision (right). Thought-
// pulses travel each axon; the busier a signal has been, the faster and
// brighter it fires — so a glance reads "what it stores" and "how it thinks".
//
// Pure vector motion graphics — no SVG assets, no platform deps — painted in a
// handful of depth-banded path calls behind a RepaintBoundary. Shared by the
// Shift Commander and Predictive Core brain tabs.
// ─────────────────────────────────────────────────────────────────────────

/// A point in the brain mesh (model space).
class _P3 {
  final double x, y, z;
  const _P3(this.x, this.y, this.z);
}

/// A projected mesh point (screen space + camera depth + perspective scale).
class _Proj {
  final double x, y, z, scale;
  const _Proj(this.x, this.y, this.z, this.scale);
}

/// One weighted signal the agent reads. [weight] (0..1) sizes the node and its
/// axon; [activity] (0..1) drives how fast and bright its thought-pulses fire.
class _CortexInput {
  final String label;
  final Color color;
  final double weight;
  final double activity;
  const _CortexInput(this.label, this.color, this.weight, this.activity);
}

/// The hero visual: a rotating 3D mesh brain fed by labelled neuro-links and
/// emitting one decision. Fully self-contained — owns one slow animation clock.
class _CortexHero extends StatefulWidget {
  final Color accent;
  final bool animate;
  final List<_CortexInput> inputs;
  final String inHeader;
  final String coreTop;
  final String coreBottom;
  final IconData outIcon;
  final String outTop;
  final String outBottom;
  final Color outColor;

  const _CortexHero({
    required this.accent,
    required this.animate,
    required this.inputs,
    required this.inHeader,
    required this.coreTop,
    required this.coreBottom,
    required this.outIcon,
    required this.outTop,
    required this.outBottom,
    required this.outColor,
  });

  @override
  State<_CortexHero> createState() => _CortexHeroState();
}

class _CortexHeroState extends State<_CortexHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_P3> _nodes;
  late final List<List<int>> _edges;
  late final List<_P3> _dust;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _buildMesh();
    if (widget.animate) {
      _c.repeat();
    } else {
      _c.value = 0.08;
    }
  }

  // An anatomical brain, not a lat/long globe. Each cerebral hemisphere is
  // traced by sagittal gyri fold-lines that meander front→back over the
  // cortex (temporal-lobe bulge, fuller occiput, frontal taper, flattened
  // underside, slight frontal-up tilt), split by a visible longitudinal
  // fissure with a corpus-callosum seam glimpsed inside it. A striated
  // cerebellum tucks under the occipital lobes and a tapering brainstem
  // descends toward the podium. Emitted once as polyline strips plus
  // interior "neural dust"; projected every frame.
  void _buildMesh() {
    final verts = <_P3>[];
    final edges = <List<int>>[];
    // Anisotropic skull proportions — longer than wide, wider than tall —
    // applied at emission so every structure shares them.
    const sx = 1.55, sz = 1.30;

    // Model is authored y-up; screen y grows downward, so emission negates y.
    void strip(List<_P3> pts) {
      final base = verts.length;
      for (final p in pts) {
        verts.add(_P3(p.x * sx, -p.y, p.z * sz));
      }
      for (var k = 0; k < pts.length - 1; k++) {
        edges.add([base + k, base + k + 1]);
      }
    }

    // Soft-clamp the underside so the cerebrum sits flat like a real brain.
    double basePlane(double y) => y < -0.40 ? -0.40 + (y + 0.40) * 0.5 : y;

    // ── cerebral hemispheres: sagittal gyri fold-lines, crown → underside
    const foldLines = 17;
    const foldSteps = 46;
    for (final s in const [-1.0, 1.0]) {
      for (var g = 0; g < foldLines; g++) {
        final beta0 = (0.04 + 0.72 * (g / (foldLines - 1))) * math.pi;
        // Stagger the pole approach per line so the endpoints never form a
        // hard ring where every fold stops at once.
        final phi0 = 0.02 + 0.022 * (0.5 + 0.5 * math.sin(g * 2.7));
        final pts = <_P3>[];
        for (var k = 0; k <= foldSteps; k++) {
          final phi =
              (phi0 + (1 - 2 * phi0) * (k / foldSteps)) * math.pi; // front→back
          final sinP = math.sin(phi);
          // Gyral meander: the fold snakes sideways as it travels back, so
          // neighbouring lines interlock like real gyri instead of gridding.
          final beta =
              beta0 +
              sinP *
                  (0.11 * math.sin(phi * (5 + g % 3) + g * 1.9) +
                      0.05 * math.sin(phi * 11 + g * 3.7));
          // Cortical ridges: bumpy radius so sulci dip between the lines.
          final ridge =
              1.0 +
              0.045 * math.sin(phi * 9 + g * 2.6) +
              0.028 * math.sin(phi * 17 + g * 1.3 + beta * 3);
          final dTemp1 = (phi - 0.40 * math.pi) / 0.42;
          final dTemp2 = (beta - 0.60 * math.pi) / 0.46;
          final temporal = 0.24 * math.exp(-dTemp1 * dTemp1 - dTemp2 * dTemp2);
          final dOcc = (phi - 0.80 * math.pi) / 0.50;
          final occiput = 0.07 * math.exp(-dOcc * dOcc);
          final dFro = (phi - 0.10 * math.pi) / 0.35;
          final frontal = -0.06 * math.exp(-dFro * dFro);
          final lat = 0.50 * ridge * (1 + temporal + occiput + frontal);
          final z = math.cos(phi) * 0.94;
          final pinch = math.sqrt(sinP); // folds converge at the poles
          final x = s * (0.055 * pinch + sinP * math.sin(beta) * lat);
          var y = basePlane(sinP * math.cos(beta) * 0.88 * ridge);
          y += 0.06 * z + 0.04; // frontal-up tilt; float a touch high
          pts.add(_P3(x, y, z));
        }
        strip(pts);
      }
    }

    // ── corpus-callosum seam, glimpsed through the longitudinal fissure
    {
      final pts = <_P3>[];
      for (var k = 0; k <= 30; k++) {
        final phi = (0.10 + 0.80 * (k / 30)) * math.pi;
        final z = math.cos(phi) * 0.92;
        final y =
            math.sin(phi) * 0.72 -
            0.05 +
            0.03 * math.sin(phi * 9) +
            0.06 * z +
            0.04;
        pts.add(_P3(0, y, z));
      }
      strip(pts);
    }

    // ── cerebellum: two lobes of fine horizontal foliation striations
    const cbLines = 6;
    const cbSteps = 24;
    for (final s in const [-1.0, 1.0]) {
      for (var g = 0; g < cbLines; g++) {
        final theta = (0.22 + 0.56 * (g / (cbLines - 1))) * math.pi;
        final ringR = math.sin(theta);
        final pts = <_P3>[];
        for (var k = 0; k <= cbSteps; k++) {
          final a = math.pi * (0.5 + k / cbSteps); // back-facing half sweep
          final wob = 1.0 + 0.045 * math.sin(a * 9 + g * 2.1);
          pts.add(
            _P3(
              s * 0.17 + math.sin(a) * ringR * 0.22 * wob,
              -0.66 + math.cos(theta) * 0.17,
              -0.57 + math.cos(a) * ringR * 0.26 * wob,
            ),
          );
        }
        strip(pts);
      }
    }

    // ── brainstem: a tapering column descending toward the podium
    const stemLevels = 5;
    _P3 stemAt(double f, double a) {
      final rr = 0.145 - 0.05 * f;
      // Ring plane tilted perpendicular to the descending stem axis.
      final ring = math.sin(a) * rr * 0.8;
      return _P3(
        math.cos(a) * rr,
        -0.34 - 0.50 * f + ring * 0.38,
        -0.30 + 0.22 * f + ring,
      );
    }

    for (var g = 0; g < stemLevels; g++) {
      final f = g / (stemLevels - 1);
      strip([for (var k = 0; k <= 14; k++) stemAt(f, k / 14 * 2 * math.pi)]);
    }
    for (var k = 0; k < 4; k++) {
      final a = k / 4 * 2 * math.pi + 0.4;
      strip([
        for (var g = 0; g < stemLevels; g++) stemAt(g / (stemLevels - 1), a),
      ]);
    }

    // ── interior neural dust: sparse thoughts drifting inside the volume
    final rnd = math.Random(7);
    final dust = <_P3>[];
    while (dust.length < 42) {
      final x = (rnd.nextDouble() * 2 - 1) * 0.60;
      final y = (rnd.nextDouble() * 2 - 1) * 0.52 + 0.14;
      final z = (rnd.nextDouble() * 2 - 1) * 0.88;
      final ex = x / 0.60, ey = (y - 0.14) / 0.52, ez = z / 0.88;
      if (ex * ex + ey * ey + ez * ez < 1) {
        dust.add(_P3(x * sx, -y, z * sz));
      }
    }

    _nodes = verts;
    _edges = edges;
    _dust = dust;
  }

  @override
  void didUpdateWidget(covariant _CortexHero old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0.08;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        final showLabels = cons.maxWidth >= 540;
        return RepaintBoundary(
          child: SizedBox(
            height: 348,
            width: double.infinity,
            child: CustomPaint(
              painter: _CortexPainter(
                tick: _c,
                accent: widget.accent,
                inputs: [
                  for (final inp in widget.inputs)
                    _CortexInput(
                      ctx.tr(inp.label),
                      inp.color,
                      inp.weight,
                      inp.activity,
                    ),
                ],
                nodes: _nodes,
                edges: _edges,
                dust: _dust,
                showLabels: showLabels,
                dim: widget.animate ? 1.0 : 0.5,
                inHeader: ctx.tr(widget.inHeader),
                coreTop: ctx.tr(widget.coreTop),
                coreBottom: ctx.tr(widget.coreBottom),
                outIcon: widget.outIcon,
                outTop: ctx.tr(widget.outTop),
                outBottom: ctx.tr(widget.outBottom),
                outHeader: ctx.tr('DECISION'),
                outColor: widget.outColor,
                isDark: Sa.isDark,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CortexPainter extends CustomPainter {
  final Animation<double> tick;
  final Color accent;
  final List<_CortexInput> inputs;
  final List<_P3> nodes;
  final List<List<int>> edges;
  final List<_P3> dust;
  final bool showLabels;
  final double dim;
  final String inHeader;
  final String coreTop;
  final String coreBottom;
  final IconData outIcon;
  final String outTop;
  final String outBottom;
  final String outHeader;
  final Color outColor;
  final bool isDark;

  _CortexPainter({
    required this.tick,
    required this.accent,
    required this.inputs,
    required this.nodes,
    required this.edges,
    required this.dust,
    required this.showLabels,
    required this.dim,
    required this.inHeader,
    required this.coreTop,
    required this.coreBottom,
    required this.outIcon,
    required this.outTop,
    required this.outBottom,
    required this.outHeader,
    required this.outColor,
    required this.isDark,
  }) : super(repaint: tick);

  void _text(
    Canvas c,
    String s,
    Offset at,
    Color col,
    double size, {
    bool center = false,
    bool rightAlign = false,
    double maxW = 240,
    FontWeight weight = FontWeight.w600,
    bool mono = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: mono
            ? Sa.mono(size: size, color: col, weight: weight)
            : Sa.body(size: size, color: col, weight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    Offset o;
    if (center) {
      o = at - Offset(tp.width / 2, tp.height / 2);
    } else if (rightAlign) {
      o = at - Offset(tp.width, tp.height / 2);
    } else {
      o = at - Offset(0, tp.height / 2);
    }
    tp.paint(c, o);
  }

  void _glyph(Canvas c, IconData icon, Offset center, Color col, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: col,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final t = tick.value;
    final rot = t * 2 * math.pi; // drives ring arcs and pulse phases
    // Museum-hologram sway: rock ±~48° around the lateral profile instead of
    // spinning 360°, so the anatomy always reads and the fold-lines never
    // collapse into a radial fan at the frontal/occipital poles.
    final yaw = math.pi / 2 + 0.70 * math.sin(t * 4 * math.pi);
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 5); // nucleus pulse

    final labelW = showLabels ? w * 0.27 : 0.0;
    final nodeX = showLabels ? labelW + 16 : w * 0.085;
    final cx = showLabels ? w * 0.60 : w * 0.52;
    final cy = h * 0.43; // brain floats high; the podium owns the lower third
    final r = math.min((cx - nodeX) * 0.78, h * 0.30);
    const orbR = 15.0;
    final ox = w - (showLabels ? 56.0 : 38.0);
    final oy = cy;
    final n = inputs.length;
    const topPad = 26.0;
    final inputBottom = h * 0.72;

    // ── Iconic hologram palette — electric-blue left lobe, molten-orange
    // right lobe: the reference picture, rebuilt as live 3D geometry. Front
    // bands glow, back bands sink into depth.
    const blue = Color(0xFF38BDF8);
    const orange = Color(0xFFFB923C);
    Color nearOf(Color base) =>
        isDark ? Color.lerp(base, Colors.white, 0.34)! : base;
    Color farOf(Color base) => isDark
        ? Color.lerp(base, const Color(0xFF071226), 0.55)!
        : Color.lerp(base, Colors.white, 0.60)!;
    final blueNear = nearOf(blue), blueFar = farOf(blue);
    final orangeNear = nearOf(orange), orangeFar = farOf(orange);

    // Podium + beam geometry.
    final podY = h * 0.88;
    final podRx = r * 1.22;
    final podRy = podRx * 0.24;
    final beamTop = cy + r * 0.86;
    final beamW = r * 0.52;

    // ── soft depth vignette behind the brain
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.55,
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), r * 1.55, [
          accent.withValues(alpha: 0.10 * dim),
          accent.withValues(alpha: 0.0),
        ]),
    );

    // ── holographic tech podium under the floating brain
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, podY), width: podRx * 2.6, height: podRy * 3.0),
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, podY), podRx * 1.3, [
          accent.withValues(alpha: 0.16 * dim),
          accent.withValues(alpha: 0.0),
        ]),
    );
    var ringI = 0;
    for (final f in const [1.0, 0.72, 0.46]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, podY), width: podRx * 2 * f, height: podRy * 2 * f),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 - ringI * 0.2
          ..color = accent.withValues(alpha: (0.5 - ringI * 0.1) * dim),
      );
      ringI++;
    }
    for (var i = 0; i < 28; i++) {
      final a = i / 28 * math.pi * 2 + t * math.pi * 2 * 0.1;
      final inner =
          Offset(cx + math.cos(a) * podRx * 0.5, podY + math.sin(a) * podRy * 0.5);
      final outer = Offset(cx + math.cos(a) * podRx, podY + math.sin(a) * podRy);
      canvas.drawLine(inner, outer,
          Paint()..color = accent.withValues(alpha: 0.10 * dim)..strokeWidth = 1);
    }
    canvas.drawCircle(
        Offset(cx, podY), 9, Paint()..color = accent.withValues(alpha: 0.3 * dim));
    canvas.drawCircle(
        Offset(cx, podY), 4, Paint()..color = accent.withValues(alpha: 0.9 * dim));

    // ── energy beams rising from the podium into the brain
    final cone = Path()
      ..moveTo(cx - beamW * 0.16, podY)
      ..lineTo(cx + beamW * 0.16, podY)
      ..lineTo(cx + beamW, beamTop)
      ..lineTo(cx - beamW, beamTop)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.linear(Offset(cx, podY), Offset(cx, beamTop), [
          accent.withValues(alpha: 0.22 * dim),
          accent.withValues(alpha: 0.0),
        ]),
    );
    for (var i = 0; i < 3; i++) {
      final off = (i - 1) * beamW * 0.5;
      final pulse = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * math.pi * 4 + i * 1.7));
      canvas.drawLine(
        Offset(cx + off * 0.2, podY),
        Offset(cx + off, beamTop),
        Paint()
          ..color = accent.withValues(alpha: 0.22 * pulse * dim)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── rising energy particles (blue/orange) inside the beam column
    for (var i = 0; i < 24; i++) {
      final seed = i * 0.1373;
      final ph = (t * 0.55 + seed) % 1.0;
      final sway = math.sin((seed + ph) * math.pi * 2) * beamW * 0.8;
      final px = cx + sway * (0.3 + ph * 0.7);
      final py = podY - ph * (podY - (cy - r * 0.2));
      final fade = math.sin(ph * math.pi);
      final col = i.isEven ? blueNear : orangeNear;
      canvas.drawCircle(Offset(px, py), 1.0 + 1.4 * fade,
          Paint()..color = col.withValues(alpha: 0.55 * fade * dim));
    }

    // ── input axons (signal → core), drawn under the brain
    final paths = <Path>[];
    final nodeYs = <double>[];
    for (var i = 0; i < n; i++) {
      final frac = n == 1 ? 0.5 : i / (n - 1);
      final ny = topPad + (inputBottom - topPad) * frac;
      nodeYs.add(ny);
      final node = Offset(nodeX, ny);
      final entry = Offset(cx - r * 0.66, cy + (ny - cy) * 0.34);
      final midX = (node.dx + entry.dx) / 2;
      final p = Path()
        ..moveTo(node.dx, node.dy)
        ..cubicTo(midX, node.dy, midX, entry.dy, entry.dx, entry.dy);
      paths.add(p);
      final inp = inputs[i];
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + 1.5 * inp.weight
          ..strokeCap = StrokeCap.round
          ..color = inp.color.withValues(
            alpha: (0.13 + 0.22 * inp.weight) * dim,
          ),
      );
    }

    // ── 3D anatomical brain (hemisphere-colored, rotated/tilted/projected)
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    const ax = -0.32; // viewed slightly from above: crown + fissure visible
    final cosX = math.cos(ax), sinX = math.sin(ax);
    const focal = 3.4;
    _Proj project(_P3 p) {
      final x = p.x * cosY + p.z * sinY;
      var z = -p.x * sinY + p.z * cosY;
      final y = p.y * cosX - z * sinX;
      z = p.y * sinX + z * cosX;
      final scale = focal / (focal - z);
      return _Proj(cx + x * scale * r, cy + y * scale * r, z, scale);
    }

    final proj = [for (final p in nodes) project(p)];
    final midNear = Color.lerp(blueNear, orangeNear, 0.5)!;
    final midFar = Color.lerp(blueFar, orangeFar, 0.5)!;
    // Model z now spans ±1.27 (skull proportions); normalize depth by 1.25.
    double depthOf(double z) => (((z / 1.25) + 1) / 2).clamp(0.0, 1.0);

    // translucent lobe volumes — glassy mass the fold-lines wrap around
    final volumes = [
      (project(const _P3(-0.42, -0.17, 0.0)), blue),
      (project(const _P3(0.42, -0.17, 0.0)), orange),
    ]..sort((a, b) => a.$1.z.compareTo(b.$1.z)); // far lobe first
    for (final (vp, vc) in volumes) {
      final vr = r * 0.62 * vp.scale;
      canvas.drawCircle(
        Offset(vp.x, vp.y),
        vr,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(vp.x, vp.y),
            vr,
            [
              vc.withValues(alpha: (isDark ? 0.13 : 0.10) * dim),
              vc.withValues(alpha: 0.02 * dim),
              vc.withValues(alpha: 0.0),
            ],
            [0.0, 0.7, 1.0],
          ),
      );
    }

    // interior neural dust — faint thoughts drifting with the rotation
    for (final d in dust) {
      final p = project(d);
      final dn = depthOf(p.z);
      final col = d.x < -0.09 ? blueNear : (d.x > 0.09 ? orangeNear : midNear);
      canvas.drawCircle(
        Offset(p.x, p.y),
        0.7 + 0.9 * dn,
        Paint()..color = col.withValues(alpha: (0.08 + 0.26 * dn) * dim),
      );
    }

    const bands = 6;
    // Split by hemisphere (model-space x) so the left lobe stays blue and the
    // right lobe orange as the whole mesh rotates through depth; midline
    // structures (fissure seam, brainstem) blend the two minds.
    final leftBands = List.generate(bands, (_) => Path());
    final rightBands = List.generate(bands, (_) => Path());
    final midBands = List.generate(bands, (_) => Path());
    for (final e in edges) {
      final a = proj[e[0]];
      final b = proj[e[1]];
      var bi = (depthOf((a.z + b.z) / 2) * bands).floor();
      if (bi < 0) bi = 0;
      if (bi >= bands) bi = bands - 1;
      final mx = (nodes[e[0]].x + nodes[e[1]].x) / 2;
      final target = mx < -0.09
          ? leftBands
          : (mx > 0.09 ? rightBands : midBands);
      target[bi]
        ..moveTo(a.x, a.y)
        ..lineTo(b.x, b.y);
    }
    for (var bi = 0; bi < bands; bi++) {
      final f = bands == 1 ? 1.0 : bi / (bands - 1);
      final sw = 0.55 + 0.85 * f;
      final al = (0.10 + 0.52 * f) * dim;
      void band(Path path, Color far, Color near) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw
            ..isAntiAlias = true
            ..color = (Color.lerp(far, near, f) ?? near).withValues(alpha: al),
        );
      }

      band(leftBands[bi], blueFar, blueNear);
      band(rightBands[bi], orangeFar, orangeNear);
      band(midBands[bi], midFar, midNear);
    }

    // bright sparkle on the closest vertices (hemisphere-tinted)
    for (var i = 0; i < proj.length; i++) {
      final p = proj[i];
      final dn = depthOf(p.z);
      if (dn > 0.78) {
        final col = nodes[i].x < -0.09
            ? blueNear
            : (nodes[i].x > 0.09 ? orangeNear : midNear);
        canvas.drawCircle(
          Offset(p.x, p.y),
          0.7 + 1.0 * ((dn - 0.78) / 0.22),
          Paint()..color = col.withValues(alpha: 0.5 * dn * dim),
        );
      }
    }

    // synaptic firing — brief flashes travelling the cortex
    for (var k = 0; k < 10; k++) {
      final cyc = t * 16 + k * 0.63;
      final win = cyc.floor();
      final ph = cyc - win;
      final vi = ((win * 131 + k * 379) & 0x7fffffff) % nodes.length;
      final p = proj[vi];
      final dn = depthOf(p.z);
      if (dn < 0.45) continue;
      final flash = math.sin(ph * math.pi);
      final col = nodes[vi].x < -0.09
          ? blueNear
          : (nodes[vi].x > 0.09 ? orangeNear : midNear);
      final fr = 1.1 + 2.1 * flash;
      canvas.drawCircle(
        Offset(p.x, p.y),
        fr + 2.6,
        Paint()..color = col.withValues(alpha: 0.15 * flash * dn * dim),
      );
      canvas.drawCircle(
        Offset(p.x, p.y),
        fr,
        Paint()..color = col.withValues(alpha: 0.6 * flash * dn * dim),
      );
    }

    // inner nucleus glow (where the two minds meet)
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.42 * (0.85 + 0.15 * breathe),
      Paint()
        ..color = midNear.withValues(alpha: (0.05 + 0.05 * breathe) * dim),
    );

    // integration rings — one faint full ring, one sweeping arc
    canvas.drawCircle(
      Offset(cx, cy),
      r + 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.14 * dim),
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r + 7),
      rot,
      math.pi * 1.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.5 * dim),
    );

    // ── core nucleus label (legible disc over the busy mesh)
    canvas.drawCircle(
      Offset(cx, cy),
      23,
      Paint()..color = Sa.bg.withValues(alpha: 0.58),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      23,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.55 * dim),
    );
    _text(
      canvas,
      coreTop,
      Offset(cx, cy - 6),
      Sa.text,
      8.5,
      center: true,
      mono: true,
      weight: FontWeight.w700,
      maxW: 60,
    );
    _text(
      canvas,
      coreBottom,
      Offset(cx, cy + 6),
      accent,
      8,
      center: true,
      mono: true,
      weight: FontWeight.w700,
      maxW: 60,
    );

    // ── input nodes, labels and travelling thought-pulses
    for (var i = 0; i < n; i++) {
      final inp = inputs[i];
      final ny = nodeYs[i];
      final node = Offset(nodeX, ny);
      final nr = 3.2 + 4.2 * inp.weight;
      canvas.drawCircle(
        node,
        nr + 4,
        Paint()
          ..color = inp.color.withValues(
            alpha: (0.10 + 0.28 * inp.activity) * dim,
          ),
      );
      canvas.drawCircle(
        node,
        nr,
        Paint()..color = inp.color.withValues(alpha: 0.85 * dim),
      );
      canvas.drawCircle(
        node,
        nr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = inp.color.withValues(alpha: 0.9 * dim),
      );
      if (showLabels) {
        _text(
          canvas,
          inp.label,
          Offset(nodeX - 13, ny),
          Sa.textDim,
          10.5,
          rightAlign: true,
          maxW: labelW - 16,
          weight: FontWeight.w500,
        );
      }
      final metrics = paths[i].computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final m = metrics.first;
        final sp = 0.5 + inp.activity * 1.5;
        final count = inp.activity > 0.55 ? 2 : 1;
        for (var k = 0; k < count; k++) {
          final ph = (t * 6 * sp + i * 0.13 + k * 0.5) % 1.0;
          final tan = m.getTangentForOffset(m.length * ph);
          if (tan == null) continue;
          final pr = 1.5 + 1.4 * inp.activity;
          canvas.drawCircle(
            tan.position,
            pr + 2,
            Paint()..color = inp.color.withValues(alpha: 0.18 * dim),
          );
          canvas.drawCircle(
            tan.position,
            pr,
            Paint()
              ..color = inp.color.withValues(
                alpha: (0.45 + 0.5 * inp.activity) * dim,
              ),
          );
        }
      }
    }

    // ── input column header
    if (showLabels) {
      _text(
        canvas,
        inHeader,
        Offset(nodeX - 13, 15),
        Sa.muted,
        8.5,
        rightAlign: true,
        mono: true,
        weight: FontWeight.w700,
        maxW: labelW,
      );
    }

    // ── output: connector, travelling pulse, arrowhead, decision orb, label
    final rim = Offset(cx + r * 0.62, cy);
    final orbCenter = Offset(ox, oy);
    final approach = orbCenter - const Offset(orbR + 3, 0);
    canvas.drawLine(
      rim,
      approach,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = outColor.withValues(alpha: 0.42 * dim),
    );
    final op = (t * 6) % 1.0;
    final opp = Offset.lerp(rim, approach, op)!;
    canvas.drawCircle(
      opp,
      2.6,
      Paint()..color = outColor.withValues(alpha: 0.85 * dim),
    );
    final ah = Path()
      ..moveTo(orbCenter.dx - orbR - 1, oy)
      ..lineTo(orbCenter.dx - orbR - 8, oy - 4)
      ..lineTo(orbCenter.dx - orbR - 8, oy + 4)
      ..close();
    canvas.drawPath(ah, Paint()..color = outColor.withValues(alpha: 0.6 * dim));
    canvas.drawCircle(
      orbCenter,
      orbR + 8,
      Paint()
        ..color = outColor.withValues(alpha: (0.10 + 0.12 * breathe) * dim),
    );
    canvas.drawCircle(
      orbCenter,
      orbR,
      Paint()
        ..shader = ui.Gradient.radial(orbCenter, orbR, [
          outColor.withValues(alpha: 0.95 * dim),
          outColor.withValues(alpha: 0.55 * dim),
        ]),
    );
    canvas.drawCircle(
      orbCenter,
      orbR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = outColor,
    );
    _glyph(canvas, outIcon, orbCenter, Sa.onAccent, 16);
    final outMaxW = (w - ox) * 2 - 8;
    _text(
      canvas,
      outTop,
      Offset(ox, oy + orbR + 14),
      Sa.text,
      10,
      center: true,
      weight: FontWeight.w600,
      maxW: outMaxW,
    );
    _text(
      canvas,
      outBottom,
      Offset(ox, oy + orbR + 27),
      Sa.muted,
      9,
      center: true,
      maxW: outMaxW,
    );
    if (showLabels) {
      _text(
        canvas,
        outHeader,
        Offset(ox, 15),
        Sa.muted,
        8.5,
        center: true,
        mono: true,
        weight: FontWeight.w700,
        maxW: 120,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CortexPainter old) =>
      old.accent != accent ||
      old.inputs != inputs ||
      old.dim != dim ||
      old.showLabels != showLabels ||
      old.outColor != outColor ||
      old.isDark != isDark;
}

/// A reasoning factor with a draggable influence bar and recent firing count.
///
/// Dragging the bar changes [value] (0..1) and reports it through [onChanged];
/// the parent persists it live to the Shift Commander. The percentage and the
/// fill follow the live value so the edit reads back immediately.
class _BrainFactorRow extends StatelessWidget {
  final _BrainFactor factor;
  final double value;
  final int fired;
  final int maxFired;
  final ValueChanged<double> onChanged;
  const _BrainFactorRow({
    required this.factor,
    required this.value,
    required this.fired,
    required this.maxFired,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final influence = value.clamp(0.0, 1.0);
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
                  color: factor.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  factor.label,
                  style: Sa.body(size: 13, color: Sa.text),
                ),
              ),
              Text(
                '${(influence * 100).round()}% weight',
                style: Sa.mono(size: 11, color: factor.color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              factor.desc,
              style: Sa.body(size: 11, color: Sa.textDim),
            ),
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Row(
              children: [
                Expanded(
                  child: _WeightSlider(
                    value: influence,
                    color: factor.color,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 56,
                  child: Text(
                    fired > 0 ? 'fired $fired×' : 'idle',
                    textAlign: TextAlign.right,
                    style: Sa.mono(
                      size: 10,
                      color: fired > 0 ? factor.color : Sa.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A self-contained horizontal drag slider styled to match the factor bars:
/// a rounded track, a colored fill and a grabbable thumb. Tap or drag anywhere
/// on the track to set the value.
class _WeightSlider extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final ValueChanged<double> onChanged;
  const _WeightSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        final w = cons.maxWidth;
        void emit(double dx) =>
            onChanged((dx / (w <= 0 ? 1 : w)).clamp(0.0, 1.0));
        final fillW = (w * value).clamp(0.0, w);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => emit(d.localPosition.dx),
          onHorizontalDragStart: (d) => emit(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => emit(d.localPosition.dx),
          child: SizedBox(
            height: 20,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // track
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Sa.panelSolid,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                // fill
                Container(
                  height: 8,
                  width: fillW,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 7,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
                // thumb
                Positioned(
                  left: (fillW - 9).clamp(0.0, math.max(0.0, w - 18)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Sa.isDark ? Sa.panelSolid : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: -1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Compact "Reset" affordance for the reasoning-factor weights.
class _ResetWeightsButton extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetWeightsButton({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onReset,
      icon: Icon(Icons.restart_alt, size: 15, color: Sa.muted),
      label: Text(
        context.tr('Reset'),
        style: Sa.body(size: 11.5, color: Sa.muted),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Inline orange banner shown when a weight mix looks incoherent. Tappable to
/// open the full list of warnings.
class _WeightWarningBanner extends StatelessWidget {
  final String message;
  final int extra; // additional warnings beyond [message]
  final VoidCallback onTap;
  const _WeightWarningBanner({
    required this.message,
    required this.extra,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Sa.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Sa.amber.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Sa.amber, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                extra > 0
                    ? context.tr('{message}  (+{extra} more)', {
                        'message': message,
                        'extra': '$extra',
                      })
                    : message,
                style: Sa.body(size: 11.5, color: Sa.text),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              context.tr('Review'),
              style: Sa.body(size: 11.5, color: Sa.amber),
            ),
            Icon(Icons.chevron_right, color: Sa.amber, size: 18),
          ],
        ),
      ),
    );
  }
}

/// One supervisor's reinforcement memory row.
class _BrainMemoryTile extends StatelessWidget {
  final _BrainMemory memory;
  final Color accent;
  const _BrainMemoryTile({required this.memory, required this.accent});

  static String _initials(String n) {
    final parts = n
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Widget _miniChip(String s, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      s,
      style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w500),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final adj = memory.adjustment;
    final adjColor = adj > 0 ? Sa.green : (adj < 0 ? Sa.red : Sa.muted);
    final adjLabel =
        '${adj > 0 ? '+' : ''}${adj.toStringAsFixed(adj.abs() < 10 ? 1 : 0)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Sa.panelSolid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _initials(memory.name),
              style: Sa.body(size: 11, color: accent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  memory.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 12.5, color: Sa.text),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _miniChip('${memory.accepted} accepted', Sa.green),
                    _miniChip('${memory.rejected} rejected', Sa.red),
                    _miniChip('${memory.resolved} resolved', Sa.blue),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(adjLabel, style: Sa.heading(size: 15, color: adjColor)),
              Text('rank bias', style: Sa.mono(size: 8.5, color: Sa.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single recent decision rendered as a "thought": situation → pick → reason.
class _ThoughtCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final Color accent;
  const _ThoughtCard({required this.log, required this.accent});

  Widget _pill(String s, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      s,
      style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w500),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kind = (log['kind'] ?? 'decision').toString();
    final who = (log['supervisorName'] ?? '').toString();
    final alert = (log['alertLabel'] ?? '').toString();
    final factory = (log['factory'] ?? log['usine'] ?? '').toString();
    final reason = (log['reason'] ?? '').toString();
    final cRaw = log['confidence'];
    final conf = cRaw is num
        ? (cRaw.toDouble() > 1 ? cRaw.toDouble() : cRaw.toDouble() * 100)
        : null;
    final blocked =
        kind.toLowerCase().contains('block') ||
        kind.toLowerCase().contains('skip');
    final tone = blocked ? Sa.amber : accent;
    final head = [
      if (alert.isNotEmpty) alert,
      if (factory.isNotEmpty) '· $factory',
    ].join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Sa.panelSolid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(blocked ? Icons.block : Icons.bolt, size: 14, color: tone),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  head.isEmpty ? context.tr('Decision') : head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 12.5, color: Sa.text),
                ),
              ),
              if (conf != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${conf.round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: tone,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _pill(kind, tone),
              if (who.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 13, color: Sa.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.body(size: 12.5, color: Sa.text),
                  ),
                ),
              ],
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Sa.termBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Sa.termBorder),
              ),
              child: Text(
                reason,
                style: Sa.mono(size: 10.5, color: Sa.termText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


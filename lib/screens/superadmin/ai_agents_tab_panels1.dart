part of 'ai_agents_tab.dart';

class _ShiftAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _ShiftAgentPanel(
      {required this.spec, required this.enabled, required this.health});

  @override
  State<_ShiftAgentPanel> createState() => _ShiftAgentPanelState();
}

class _ShiftAgentPanelState extends State<_ShiftAgentPanel> {
  StreamSubscription<DatabaseEvent>? _sub;
  List<Map<String, dynamic>> _logs = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseDatabase.instance
        .ref('shift_ai_logs')
        .limitToLast(25)
        .onValue
        .listen((event) {
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
        flat.sort((a, b) =>
            (b['at'] ?? '').toString().compareTo((a['at'] ?? '').toString()));
      }
      if (mounted) setState(() => _logs = flat.take(120).toList());
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _bucket(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('assign') || k.contains('transfer')) return 'Assignments';
    if (k.contains('collab')) return 'Collaborations';
    if (k.contains('handover')) return 'Handovers';
    if (k.contains('presence')) return 'Presence checks';
    if (k.contains('block') || k.contains('skip')) return 'Blocked / skipped';
    return 'Other';
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
    final maxBucket =
        buckets.values.isEmpty ? 0 : buckets.values.reduce(math.max);
    final health = widget.health;

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
              title: 'COMMAND DECK',
              subtitle:
                  'Every decision the AI commander takes across active shifts — assignments, collaborations, handovers, presence.',
              accent: spec.accent,
              trailing: GlowChip(
                label: 'LLAMA 3.2 · EDGE',
                color: spec.accent,
                icon: Icons.memory,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Actions · 24h',
                  value: '${last24.length}',
                  icon: Icons.bolt_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Assignments · last cron',
                  value: '${(health?['assignmentsMade'] as num?)?.toInt() ?? 0}',
                  icon: Icons.assignment_turned_in_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'Collabs · last cron',
                  value:
                      '${(health?['collaborationsApproved'] as num?)?.toInt() ?? 0}',
                  icon: Icons.handshake_outlined,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'Handovers · last cron',
                  value:
                      '${(health?['handoversGenerated'] as num?)?.toInt() ?? 0}',
                  icon: Icons.swap_horiz,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Last pulse',
                  value: _agoIso(health?['timestamp']),
                  icon: Icons.monitor_heart_outlined,
                  color: Sa.amber,
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
              icon: Icons.stacked_bar_chart,
              title: 'TASK BREAKDOWN',
              subtitle: 'Distribution of the commander’s recent decisions.',
              accent: spec.accent,
            ),
            const SizedBox(height: 14),
            if (buckets.isEmpty)
              Text('No shift AI activity recorded yet.',
                  style: Sa.body(size: 12, color: Sa.textDim))
            else
              ...buckets.entries.map((e) => _KindBar(
                    label: e.key,
                    count: e.value,
                    max: maxBucket,
                    color: spec.accent,
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
              title: 'ACTION LOG',
              subtitle:
                  'Tap any entry for the full unredacted reasoning, confidence and gate diagnostics.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SaEmptyState(
                icon: Icons.lock_outline,
                title: 'Cannot read shift AI logs',
                message: _error!,
                accent: Sa.red,
              )
            else if (_logs.isEmpty)
              SaEmptyState(
                icon: Icons.nights_stay_outlined,
                title: 'No actions yet',
                message:
                    'The commander logs here the moment a shift with AI Commander enabled goes live.',
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
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-02 · BRIEFING OFFICER
// ═══════════════════════════════════════════════════════════════════════════

class _BriefingAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  const _BriefingAgentPanel({required this.spec, required this.enabled});

  @override
  State<_BriefingAgentPanel> createState() => _BriefingAgentPanelState();
}

class _BriefingAgentPanelState extends State<_BriefingAgentPanel> {
  StreamSubscription<DatabaseEvent>? _latestSub;
  StreamSubscription<DatabaseEvent>? _statsSub;
  Map<String, dynamic>? _latest;
  Map<String, dynamic>? _stats;
  int _historyCount = 0;
  int _factoryCount = 0;
  bool _regenerating = false;
  List<String> _factories = const [];
  // null = global (all-factories) briefing.
  String? _selectedFactory;

  @override
  void initState() {
    super.initState();
    _subscribeLatest();
    _statsSub = FirebaseDatabase.instance
        .ref('ai_agents/briefing/stats')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted && v is Map) {
        setState(() => _stats = Map<String, dynamic>.from(v));
      }
    }, onError: (_) {});
    _probeCounts();
    _loadFactories();
  }

  void _subscribeLatest() {
    _latestSub?.cancel();
    _latestSub = FirebaseDatabase.instance
        .ref(predictiveBriefingPath(_selectedFactory))
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() => _latest = v is Map ? Map<String, dynamic>.from(v) : null);
      }
    }, onError: (_) {});
  }

  Future<void> _loadFactories() async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('hierarchy/factories').get();
      if (snap.value is Map && mounted) {
        final names = (snap.value as Map)
            .values
            .whereType<Map>()
            .map((f) => (f['name'] ?? '').toString())
            .where((n) => n.isNotEmpty)
            .toList()
          ..sort();
        setState(() => _factories = names);
      }
    } catch (_) {}
  }

  Future<void> _probeCounts() async {
    try {
      final slug = predictiveFactorySlug(_selectedFactory);
      final histPath = slug == null
          ? 'ai_briefing/history'
          : 'ai_briefing/factory/$slug/history';
      final hist = await FirebaseDatabase.instance.ref(histPath).get();
      final fact =
          await FirebaseDatabase.instance.ref('ai_briefing/factory').get();
      if (mounted) {
        setState(() {
          _historyCount = hist.children.length;
          _factoryCount = fact.children.length;
        });
      }
    } catch (_) {}
  }

  void _selectFactory(String? factory) {
    if (factory == _selectedFactory) return;
    setState(() {
      _selectedFactory = factory;
      _latest = null;
    });
    _subscribeLatest();
    _probeCounts();
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      final scope = normalizePredictiveFactory(_selectedFactory);
      final factoryQuery = scope != null
          ? 'factory=${Uri.encodeQueryComponent(scope)}&'
          : '';
      final res = await http
          .get(Uri.parse('${AppConfig.briefingEndpoint}?${factoryQuery}force=1'))
          .timeout(const Duration(seconds: 25));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            res.statusCode == 200
                ? 'Briefing regenerated — PM dashboards update live.'
                : 'Briefing endpoint replied ${res.statusCode}.',
            style: Sa.body(size: 12.5),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Regeneration failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  @override
  void dispose() {
    _latestSub?.cancel();
    _statsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final latest = _latest;
    final model = (latest?['model'] ?? '—').toString();

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
              title: 'BRIEFING DESK',
              subtitle:
                  'Writes the factory-aware morning briefing each Production Manager wakes up to.',
              accent: spec.accent,
              trailing: SaButton(
                label: 'REGENERATE NOW',
                icon: Icons.bolt,
                color: spec.accent,
                busy: _regenerating,
                onPressed: widget.enabled ? _regenerate : null,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Briefings archived',
                  value: '$_historyCount',
                  icon: Icons.inventory_2_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Factory scopes',
                  value: '$_factoryCount',
                  icon: Icons.factory_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Generated total',
                  value: '${(_stats?['generated'] as num?)?.toInt() ?? '—'}',
                  icon: Icons.auto_awesome,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'Last generated',
                  value: _agoIso(_stats?['lastGeneratedAt'] ??
                      latest?['generatedAt']),
                  icon: Icons.schedule,
                  color: Sa.amber,
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
              icon: Icons.article_outlined,
              title: 'LATEST DISPATCH',
              subtitle: 'The exact words the PMs are reading right now.',
              accent: spec.accent,
              trailing: Wrap(
                spacing: 6,
                children: [
                  GlowChip(
                    label: model.contains('llama')
                        ? 'LLAMA 3.2 3B'
                        : model.toUpperCase(),
                    color: spec.accent,
                    icon: Icons.memory,
                  ),
                  if ((latest?['date'] ?? '').toString().isNotEmpty)
                    GlowChip(
                        label: (latest?['date'] ?? '').toString(),
                        color: Sa.muted),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FactoryScopeBar(
              factories: _factories,
              selected: _selectedFactory,
              onSelect: _selectFactory,
              accent: spec.accent,
            ),
            const SizedBox(height: 14),
            if (latest == null)
              SaEmptyState(
                icon: Icons.hourglass_empty,
                title: _selectedFactory == null
                    ? 'No briefing yet today'
                    : 'No briefing yet for $_selectedFactory',
                message:
                    'The officer writes the first dispatch when a PM opens their dashboard (or hit REGENERATE NOW).',
                accent: spec.accent,
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Sa.termBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.termBorder),
                ),
                child: SelectableText(
                  (latest['summary'] ?? '—').toString(),
                  style: Sa.mono(size: 11.5, color: Sa.termText),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (latest['accuracyPct'] != null)
                    GlowChip(
                        label: 'MODEL ACCURACY ${latest['accuracyPct']}%',
                        color: Sa.violet),
                  if (latest['topSupervisor'] is Map)
                    GlowChip(
                      label:
                          'TOP: ${((latest['topSupervisor'] as Map)['name'] ?? '—')}'
                          .toUpperCase(),
                      color: Sa.green,
                      icon: Icons.emoji_events_outlined,
                    ),
                  if (latest['predictiveInsight'] is Map &&
                      (latest['predictiveInsight'] as Map)['type'] != null)
                    GlowChip(
                      label:
                          'PREDICTS ${((latest['predictiveInsight'] as Map)['type'] ?? '')}'
                              .toUpperCase(),
                      color: Sa.amber,
                      icon: Icons.online_prediction,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ]);
  }
}

/// Horizontal "ALL FACTORIES" + per-factory chip row letting the SuperAdmin
/// pick which plant's morning briefing the dispatch panel is showing.
/// Each factory has its own briefing scope written to
/// `ai_briefing/factory/{slug}/latest` by the worker (see CLAUDE.md briefing
/// personalization section); `null` selects the global `ai_briefing/latest`.
class _FactoryScopeBar extends StatelessWidget {
  final List<String> factories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final Color accent;

  const _FactoryScopeBar({
    required this.factories,
    required this.selected,
    required this.onSelect,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (factories.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.tune, size: 14, color: Sa.muted),
          ),
          _ScopeChip(
            label: 'ALL FACTORIES',
            selected: selected == null,
            color: accent,
            onTap: () => onSelect(null),
          ),
          for (final f in factories)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _ScopeChip(
                label: f.toUpperCase(),
                selected: selected == f,
                color: accent,
                onTap: () => onSelect(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(colors: [
                  color.withValues(alpha: 0.32),
                  color.withValues(alpha: 0.14),
                ])
              : null,
          color: selected ? null : Sa.termBg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.7) : Sa.termBorder,
          ),
        ),
        child: Text(
          label,
          style: Sa.mono(
            size: 10.5,
            color: selected ? color : Sa.muted,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-03 · AI ASSIST
// ═══════════════════════════════════════════════════════════════════════════

/// The worker's built-in prompt, kept verbatim so the SuperAdmin sees exactly
/// what runs when no override is deployed. Placeholders are substituted by
/// the Cloudflare worker at request time.
const String kAssistDefaultPrompt =
    '''You are an industrial operations assistant. A supervisor needs a resolution suggestion.

Alert type: {type}
Description: {description}
Location: Factory: {usine}, Conveyor line: {convoyeur}, Workstation: #{poste}

{history}

Provide a concise, actionable resolution in 2-3 bullet points. Base it on the past fixes when available; otherwise suggest the most likely root cause and immediate action.''';

class _AssistAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  const _AssistAgentPanel({required this.spec, required this.enabled});

  @override
  State<_AssistAgentPanel> createState() => _AssistAgentPanelState();
}

class _AssistAgentPanelState extends State<_AssistAgentPanel> {
  StreamSubscription<DatabaseEvent>? _statsSub;
  StreamSubscription<DatabaseEvent>? _logsSub;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _logs = const [];
  List<Map<String, dynamic>> _knowledge = const [];
  bool _knowledgeLoading = true;

  final TextEditingController _prompt = TextEditingController();
  bool _overrideActive = false;
  bool _savingPrompt = false;

  @override
  void initState() {
    super.initState();
    _statsSub = FirebaseDatabase.instance
        .ref('ai_agents/assist/stats')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted && v is Map) {
        setState(() => _stats = Map<String, dynamic>.from(v));
      }
    }, onError: (_) {});
    _logsSub = FirebaseDatabase.instance
        .ref('ai_agents/assist/logs')
        .limitToLast(40)
        .onValue
        .listen((event) {
      if (mounted) {
        setState(
            () => _logs = _mapToSortedList(event.snapshot.value, 'at'));
      }
    }, onError: (_) {});
    _loadPrompt();
    _loadKnowledge();
  }

  Future<void> _loadPrompt() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('ai_agents/assist/promptTemplate')
          .get();
      final v = (snap.value ?? '').toString();
      if (mounted) {
        setState(() {
          _overrideActive = v.trim().isNotEmpty;
          _prompt.text = _overrideActive ? v : kAssistDefaultPrompt;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _prompt.text = kAssistDefaultPrompt);
    }
  }

  Future<void> _loadKnowledge() async {
    setState(() => _knowledgeLoading = true);
    try {
      final snap = await FirebaseDatabase.instance
          .ref('alerts')
          .orderByChild('status')
          .equalTo('validee')
          .limitToLast(30)
          .get();
      final list = <Map<String, dynamic>>[];
      for (final child in snap.children) {
        final v = child.value;
        if (v is Map && (v['resolutionReason'] ?? '').toString().isNotEmpty) {
          final m = Map<String, dynamic>.from(v);
          m['id'] = child.key ?? '';
          list.add(m);
        }
      }
      list.sort((a, b) => (b['resolvedAt'] ?? '')
          .toString()
          .compareTo((a['resolvedAt'] ?? '').toString()));
      if (mounted) setState(() => _knowledge = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _knowledgeLoading = false);
    }
  }

  Future<void> _savePrompt() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingPrompt = true);
    try {
      await FirebaseDatabase.instance.ref('ai_agents/assist').update({
        'promptTemplate': text,
        'promptUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(() => _overrideActive = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Prompt override deployed — live within 60s.',
              style: Sa.body(size: 12.5)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Save failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
      }
    } finally {
      if (mounted) setState(() => _savingPrompt = false);
    }
  }

  Future<void> _resetPrompt() async {
    setState(() => _savingPrompt = true);
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/assist/promptTemplate')
          .remove();
      if (mounted) {
        setState(() {
          _overrideActive = false;
          _prompt.text = kAssistDefaultPrompt;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _savingPrompt = false);
    }
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _logsSub?.cancel();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
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
              title: 'CO-PILOT STATUS',
              subtitle:
                  'Serves resolution suggestions to supervisors, grounded in this plant’s real past fixes.',
              accent: spec.accent,
              trailing: GlowChip(
                label: 'LLAMA 3.2 · EDGE',
                color: spec.accent,
                icon: Icons.memory,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Suggestions served',
                  value: '${(_stats?['served'] as num?)?.toInt() ?? 0}',
                  icon: Icons.tips_and_updates_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Last served',
                  value: _agoIso(_stats?['lastServedAt']),
                  icon: Icons.schedule,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Knowledge entries',
                  value: '${_knowledge.length}',
                  icon: Icons.school_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Prompt',
                  value: _overrideActive ? 'CUSTOM' : 'FACTORY DEFAULT',
                  icon: Icons.edit_note,
                  color: _overrideActive ? Sa.green : Sa.muted,
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
              icon: Icons.edit_note,
              title: 'PROMPT LAB',
              subtitle:
                  'The exact instruction sent to Llama on Cloudflare for every suggestion. Edit, deploy, or revert to the factory default.',
              accent: spec.accent,
              trailing: _overrideActive
                  ? GlowChip(
                      label: 'OVERRIDE ACTIVE', color: Sa.green, pulse: true)
                  : GlowChip(label: 'DEFAULT', color: Sa.muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final ph in const [
                  '{type}',
                  '{description}',
                  '{usine}',
                  '{convoyeur}',
                  '{poste}',
                  '{history}',
                ])
                  Tooltip(
                    message: switch (ph) {
                      '{type}' => 'Human-readable alert type',
                      '{description}' => 'Supervisor’s sanitized description',
                      '{usine}' => 'Factory name',
                      '{convoyeur}' => 'Conveyor line number',
                      '{poste}' => 'Workstation number',
                      _ => 'Block of past resolutions for this exact location',
                    },
                    child: GlowChip(label: ph, color: spec.accent),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Sa.termBg.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Sa.termBorder, width: 1.5),
              ),
              child: TextField(
                controller: _prompt,
                maxLines: 12,
                minLines: 6,
                style: Sa.mono(size: 11, color: Sa.termText),
                cursorColor: spec.accent,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                  filled: true,
                  fillColor: Colors.transparent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SaButton(
                  label: 'DEPLOY PROMPT',
                  icon: Icons.rocket_launch_outlined,
                  color: spec.accent,
                  busy: _savingPrompt,
                  onPressed: _savePrompt,
                ),
                const SizedBox(width: 10),
                SaButton(
                  label: 'REVERT TO DEFAULT',
                  icon: Icons.history,
                  color: Sa.amber,
                  outlined: true,
                  onPressed: _overrideActive ? _resetPrompt : null,
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
              icon: Icons.school_outlined,
              title: 'KNOWLEDGE BASE',
              subtitle:
                  'What the agent learns from: the latest validated resolutions it cites when supervisors ask for help.',
              accent: spec.accent,
              trailing: IconButton(
                tooltip: 'Refresh',
                onPressed: _loadKnowledge,
                icon: Icon(Icons.refresh, size: 16, color: spec.accent),
              ),
            ),
            const SizedBox(height: 12),
            if (_knowledgeLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: spec.accent),
                ),
              )
            else if (_knowledge.isEmpty)
              SaEmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No learned fixes yet',
                message:
                    'Resolved alerts with a written resolution become this agent’s study material automatically.',
                accent: spec.accent,
              )
            else
              ..._knowledge.take(20).map((k) => _LogTile(
                    kind: (k['type'] ?? 'fix').toString(),
                    color: spec.accent,
                    title:
                        '${k['usine'] ?? ''} · L${k['convoyeur'] ?? '?'} WS${k['poste'] ?? '?'} — ${k['resolutionReason'] ?? ''}',
                    at: (k['resolvedAt'] ?? '').toString(),
                    details: k,
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
              title: 'SERVICE LOG',
              subtitle: 'Recent suggestion requests answered at the edge.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_logs.isEmpty)
              Text(
                'No requests logged yet — entries appear the moment a supervisor asks for an AI suggestion.',
                style: Sa.body(size: 12, color: Sa.textDim),
              )
            else
              ..._logs.take(30).map((l) => _LogTile(
                    kind: (l['outcome'] ?? 'served').toString(),
                    color: (l['outcome'] ?? '') == 'fallback'
                        ? Sa.amber
                        : spec.accent,
                    title:
                        '${l['type'] ?? ''} @ ${l['usine'] ?? ''} L${l['convoyeur'] ?? '?'} WS${l['poste'] ?? '?'} · ${l['historyUsed'] ?? 0} past fixes cited',
                    at: (l['at'] ?? '').toString(),
                    details: l,
                  )),
          ],
        ),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-04 · SECURITY SENTINEL
// ═══════════════════════════════════════════════════════════════════════════


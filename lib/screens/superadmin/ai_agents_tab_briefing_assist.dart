// Briefing Officer + AI Assist panels: latest dispatch, factory scoping,
// the Prompt Lab, knowledge base, and the LLM model-engine picker.
//
// This is a part file of ai_agents_tab.dart (one library, split for
// maintainability); private identifiers are shared across all parts.
part of 'ai_agents_tab.dart';

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
            setState(
              () => _latest = v is Map ? Map<String, dynamic>.from(v) : null,
            );
          }
        }, onError: (_) {});
  }

  Future<void> _loadFactories() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('hierarchy/factories')
          .get();
      if (snap.value is Map && mounted) {
        final names =
            (snap.value as Map).values
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
      final fact = await FirebaseDatabase.instance
          .ref('ai_briefing/factory')
          .get();
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
          .get(
            Uri.parse('${AppConfig.briefingEndpoint}?${factoryQuery}force=1'),
          )
          .timeout(const Duration(seconds: 25));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              res.statusCode == 200
                  ? 'Briefing regenerated — PM dashboards update live.'
                  : 'Briefing endpoint replied ${res.statusCode}.',
              style: Sa.body(size: 12.5),
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
              'Regeneration failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
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
                leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                title: context.tr('BRIEFING DESK'),
                subtitle: context.tr(
                  'Writes the factory-aware morning briefing each Production Manager wakes up to.',
                ),
                accent: spec.accent,
                trailing: SaButton(
                  label: context.tr('REGENERATE NOW'),
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
                    label: context.tr('Briefings archived'),
                    value: '$_historyCount',
                    icon: Icons.inventory_2_outlined,
                    color: spec.accent,
                  ),
                  SaStatTile(
                    label: context.tr('Factory scopes'),
                    value: '$_factoryCount',
                    icon: Icons.factory_outlined,
                    color: Sa.violet,
                  ),
                  SaStatTile(
                    label: context.tr('Generated total'),
                    value: '${(_stats?['generated'] as num?)?.toInt() ?? '—'}',
                    icon: Icons.auto_awesome,
                    color: Sa.green,
                  ),
                  SaStatTile(
                    label: context.tr('Last generated'),
                    value: _agoIso(
                      context,
                      _stats?['lastGeneratedAt'] ?? latest?['generatedAt'],
                    ),
                    icon: Icons.schedule,
                    color: Sa.amber,
                  ),
                ],
              ),
            ],
          ),
        ),
        _ModelEnginePanel(
          agent: 'briefing',
          accent: spec.accent,
          enabled: widget.enabled,
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.article_outlined,
                title: context.tr('LATEST DISPATCH'),
                subtitle: context.tr(
                  'The exact words the PMs are reading right now.',
                ),
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
                        color: Sa.muted,
                      ),
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
                      ? context.tr('No briefing yet today')
                      : context.tr('No briefing yet for {factory}', {
                          'factory': _selectedFactory!,
                        }),
                  message: context.tr(
                    'The officer writes the first dispatch when a PM opens their dashboard (or hit REGENERATE NOW).',
                  ),
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
                        label: context.tr('MODEL ACCURACY {pct}%', {
                          'pct': '${latest['accuracyPct']}',
                        }),
                        color: Sa.violet,
                      ),
                    if (latest['topSupervisor'] is Map)
                      GlowChip(
                        label: context
                            .tr('TOP: {name}', {
                              'name':
                                  ((latest['topSupervisor']
                                              as Map)['name'] ??
                                          '—')
                                      .toString(),
                            })
                            .toUpperCase(),
                        color: Sa.green,
                        icon: Icons.emoji_events_outlined,
                      ),
                    if (latest['predictiveInsight'] is Map &&
                        (latest['predictiveInsight'] as Map)['type'] != null)
                      GlowChip(
                        label: context
                            .tr('PREDICTS {type}', {
                              'type':
                                  ((latest['predictiveInsight'] as Map)['type'] ??
                                          '')
                                      .toString(),
                            })
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
      ],
    );
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
            label: context.tr('ALL FACTORIES'),
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
              ? LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.32),
                    color.withValues(alpha: 0.14),
                  ],
                )
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
              () => _logs = _mapToSortedList(event.snapshot.value, 'at'),
            );
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
      list.sort(
        (a, b) => (b['resolvedAt'] ?? '').toString().compareTo(
          (a['resolvedAt'] ?? '').toString(),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Sa.panelSolid,
            content: Text(
              'Prompt override deployed — live within 60s.',
              style: Sa.body(size: 12.5),
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
              'Save failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red),
            ),
          ),
        );
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
                leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
                title: context.tr('CO-PILOT STATUS'),
                subtitle: context.tr(
                  'Serves resolution suggestions to supervisors, grounded in this plant’s real past fixes.',
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
                    label: context.tr('Suggestions served'),
                    value: '${(_stats?['served'] as num?)?.toInt() ?? 0}',
                    icon: Icons.tips_and_updates_outlined,
                    color: spec.accent,
                  ),
                  SaStatTile(
                    label: context.tr('Last served'),
                    value: _agoIso(context, _stats?['lastServedAt']),
                    icon: Icons.schedule,
                    color: Sa.amber,
                  ),
                  SaStatTile(
                    label: context.tr('Knowledge entries'),
                    value: '${_knowledge.length}',
                    icon: Icons.school_outlined,
                    color: Sa.violet,
                  ),
                  SaStatTile(
                    label: context.tr('Prompt'),
                    value: _overrideActive
                        ? context.tr('CUSTOM')
                        : context.tr('FACTORY DEFAULT'),
                    icon: Icons.edit_note,
                    color: _overrideActive ? Sa.green : Sa.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
        _ModelEnginePanel(
          agent: 'assist',
          accent: spec.accent,
          enabled: widget.enabled,
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SaSectionHeader(
                icon: Icons.edit_note,
                title: context.tr('PROMPT LAB'),
                subtitle: context.tr(
                  'The exact instruction sent to Llama on Cloudflare for every suggestion. Edit, deploy, or revert to the factory default.',
                ),
                accent: spec.accent,
                trailing: _overrideActive
                    ? GlowChip(
                        label: context.tr('OVERRIDE ACTIVE'),
                        color: Sa.green,
                        pulse: true,
                      )
                    : GlowChip(label: context.tr('DEFAULT'), color: Sa.muted),
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
                        '{type}' => context.tr('Human-readable alert type'),
                        '{description}' => context.tr(
                          'Supervisor’s sanitized description',
                        ),
                        '{usine}' => context.tr('Factory name'),
                        '{convoyeur}' => context.tr('Conveyor line number'),
                        '{poste}' => context.tr('Workstation number'),
                        _ => context.tr(
                          'Block of past resolutions for this exact location',
                        ),
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
                    label: context.tr('DEPLOY PROMPT'),
                    icon: Icons.rocket_launch_outlined,
                    color: spec.accent,
                    busy: _savingPrompt,
                    onPressed: _savePrompt,
                  ),
                  const SizedBox(width: 10),
                  SaButton(
                    label: context.tr('REVERT TO DEFAULT'),
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
                title: context.tr('KNOWLEDGE BASE'),
                subtitle: context.tr(
                  'What the agent learns from: the latest validated resolutions it cites when supervisors ask for help.',
                ),
                accent: spec.accent,
                trailing: IconButton(
                  tooltip: context.tr('Refresh'),
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
                      strokeWidth: 2,
                      color: spec.accent,
                    ),
                  ),
                )
              else if (_knowledge.isEmpty)
                SaEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: context.tr('No learned fixes yet'),
                  message: context.tr(
                    'Resolved alerts with a written resolution become this agent’s study material automatically.',
                  ),
                  accent: spec.accent,
                )
              else
                ..._knowledge
                    .take(20)
                    .map(
                      (k) => _LogTile(
                        kind: (k['type'] ?? 'fix').toString(),
                        color: spec.accent,
                        title:
                            '${k['usine'] ?? ''} · L${k['convoyeur'] ?? '?'} WS${k['poste'] ?? '?'} — ${k['resolutionReason'] ?? ''}',
                        at: (k['resolvedAt'] ?? '').toString(),
                        details: k,
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
                title: context.tr('SERVICE LOG'),
                subtitle: context.tr(
                  'Recent suggestion requests answered at the edge.',
                ),
                accent: spec.accent,
              ),
              const SizedBox(height: 12),
              if (_logs.isEmpty)
                Text(
                  context.tr(
                    'No requests logged yet — entries appear the moment a supervisor asks for an AI suggestion.',
                  ),
                  style: Sa.body(size: 12, color: Sa.textDim),
                )
              else
                ..._logs
                    .take(30)
                    .map(
                      (l) => _LogTile(
                        kind: (l['outcome'] ?? 'served').toString(),
                        color: (l['outcome'] ?? '') == 'fallback'
                            ? Sa.amber
                            : spec.accent,
                        title: context.tr('{prefix} · {count} past fixes cited', {
                          'prefix':
                              '${l['type'] ?? ''} @ ${l['usine'] ?? ''} L${l['convoyeur'] ?? '?'} WS${l['poste'] ?? '?'}',
                          'count': '${l['historyUsed'] ?? 0}',
                        }),
                        at: (l['at'] ?? '').toString(),
                        details: l,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-04 · SECURITY SENTINEL
// ═══════════════════════════════════════════════════════════════════════════

/// MODEL ENGINE — lets IT point the Assist or Briefing agent at any supported
/// LLM and paste the company's own API key. Llama (Cloudflare Workers AI) is the
/// default and needs no key. Reads/writes ai_model_config/{agent}.
class _ModelEnginePanel extends StatefulWidget {
  final String agent; // 'assist' | 'briefing'
  final Color accent;
  final bool enabled;
  const _ModelEnginePanel({
    required this.agent,
    required this.accent,
    required this.enabled,
  });

  @override
  State<_ModelEnginePanel> createState() => _ModelEnginePanelState();
}

class _ModelEnginePanelState extends State<_ModelEnginePanel> {
  final _svc = AiModelConfigService();
  final TextEditingController _key = TextEditingController();
  String _modelId = kDefaultAiModelId;
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  bool _testing = false;
  bool _hasKey = false; // a key is on file in the worker-only vault (value unknown to the client)
  ModelEvalResult? _eval;
  StreamSubscription<DatabaseEvent>? _driftSub;
  Map<String, dynamic>? _drift;

  @override
  void initState() {
    super.initState();
    _load();
    _driftSub = FirebaseDatabase.instance
        .ref('ai_model_evals/${widget.agent}/driftStatus')
        .onValue
        .listen((e) {
          final v = e.snapshot.value;
          if (mounted) {
            setState(
              () => _drift = v is Map ? Map<String, dynamic>.from(v) : null,
            );
          }
        }, onError: (_) {});
  }

  Future<void> _load() async {
    try {
      final cfg = await _svc.fetch(widget.agent);
      if (mounted) {
        setState(() {
          _modelId = cfg.modelId;
          // The key value is worker-only and never returned; we only learn
          // whether one is on file.
          _hasKey = cfg.hasKey;
          _key.clear();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final model = aiModelById(_modelId);
    final key = _key.text.trim();
    // A key is required unless one is already on file for this keyed model
    // (re-saving keeps the stored key — the client can't read it back to resend).
    if (model.needsKey && key.isEmpty && !_hasKey) {
      _toast(
        context.tr('{label} needs an API key — paste it first.', {
          'label': model.label,
        }),
        err: true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.save(
        widget.agent,
        AiModelConfig(
          modelId: _modelId,
          apiKey: model.needsKey ? key : '',
          hasKey: model.needsKey && (key.isNotEmpty || _hasKey),
        ),
      );
      if (mounted) {
        setState(() {
          if (model.needsKey && key.isNotEmpty) _hasKey = true;
          if (!model.needsKey) _hasKey = false;
          _key.clear();
        });
      }
      _toast(
        context.tr('Model saved — {label}. Live within 60s.', {
          'label': model.label,
        }),
      );
    } catch (e) {
      _toast(context.tr('Save failed: {error}', {'error': '$e'}), err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final model = aiModelById(_modelId);
    final key = _key.text.trim();
    if (model.needsKey && key.isEmpty) {
      _toast(
        context.tr('{label} needs an API key to test.', {
          'label': model.label,
        }),
        err: true,
      );
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await _svc.evaluate(
        widget.agent,
        AiModelConfig(modelId: _modelId, apiKey: model.needsKey ? key : ''),
      );
      if (mounted) setState(() => _eval = result);
    } catch (e) {
      _toast(context.tr('Test failed: {error}', {'error': '$e'}), err: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _driftStripWidget() {
    final d = _drift!;
    final drifting = d['drift'] == true;
    final score = (d['score'] is num) ? (d['score'] as num).toDouble() : 0.0;
    final baseline = (d['baseline'] is num)
        ? (d['baseline'] as num).toDouble()
        : null;
    final c = drifting ? Sa.red : Sa.green;
    final reason = (d['reason'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            drifting ? Icons.warning_amber_rounded : Icons.verified_outlined,
            size: 16,
            color: c,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              drifting
                  ? context.tr('Drift detected — {reason}', {
                      'reason': reason.isNotEmpty
                          ? reason
                          : context.tr('quality regressed'),
                    })
                  : context.tr('Quality stable · {pct}%{baseline}', {
                      'pct': '${(score * 100).round()}',
                      'baseline': baseline != null
                          ? context.tr(' vs {pct}% baseline', {
                              'pct': '${(baseline * 100).round()}',
                            })
                          : '',
                    }),
              style: Sa.body(size: 11.5, color: Sa.text),
            ),
          ),
          Text(
            context.tr('checked {time}', {
              'time': _agoIso(context, d['at']),
            }),
            style: Sa.mono(size: 9.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Sa.panelSolid,
        content: Text(
          msg,
          style: Sa.body(size: 12.5, color: err ? Sa.red : Sa.text),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _driftSub?.cancel();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = aiModelById(_modelId);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.hub_outlined,
            title: context.tr('MODEL ENGINE'),
            subtitle: context.tr(
              'Choose which AI model writes this agent’s output. Llama runs free on the edge; any other provider uses your own API key — stored in a SuperAdmin-only node and used edge-side only.',
            ),
            accent: widget.accent,
            trailing: GlowChip(
              label: selected.needsKey
                  ? context.tr('BRING-YOUR-OWN-KEY')
                  : context.tr('BUILT-IN'),
              color: selected.needsKey ? Sa.amber : Sa.green,
              icon: selected.needsKey ? Icons.vpn_key_outlined : Icons.bolt,
            ),
          ),
          const SizedBox(height: 14),
          if (_drift != null) _driftStripWidget(),
          if (_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.accent,
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in kAiModels)
                  _ModelOptionTile(
                    model: m,
                    selected: m.id == _modelId,
                    onTap: () => setState(() {
                      _modelId = m.id;
                      if (!m.needsKey) _key.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (selected.needsKey) ...[
              Text(
                context.tr('{label} — API key', {'label': selected.label}),
                style: Sa.body(size: 12, color: Sa.muted),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Sa.termBg.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.termBorder, width: 1.5),
                ),
                child: TextField(
                  controller: _key,
                  obscureText: _obscure,
                  style: Sa.mono(size: 11.5, color: Sa.termText),
                  cursorColor: widget.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    hintText: _hasKey
                        ? context.tr('•••••••• key on file — paste a new one to replace it')
                        : context.tr('Paste your {provider} API key', {
                            'provider': selected.provider,
                          }),
                    hintStyle: Sa.mono(size: 11.5, color: Sa.muted),
                    suffixIcon: IconButton(
                      tooltip: _obscure
                          ? context.tr('Show')
                          : context.tr('Hide'),
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 16,
                        color: Sa.muted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 12, color: Sa.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr(
                        'The key is read only by the edge worker and SuperAdmin. It never reaches supervisor or PM devices. If a call fails, the agent falls back to built-in Llama automatically.',
                      ),
                      style: Sa.body(size: 11, color: Sa.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Sa.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bolt, size: 16, color: Sa.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr(
                          'Built-in Llama 3.2 runs on Cloudflare Workers AI — no API key, no extra cost. Pick another provider above to use a stronger model.',
                        ),
                        style: Sa.body(size: 12, color: Sa.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaButton(
                  label: context.tr('TEST THIS MODEL'),
                  icon: Icons.science_outlined,
                  color: widget.accent,
                  outlined: true,
                  busy: _testing,
                  onPressed: widget.enabled ? _test : null,
                ),
                SaButton(
                  label: context.tr('SAVE MODEL'),
                  icon: Icons.save_outlined,
                  color: widget.accent,
                  busy: _saving,
                  onPressed: widget.enabled ? _save : null,
                ),
              ],
            ),
            if (_testing)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  context.tr(
                    'Running both models on golden tasks and scoring them…',
                  ),
                  style: Sa.body(size: 11, color: Sa.muted),
                ),
              ),
            if (_eval != null)
              _EvalResultCard(eval: _eval!, accent: widget.accent),
          ],
        ],
      ),
    );
  }
}

/// Head-to-head eval result: candidate vs current champion, with a verdict.
class _EvalResultCard extends StatelessWidget {
  final ModelEvalResult eval;
  final Color accent;
  const _EvalResultCard({required this.eval, required this.accent});

  static String _short(BuildContext context, String id) =>
      id.isEmpty ? context.tr('built-in') : id;

  Widget _scoreRow(String label, double score, Color color, bool strong) {
    final pct = score.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Sa.body(size: 11.5, color: strong ? Sa.text : Sa.textDim),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, cons) => Container(
              height: 10,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Sa.panelSolid,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Container(
                height: 10,
                width: cons.maxWidth * pct,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 42,
          child: Text(
            '${(pct * 100).round()}%',
            textAlign: TextAlign.right,
            style: Sa.mono(size: 11.5, color: strong ? Sa.text : Sa.muted),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = eval.verdict;
    final vColor = v == 'better'
        ? Sa.green
        : (v == 'worse' ? Sa.red : Sa.amber);
    final vLabel = v == 'better'
        ? context.tr('BETTER — safe to deploy')
        : v == 'worse'
        ? context.tr('WORSE — keep current')
        : context.tr('SIMILAR — no real gain');
    final vIcon = v == 'better'
        ? Icons.trending_up
        : v == 'worse'
        ? Icons.trending_down
        : Icons.drag_handle;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: vColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: vColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(vIcon, size: 18, color: vColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(vLabel, style: Sa.heading(size: 13, color: vColor)),
              ),
              Text(
                '${eval.delta >= 0 ? '+' : ''}${(eval.delta * 100).round()} pts',
                style: Sa.mono(size: 12, color: vColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _scoreRow(context.tr('This model'), eval.candidate.score, accent, true),
          const SizedBox(height: 8),
          _scoreRow(
            context.tr('Current · {model}', {
              'model': _short(context, eval.champion.modelId),
            }),
            eval.champion.score,
            Sa.muted,
            false,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Both models ran the same golden tasks; we score grounding, structure, on-topic accuracy and length. Higher is better.',
            ),
            style: Sa.body(size: 10.5, color: Sa.muted),
          ),
        ],
      ),
    );
  }
}

/// One selectable model in the MODEL ENGINE grid: brand icon + label, with a
/// "no key" hint for the built-in default and a check when selected.
class _ModelOptionTile extends StatelessWidget {
  final AiModel model;
  final bool selected;
  final VoidCallback onTap;
  const _ModelOptionTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 176,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? model.color.withValues(alpha: 0.14)
              : Sa.termBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? model.color : Sa.termBorder,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: model.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _ProviderLogo(
                provider: _Providers.of(model.brandId),
                size: 17,
                color: model.color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    model.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.body(
                      size: 11.5,
                      color: selected ? Sa.text : Sa.textDim,
                    ),
                  ),
                  if (!model.needsKey)
                    Text(
                      context.tr('default · no key'),
                      style: Sa.body(size: 9.5, color: Sa.green),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 16, color: model.color),
          ],
        ),
      ),
    );
  }
}


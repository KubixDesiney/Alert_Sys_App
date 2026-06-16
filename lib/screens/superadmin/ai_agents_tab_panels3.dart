part of 'ai_agents_tab.dart';

class _GuardianAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  const _GuardianAgentPanel({required this.spec});

  @override
  State<_GuardianAgentPanel> createState() => _GuardianAgentPanelState();
}

class _GuardianAgentPanelState extends State<_GuardianAgentPanel> {
  static const _ghUrl = String.fromEnvironment('ALERTSYS_GITHUB_WORKER_URL', defaultValue: '');
  static const _wSecret = String.fromEnvironment('ALERTSYS_WORKER_SHARED_SECRET', defaultValue: '');

  final _cfg = FirebaseDatabase.instance.ref('ai_agents/guardian');
  final _sec = FirebaseDatabase.instance.ref('ai_agent_secrets/guardian');

  static const _gGreen = Color(0xFF3FB950);
  static const _gRed = Color(0xFFF85149);
  static const _gAmber = Color(0xFFD29922);
  static const _gPurple = Color(0xFFA371F7);

  List<Map<String, dynamic>> _ghRuns = [];
  List<Map<String, dynamic>> _ghPulls = [];
  bool _ghLoading = false;
  bool _ghConnected = false;
  Map<dynamic, dynamic> _secrets = {};
  Offset _simOffset = const Offset(10, 96);
  bool _deployAuto = false;
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _sec.get().then((s) {
      if (mounted && s.value is Map) setState(() => _secrets = s.value as Map<dynamic, dynamic>);
    });
    _loadGithub();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGithub() async {
    if (_ghUrl.isEmpty) return;
    setState(() => _ghLoading = true);
    final gh = GithubService(baseUrl: _ghUrl, sharedSecret: _wSecret);
    final connected = await gh.connected();
    final runs = connected ? await gh.runs() : <Map<String, dynamic>>[];
    final pulls = connected ? await gh.pulls() : <Map<String, dynamic>>[];
    if (!mounted) return;
    setState(() {
      _ghConnected = connected;
      _ghRuns = runs;
      _ghPulls = pulls;
      _ghLoading = false;
    });
  }

  bool _hasSecret(String k) => (_secrets[k]?.toString() ?? '').isNotEmpty;
  String _ts() => DateTime.now().toIso8601String().substring(11, 19);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _cfg.onValue,
      builder: (context, snap) {
        final raw = snap.data?.snapshot.value;
        final cfg = (raw is Map) ? raw : const {};
        final settings = (cfg['settings'] is Map) ? cfg['settings'] as Map : const {};
        final enabled = cfg['enabled'] != false;
        final active = (cfg['activeRun'] is Map) ? cfg['activeRun'] as Map : null;
        _deployAuto = (settings['deployMode'] ?? 'human') == 'auto';
        return LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight.isFinite ? c.maxHeight : 1600.0;
            return SizedBox(
              height: h,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(enabled, settings),
                          const SizedBox(height: 14),
                          _pipeline(active),
                          const SizedBox(height: 14),
                          _terminal(active),
                          const SizedBox(height: 14),
                          _aiConfig(settings),
                          const SizedBox(height: 14),
                          _github(cfg),
                          const SizedBox(height: 14),
                          _knowledge(cfg),
                          const SizedBox(height: 14),
                          _githubLive(),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: _simOffset.dx.clamp(0.0, (c.maxWidth - 176).clamp(0.0, double.infinity)),
                    top: _simOffset.dy.clamp(0.0, (h - 120).clamp(0.0, double.infinity)),
                    child: _simToolbar(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── movable simulate toolbar ──
  Widget _simToolbar() {
    final sims = <List<dynamic>>[
      ['Login error', Icons.login, 'high', 'login screen error — users cannot sign in', 'claude-opus-4-8'],
      ['Notifications', Icons.notifications_off, 'high', 'alerts not reaching supervisors', 'claude-opus-4-8'],
      ['Worker fail', Icons.dns, 'high', 'cloudflare worker endpoint failing', 'claude-opus-4-8'],
      ['Version', Icons.sync_problem, 'medium', 'dependency version mismatch breaks build', 'claude-sonnet-4-6'],
      ['Tab broken', Icons.tab_unselected, 'medium', 'supervisor tab blank / not loading', 'claude-sonnet-4-6'],
      ['Test fail', Icons.science, 'low', 'flutter test failing on a widget test', 'claude-haiku-4-5'],
    ];
    return Container(
      width: 166,
      decoration: BoxDecoration(
        color: Sa.panelSolid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.borderBright),
        boxShadow: [BoxShadow(color: Sa.shadow, blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onPanUpdate: (d) => setState(() => _simOffset += d.delta),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: widget.spec.accent.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(children: [
                Icon(Icons.drag_indicator, size: 15, color: Sa.muted),
                const SizedBox(width: 5),
                Text('SIMULATE', style: Sa.body(size: 10.5, color: Sa.textDim)),
              ]),
            ),
          ),
          for (final s in sims)
            InkWell(
              onTap: () => _simulateIncident(s[0] as String, s[2] as String, s[3] as String, s[4] as String),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(children: [
                  Icon(s[1] as IconData, size: 14,
                      color: s[2] == 'high' ? _gRed : (s[2] == 'medium' ? _gAmber : Sa.muted)),
                  const SizedBox(width: 8),
                  Text(s[0] as String, style: Sa.body(size: 12, color: Sa.text)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // ── header ──
  Widget _header(bool enabled, Map settings) {
    return GlassPanel(
      accent: widget.spec.accent,
      child: Row(
        children: [
          SizedBox(width: 40, height: 40, child: _AgentGlyph(spec: widget.spec, size: 40, radius: 11)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GUARDIAN', style: Sa.display(size: 17)),
                Text('autonomous fix pipeline', style: Sa.body(size: 12, color: Sa.muted)),
              ],
            ),
          ),
          _deployToggle('Automatic', _deployAuto, () => _saveSetting('deployMode', 'auto')),
          const SizedBox(width: 6),
          _deployToggle('Human review', !_deployAuto, () => _saveSetting('deployMode', 'human')),
          const SizedBox(width: 12),
          GlowChip(label: enabled ? 'ARMED' : 'OFF', color: enabled ? _gGreen : Sa.muted, pulse: enabled),
          Switch(value: enabled, onChanged: (v) => _cfg.update({'enabled': v})),
        ],
      ),
    );
  }

  Widget _deployToggle(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? widget.spec.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? widget.spec.accent.withValues(alpha: 0.5) : Sa.border),
        ),
        child: Text(label, style: Sa.body(size: 11.5, color: active ? widget.spec.accent : Sa.textDim)),
      ),
    );
  }

  // ── dynamic pipeline ──
  Widget _pipeline(Map? active) {
    if (active == null) {
      return _panel('PIPELINE', Icons.route, Row(children: [
        Icon(Icons.check_circle_outline, color: _gGreen, size: 18),
        const SizedBox(width: 9),
        Expanded(child: Text('No active incident — pipeline idle. Guardian is watching.',
            style: Sa.body(size: 12.5, color: Sa.muted))),
      ]));
    }
    final stages = ['detect', 'context', 'fix', 'review', 'gate', 'deploy'];
    final labels = ['Detect', 'Gather context', 'Fix', 'Review + tests', 'Gate', 'PR / deploy'];
    final cur = stages.indexOf((active['stage'] ?? 'detect').toString());
    final status = (active['status'] ?? 'running').toString();
    final done = status == 'deployed' || status == 'pr_open';
    final failed = status == 'failed';
    final sev = (active['severity'] ?? 'high').toString().toUpperCase();
    return GlassPanel(
      accent: _gRed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GlowChip(label: done ? 'RESOLVED' : 'INCIDENT ACTIVE', color: done ? _gGreen : _gRed, pulse: !done),
            const SizedBox(width: 8),
            GlowChip(label: sev, color: sev == 'HIGH' ? _gRed : (sev == 'MEDIUM' ? _gAmber : Sa.muted)),
            const Spacer(),
            InkWell(onTap: _dismissIncident, child: Icon(Icons.close, size: 16, color: Sa.muted)),
          ]),
          const SizedBox(height: 6),
          Text((active['title'] ?? 'incident').toString(), style: Sa.body(size: 12.5, color: Sa.text)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < stages.length; i++)
              _stageChip(labels[i],
                  done ? 'done' : (i < cur ? 'done' : (i == cur ? (failed ? 'failed' : 'active') : 'pending'))),
          ]),
        ],
      ),
    );
  }

  Widget _stageChip(String label, String state) {
    Color c;
    Widget ic;
    switch (state) {
      case 'done':
        c = _gGreen;
        ic = Icon(Icons.check, size: 13, color: c);
        break;
      case 'active':
        c = _gAmber;
        ic = SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: c));
        break;
      case 'failed':
        c = _gRed;
        ic = Icon(Icons.close, size: 13, color: c);
        break;
      default:
        c = Sa.muted;
        ic = Icon(Icons.circle_outlined, size: 12, color: c);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
        color: c.withValues(alpha: 0.10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [ic, const SizedBox(width: 6), Text(label, style: Sa.body(size: 11.5, color: c))]),
    );
  }

  // ── terminal ──
  Widget _terminal(Map? active) {
    final logs = (active != null && active['log'] is List)
        ? (active['log'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final running = active != null && (active['status'] ?? '') == 'running';
    return Container(
      decoration: BoxDecoration(color: Sa.termBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: Sa.termBorder)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.terminal, size: 14, color: Sa.termDim),
            const SizedBox(width: 6),
            Text('GUARDIAN TERMINAL', style: TextStyle(color: Sa.termDim, fontSize: 11, letterSpacing: 0.5, fontFamily: 'monospace')),
            const Spacer(),
            if (running) ...[
              SizedBox(width: 9, height: 9, child: CircularProgressIndicator(strokeWidth: 2, color: _gAmber)),
              const SizedBox(width: 6),
              Text('working', style: TextStyle(color: _gAmber, fontSize: 11, fontFamily: 'monospace')),
            ],
          ]),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            Text('guardian idle \$ watching for incidents…',
                style: TextStyle(color: Sa.termMuted, fontSize: 11.5, fontFamily: 'monospace'))
          else
            for (final l in logs)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(l, style: TextStyle(color: Sa.termText, fontSize: 11.5, height: 1.5, fontFamily: 'monospace')),
              ),
        ],
      ),
    );
  }

  // ── AI config ──
  Widget _aiConfig(Map settings) {
    final auto = settings['autoModelSelect'] != false;
    return _panel('AI CONFIGURATION', Icons.memory, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _aiCard('Fix AI', 'fix', settings, Sa.blue)),
          const SizedBox(width: 10),
          Expanded(child: _aiCard('Review AI', 'review', settings, _gPurple)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text('Auto-select model by severity', style: Sa.body(size: 12, color: Sa.textDim)),
          const Spacer(),
          Switch(value: auto, onChanged: (v) => _saveSetting('autoModelSelect', v)),
        ]),
      ],
    ));
  }

  Widget _aiCard(String title, String role, Map settings, Color accent) {
    final provId = (settings['${role}Provider'] ?? (role == 'fix' ? 'anthropic' : 'openai')).toString();
    final prov = _Providers.list.firstWhere((p) => p.id == provId, orElse: () => _Providers.list.first);
    final model = (settings['${role}Model'] ?? prov.defaultModel).toString();
    final keySet = _hasSecret('${role}ApiKey');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Sa.bgRaised, borderRadius: BorderRadius.circular(10), border: Border.all(color: Sa.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Sa.body(size: 12.5, color: accent)),
          const SizedBox(height: 8),
          InkWell(onTap: () => _pickProvider(role, settings), child: _fieldRow(Icons.expand_more, '${prov.name} · $model')),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _setSecret('${role}ApiKey', '$title API key', prov.tokenHint),
            child: _fieldRow(Icons.key, keySet ? '•••••••• set' : 'set API key',
                trailing: keySet ? Icon(Icons.check, size: 14, color: _gGreen) : null),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(IconData ic, String text, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Sa.bg, borderRadius: BorderRadius.circular(7), border: Border.all(color: Sa.border)),
      child: Row(children: [
        Icon(ic, size: 14, color: Sa.muted),
        const SizedBox(width: 7),
        Expanded(child: Text(text, overflow: TextOverflow.ellipsis, style: Sa.body(size: 12, color: Sa.text))),
        if (trailing != null) trailing,
      ]),
    );
  }

  // ── github connection ──
  Widget _github(Map cfg) {
    final repo = (cfg['repo'] ?? '').toString();
    return _panel('GITHUB CONNECTION', Icons.hub_outlined, Row(children: [
      Expanded(child: InkWell(onTap: _setRepo, child: _fieldRow(Icons.account_tree, repo.isEmpty ? 'link repository (owner/name)' : repo))),
      const SizedBox(width: 10),
      Expanded(child: InkWell(
        onTap: () => _setSecret('githubToken', 'GitHub token', 'github_pat_…'),
        child: _fieldRow(Icons.vpn_key, _hasSecret('githubToken') ? '•••••••• set' : 'set token',
            trailing: _ghConnected ? Icon(Icons.check, size: 14, color: _gGreen) : null),
      )),
    ]));
  }

  // ── knowledge ──
  Widget _knowledge(Map cfg) {
    List<String> listOf(String k) {
      final v = cfg[k];
      if (v is List) return v.map((e) => e is Map ? (e['name'] ?? 'file').toString() : e.toString()).toList();
      return const [];
    }
    return _panel('KNOWLEDGE · upload .md', Icons.menu_book_outlined, Row(children: [
      Expanded(child: _mdColumn('Instructions', 'instructions', listOf('instructions'), Sa.blue)),
      const SizedBox(width: 10),
      Expanded(child: _mdColumn('Skills', 'skills', listOf('skills'), _gGreen)),
    ]));
  }

  Widget _mdColumn(String title, String key, List<String> files, Color accent) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Sa.bgRaised, borderRadius: BorderRadius.circular(10), border: Border.all(color: Sa.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: Sa.body(size: 12.5, color: accent)),
            const Spacer(),
            Text('${files.length}', style: Sa.body(size: 11, color: Sa.muted)),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Icon(Icons.description_outlined, size: 13, color: Sa.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(files[i], overflow: TextOverflow.ellipsis, style: Sa.body(size: 11.5, color: Sa.textDim))),
                InkWell(
                  onTap: () => _deleteMd(key, i),
                  child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.delete_outline, size: 15, color: _gRed)),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          SaButton(label: 'Upload .md', icon: Icons.upload_file, outlined: true, onPressed: () => _uploadMd(key)),
        ],
      ),
    );
  }

  // ── live github (matches the GitHub screenshots) ──
  Widget _githubLive() {
    return _panel('GITHUB · LIVE', Icons.bolt, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Workflow runs', style: Sa.body(size: 12, color: Sa.textDim)),
          const Spacer(),
          if (_ghLoading)
            SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Sa.cyan))
          else
            InkWell(onTap: _loadGithub, child: Icon(Icons.refresh, size: 17, color: Sa.cyan)),
        ]),
        const SizedBox(height: 4),
        if (!_ghConnected)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Sa.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: Sa.border)),
            child: Row(children: [
              Icon(Icons.link_off, size: 16, color: Sa.muted),
              const SizedBox(width: 9),
              Expanded(child: Text(
                _ghUrl.isEmpty
                    ? 'Set ALERTSYS_GITHUB_WORKER_URL (build define) to stream live Actions + PRs.'
                    : 'Link a repo + GitHub token above to stream live Actions + PRs.',
                style: Sa.body(size: 12, color: Sa.muted))),
            ]),
          )
        else ...[
          for (final r in _ghRuns.take(6)) _ghActionRow(r),
          const SizedBox(height: 12),
          Text('Pull requests', style: Sa.body(size: 12, color: Sa.textDim)),
          const SizedBox(height: 4),
          for (final p in _ghPulls.take(6)) _ghPrRow(p),
        ],
      ],
    ));
  }

  Widget _ghActionRow(Map<String, dynamic> r) {
    final concl = (r['conclusion'] ?? r['status'] ?? '').toString();
    final c = _statusColor(concl);
    final running = concl.contains('progress') || concl.contains('queued') || concl.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Sa.border.withValues(alpha: 0.5)))),
      child: Row(children: [
        running
            ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: _gAmber))
            : Icon(_statusIcon(concl), size: 17, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['name'] ?? 'workflow'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Sa.body(size: 13, color: Sa.text)),
            Text('#${r['runNumber'] ?? '?'} · ${r['event'] ?? ''}', style: Sa.body(size: 11, color: Sa.muted)),
          ]),
        ),
        if ((r['branch'] ?? '').toString().isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Sa.blue.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(r['branch'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Sa.body(size: 10.5, color: Sa.blue)),
          ),
        const SizedBox(width: 8),
        Text(_ago(r['createdAt']?.toString()), style: Sa.body(size: 11, color: Sa.muted)),
      ]),
    );
  }

  Widget _ghPrRow(Map<String, dynamic> p) {
    final state = (p['state'] ?? '').toString();
    final c = state == 'merged' ? _gPurple : (state == 'open' ? _gGreen : Sa.muted);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Sa.border.withValues(alpha: 0.5)))),
      child: Row(children: [
        Icon(Icons.call_merge, size: 16, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Sa.body(size: 13, color: Sa.text)),
            Row(children: [
              Text('#${p['number'] ?? '?'} · ${p['user'] ?? ''}', style: Sa.body(size: 11, color: Sa.muted)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Sa.border)),
                child: Text('Bot', style: Sa.body(size: 9, color: Sa.muted)),
              ),
            ]),
          ]),
        ),
        GlowChip(label: state.toUpperCase(), color: c),
      ]),
    );
  }

  // ── helpers ──
  Widget _panel(String label, IconData ic, Widget child) {
    return GlassPanel(
      accent: widget.spec.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(ic, size: 14, color: Sa.muted), const SizedBox(width: 7), Text(label, style: Sa.body(size: 11, color: Sa.muted))]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String _ago(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Color _statusColor(String s) {
    s = s.toLowerCase();
    if (s.contains('success') || s.contains('complet')) return _gGreen;
    if (s.contains('fail') || s.contains('cancel')) return _gRed;
    if (s.contains('progress') || s.contains('queued') || s.contains('pending')) return _gAmber;
    return Sa.muted;
  }

  IconData _statusIcon(String s) {
    s = s.toLowerCase();
    if (s.contains('success') || s.contains('complet')) return Icons.check_circle;
    if (s.contains('fail') || s.contains('cancel')) return Icons.cancel;
    return Icons.sync;
  }

  Future<void> _saveSetting(String k, dynamic v) =>
      _cfg.child('settings').update({k: v, 'updatedAt': DateTime.now().toUtc().toIso8601String()});

  Future<void> _dismissIncident() async {
    _simTimer?.cancel();
    await _cfg.child('activeRun').remove();
  }

  Future<void> _simulateIncident(String title, String severity, String description, String model) async {
    _simTimer?.cancel();
    final stages = ['detect', 'context', 'fix', 'review', 'gate', 'deploy'];
    String line(String st) {
      switch (st) {
        case 'detect':
          return 'detect   > $description';
        case 'context':
          return 'context  > pulling source files + stack traces + DB state';
        case 'fix':
          return 'fix      > $model generating minimal patch…';
        case 'review':
          return 'review   > flutter analyze + flutter test + AI review…';
        case 'gate':
          return 'gate     > tests passed, review approved';
        default:
          return _deployAuto ? 'deploy   > merged to main, production live' : 'deploy   > opened PR, awaiting human review';
      }
    }

    final logs = <String>['[${_ts()}] incident: $title ($severity)', '[${_ts()}] ${line('detect')}'];
    await _cfg.child('activeRun').set({
      'title': title, 'severity': severity, 'description': description, 'model': model,
      'stage': 'detect', 'status': 'running', 'log': logs, 'simulated': true,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    FirebaseDatabase.instance.ref('bugs/client').push().set({
      'area': 'simulation', 'severity': severity, 'message': description,
      'at': DateTime.now().toUtc().toIso8601String(), 'simulated': true,
    });
    var i = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 1700), (t) async {
      i++;
      if (i >= stages.length) {
        t.cancel();
        logs.add('[${_ts()}] ${line('deploy')}');
        logs.add('[${_ts()}] ${_deployAuto ? '✔ resolved & deployed' : '✔ PR opened — awaiting review'}');
        await _cfg.child('activeRun').update({'stage': 'deploy', 'status': _deployAuto ? 'deployed' : 'pr_open', 'log': logs});
        return;
      }
      logs.add('[${_ts()}] ${line(stages[i])}');
      await _cfg.child('activeRun').update({'stage': stages[i], 'status': 'running', 'log': logs});
    });
  }

  Future<void> _deleteMd(String key, int index) async {
    final snap = await _cfg.child(key).get();
    if (snap.value is! List) return;
    final list = List<dynamic>.from(snap.value as List);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _cfg.child(key).set(list);
  }

  Future<void> _pickProvider(String role, Map settings) async {
    final chosen = await showModalBottomSheet<_Provider>(
      context: context,
      backgroundColor: Sa.panelSolid,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in _Providers.list)
              ListTile(
                leading: Icon(Icons.bolt, color: p.color),
                title: Text(p.name, style: Sa.body(size: 14, color: Sa.text)),
                subtitle: Text(p.defaultModel.isEmpty ? 'custom endpoint' : p.defaultModel, style: Sa.body(size: 11, color: Sa.muted)),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ]),
        ),
      ),
    );
    if (chosen != null) {
      await _saveSetting('${role}Provider', chosen.id);
      await _saveSetting('${role}Model', chosen.defaultModel);
    }
  }

  Future<void> _setSecret(String field, String title, String hint) async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text(title, style: Sa.body(size: 15, color: Sa.text)),
        content: TextField(controller: ctl, obscureText: true,
            style: Sa.body(size: 13, color: Sa.text),
            decoration: InputDecoration(hintText: hint, hintStyle: Sa.body(size: 13, color: Sa.muted), border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text('Save', style: Sa.body(size: 13, color: Sa.cyan))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      await _sec.update({field: v, 'updatedAt': DateTime.now().toUtc().toIso8601String()});
      final s = await _sec.get();
      if (mounted && s.value is Map) setState(() => _secrets = s.value as Map<dynamic, dynamic>);
    }
  }

  Future<void> _setRepo() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text('Link GitHub repository', style: Sa.body(size: 15, color: Sa.text)),
        content: TextField(controller: ctl,
            style: Sa.body(size: 13, color: Sa.text),
            decoration: InputDecoration(hintText: 'owner/repository', hintStyle: Sa.body(size: 13, color: Sa.muted), border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text('Save', style: Sa.body(size: 13, color: Sa.cyan))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      await _cfg.update({'repo': v});
      _loadGithub();
    }
  }

  Future<void> _uploadMd(String key) async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['md'], withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: true);
    final snap = await _cfg.child(key).get();
    final list = (snap.value is List) ? List<dynamic>.from(snap.value as List) : <dynamic>[];
    list.add({'name': f.name, 'content': content, 'at': DateTime.now().toUtc().toIso8601String()});
    await _cfg.child(key).set(list);
  }
}

class _GuardianScanPainter extends CustomPainter {
  final Color color;
  final Animation<double> tick;
  _GuardianScanPainter({required this.color, required this.tick})
      : super(repaint: tick);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final t = tick.value;
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(
        c,
        r * i / 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = color.withValues(alpha: 0.22),
      );
    }
    // Sweeping radar beam.
    final angle = t * math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1),
      angle,
      0.7,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: angle,
          endAngle: angle + 0.7,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.35)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Expanding maintenance pulse.
    final pulse = (t * 2) % 1.0;
    canvas.drawCircle(
      c,
      r * pulse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: (1 - pulse) * 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _GuardianScanPainter old) =>
      old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM AGENTS · ICON PALETTE
// ═══════════════════════════════════════════════════════════════════════════

/// Fixed icon palette for operator-created agents. Keys (not raw code points)
/// are stored in RTDB so every [IconData] used by the app stays const — that
/// keeps Flutter's release icon tree-shaking working.
const Map<String, IconData> _kAgentIcons = {
  'robot': Icons.smart_toy_outlined,
  'bolt': Icons.bolt,
  'shield': Icons.shield_outlined,
  'brain': Icons.psychology_outlined,
  'radar': Icons.radar,
  'chat': Icons.forum_outlined,
  'eye': Icons.visibility_outlined,
  'gear': Icons.settings_suggest_outlined,
  'rocket': Icons.rocket_launch_outlined,
  'chart': Icons.insights_outlined,
  'flask': Icons.science_outlined,
  'hub': Icons.hub_outlined,
  'translate': Icons.translate,
  'inventory': Icons.inventory_2_outlined,
  'bug': Icons.bug_report_outlined,
  'bell': Icons.notifications_active_outlined,
};

const List<int> _kAccentSwatches = [
  0x22D3EE,
  0x3B82F6,
  0xA78BFA,
  0x34D399,
  0xFBBF24,
  0xF87171,
  0xF472B6,
  0xF6821F,
  0x10A37F,
  0x64748B,
];

String _hexOf(int rgb) => rgb.toRadixString(16).padLeft(6, '0');

/// Decode-resize-PNG-encode an uploaded logo to a small base64 string so the
/// registry record stays light (the screen streams it live). Falls back to the
/// raw bytes when decoding is unavailable and the file is already small.
Future<String?> _encodeLogoBase64(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 192);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data != null) return base64Encode(data.buffer.asUint8List());
  } catch (_) {}
  if (bytes.length <= 220 * 1024) return base64Encode(bytes);
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM AGENT · DETAIL PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _CustomAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomAgentPanel({
    required this.spec,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CustomAgentPanel> createState() => _CustomAgentPanelState();
}

class _CustomAgentPanelState extends State<_CustomAgentPanel> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final provider = _Providers.of(spec.provider);
    final token = (spec.apiToken ?? '');
    final masked = token.isEmpty
        ? 'NO CREDENTIAL ON FILE'
        : token.length <= 4
            ? '••••'
            : '${'•' * (token.length - 4).clamp(4, 24)}${token.substring(token.length - 4)}';

    return _AgentScroll(children: [
      if (!widget.enabled) _OfflineBanner(spec: spec),
      // ── HERO ──────────────────────────────────────────────────────────
      GlassPanel(
        accent: spec.accent,
        glow: widget.enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: spec.icon,
              leading: _AgentGlyph(spec: spec, size: 36, radius: 10),
              title: spec.name,
              subtitle: spec.codename,
              accent: spec.accent,
              trailing: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GlowChip(
                    label: 'CUSTOM UNIT',
                    color: spec.accent,
                    icon: Icons.auto_awesome,
                  ),
                  GlowChip(
                    label: widget.enabled ? 'ONLINE' : 'OFFLINE',
                    color: widget.enabled ? Sa.green : Sa.muted,
                    pulse: widget.enabled,
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
                  label: 'Provider',
                  value: provider.name,
                  icon: Icons.cloud_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Model',
                  value: (spec.model ?? '').isEmpty ? '—' : spec.model!,
                  icon: Icons.memory,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'Credential',
                  value: token.isEmpty ? 'MISSING' : 'ON FILE',
                  icon: Icons.vpn_key_outlined,
                  color: token.isEmpty ? Sa.amber : Sa.green,
                ),
                SaStatTile(
                  label: 'Deployed',
                  value: _agoIso(spec.createdAt),
                  icon: Icons.schedule,
                  color: Sa.muted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SaButton(
                  label: 'EDIT AGENT',
                  icon: Icons.tune,
                  color: spec.accent,
                  outlined: true,
                  onPressed: widget.onEdit,
                ),
                const SizedBox(width: 10),
                SaButton(
                  label: 'DELETE',
                  icon: Icons.delete_forever_outlined,
                  color: Sa.red,
                  outlined: true,
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
      // ── PROFILE ───────────────────────────────────────────────────────
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.badge_outlined,
              title: 'PROFILE',
              subtitle: 'Who this agent is and what it stands for.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if ((spec.description ?? '').trim().isEmpty)
              Text('No description provided.',
                  style: Sa.body(size: 12, color: Sa.textDim))
            else
              Text(spec.description!, style: Sa.body(size: 12.5)),
          ],
        ),
      ),
      // ── MISSION / TASKS ───────────────────────────────────────────────
      _CustomDocPanel(
        icon: Icons.assignment_outlined,
        title: 'MISSION BRIEF',
        subtitle: 'The tasks this agent is responsible for.',
        accent: spec.accent,
        body: spec.tasks ?? '',
        fileName: spec.tasksFile,
        emptyMsg: 'No tasks defined yet — edit the agent to brief it.',
      ),
      // ── SKILLS ────────────────────────────────────────────────────────
      _CustomDocPanel(
        icon: Icons.school_outlined,
        title: 'SKILLS & CAPABILITIES',
        subtitle: 'What this agent knows how to do.',
        accent: spec.accent,
        body: spec.skills ?? '',
        fileName: spec.skillsFile,
        emptyMsg: 'No skills listed yet.',
      ),
      // ── CREDENTIALS ───────────────────────────────────────────────────
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.vpn_key_outlined,
              title: 'CREDENTIALS',
              subtitle:
                  'The LLM provider and API token this agent authenticates with.',
              accent: spec.accent,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: provider.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: provider.color.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                      child: _ProviderLogo(
                          provider: provider, size: 28, color: provider.color)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.name, style: Sa.heading(size: 14)),
                      Text(
                        (spec.model ?? '').isEmpty
                            ? 'Default model'
                            : spec.model!,
                        style: Sa.mono(size: 10.5, color: Sa.textDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Sa.termBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Sa.termBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.key, size: 14, color: Sa.termMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      _reveal && token.isNotEmpty ? token : masked,
                      style: Sa.mono(size: 11.5, color: Sa.termText),
                    ),
                  ),
                  if (token.isNotEmpty) ...[
                    IconButton(
                      tooltip: _reveal ? 'Hide' : 'Reveal',
                      onPressed: () => setState(() => _reveal = !_reveal),
                      icon: Icon(
                        _reveal
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: Sa.termDim,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: token));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor: Sa.panelSolid,
                          content: Text('Token copied to clipboard.',
                              style: Sa.body(size: 12.5)),
                        ));
                      },
                      icon: const Icon(Icons.copy_all_outlined,
                          size: 15, color: Sa.termDim),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: Sa.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Stored separately in a superadmin-only credential vault. Treat it as a secret — rotate it from EDIT AGENT if it leaks.',
                    style: Sa.body(size: 10.5, color: Sa.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Reusable read-only document panel (tasks / skills) with an optional source
/// file chip.
class _CustomDocPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String body;
  final String? fileName;
  final String emptyMsg;

  const _CustomDocPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.body,
    required this.fileName,
    required this.emptyMsg,
  });

  @override
  Widget build(BuildContext context) {
    final hasBody = body.trim().isNotEmpty;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            accent: accent,
            trailing: (fileName ?? '').isEmpty
                ? null
                : GlowChip(
                    label: fileName!.toUpperCase(),
                    color: accent,
                    icon: Icons.attach_file,
                  ),
          ),
          const SizedBox(height: 12),
          if (!hasBody)
            Text(emptyMsg, style: Sa.body(size: 12, color: Sa.textDim))
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Sa.termBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Sa.termBorder),
              ),
              child: SelectableText(body,
                  style: Sa.mono(size: 11.5, color: Sa.termText)),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AGENT EDITOR DIALOG (add / edit a custom agent)
// ═══════════════════════════════════════════════════════════════════════════

class _AgentEditorDialog extends StatefulWidget {
  final _AgentSpec? editing;
  const _AgentEditorDialog({this.editing});

  @override
  State<_AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends State<_AgentEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _codename;
  late final TextEditingController _description;
  late final TextEditingController _tasks;
  late final TextEditingController _skills;
  late final TextEditingController _model;
  late final TextEditingController _token;

  String? _logoData;
  bool _logoBusy = false;
  String _iconKey = 'robot';
  String _accentHex = '22D3EE';
  String? _provider;
  String? _tasksFile;
  String? _skillsFile;
  bool _revealToken = false;
  bool _modelEdited = false;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = TextEditingController(text: e?.name ?? '');
    _codename = TextEditingController(
        text: (e?.codename ?? '') == 'CUSTOM UNIT' ? '' : (e?.codename ?? ''));
    _description = TextEditingController(text: e?.description ?? '');
    _tasks = TextEditingController(text: e?.tasks ?? '');
    _skills = TextEditingController(text: e?.skills ?? '');
    _model = TextEditingController(text: e?.model ?? '');
    _token = TextEditingController(text: e?.apiToken ?? '');
    _logoData = e?.logoData;
    _tasksFile = e?.tasksFile;
    _skillsFile = e?.skillsFile;
    _provider = (e?.provider ?? '').isEmpty ? null : e!.provider;
    _accentHex = (e?.accentHex ?? '').isEmpty ? '22D3EE' : e!.accentHex!;
    _modelEdited = (e?.model ?? '').isNotEmpty;
    // Resolve the stored icon back to its palette key.
    if (e != null) {
      _kAgentIcons.forEach((k, v) {
        if (v == e.icon) _iconKey = k;
      });
    }
    _model.addListener(() => _modelEdited = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _codename.dispose();
    _description.dispose();
    _tasks.dispose();
    _skills.dispose();
    _model.dispose();
    _token.dispose();
    super.dispose();
  }

  Color get _accent {
    final v = int.tryParse(_accentHex, radix: 16);
    return v == null ? Sa.cyan : Color(0xFF000000 | v);
  }

  Future<void> _attachLogo() async {
    setState(() => _logoBusy = true);
    try {
      final res =
          await FilePicker.pickFiles(type: FileType.image, withData: true);
      final files = res?.files ?? const [];
      final bytes = files.isNotEmpty ? files.first.bytes : null;
      if (bytes != null) {
        final encoded = await _encodeLogoBase64(bytes);
        if (encoded != null && mounted) setState(() => _logoData = encoded);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _attachText({required bool tasks}) async {
    try {
      final res = await FilePicker.pickFiles(withData: true);
      final files = res?.files ?? const [];
      if (files.isEmpty) return;
      final f = files.first;
      String? content;
      final bytes = f.bytes;
      if (bytes != null && bytes.length <= 200 * 1024) {
        try {
          content = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {}
      }
      setState(() {
        if (tasks) {
          _tasksFile = f.name;
          if (content != null && content.trim().isNotEmpty) {
            _tasks.text = content;
          }
        } else {
          _skillsFile = f.name;
          if (content != null && content.trim().isNotEmpty) {
            _skills.text = content;
          }
        }
      });
    } catch (_) {}
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _provider == null) {
      setState(() => _showError = true);
      return;
    }
    final map = <String, dynamic>{
      'name': name.toUpperCase(),
      'codename': _codename.text.trim().isEmpty
          ? 'CUSTOM UNIT'
          : _codename.text.trim().toUpperCase(),
      'description': _description.text.trim(),
      'tasks': _tasks.text.trim(),
      'skills': _skills.text.trim(),
      'provider': _provider,
      'model': _model.text.trim(),
      'apiToken': _token.text.trim(),
      'iconKey': _iconKey,
      'accentHex': _accentHex,
    };
    if ((_logoData ?? '').isNotEmpty) map['logoData'] = _logoData;
    if ((_tasksFile ?? '').isNotEmpty) map['tasksFile'] = _tasksFile;
    if ((_skillsFile ?? '').isNotEmpty) map['skillsFile'] = _skillsFile;
    Navigator.pop(context, map);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final editing = widget.editing != null;
    final logoBytes = () {
      final d = _logoData;
      if (d == null || d.isEmpty) return null;
      try {
        return base64Decode(d.contains(',') ? d.split(',').last : d);
      } catch (_) {
        return null;
      }
    }();

    return Dialog(
      backgroundColor: Sa.panelSolid,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.45)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  accent.withValues(alpha: Sa.isDark ? 0.18 : 0.10),
                  Colors.transparent,
                ]),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        accent.withValues(alpha: 0.3),
                        accent.withValues(alpha: 0.08),
                      ]),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: logoBytes != null
                        ? Padding(
                            padding: const EdgeInsets.all(5),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(logoBytes,
                                  fit: BoxFit.cover, gaplessPlayback: true),
                            ),
                          )
                        : Icon(_kAgentIcons[_iconKey], color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(editing ? 'EDIT AGENT' : 'DEPLOY NEW AGENT',
                            style: Sa.display(size: 16)),
                        Text(
                          'Configure a custom autonomous unit for the fleet',
                          style: Sa.mono(size: 9, color: Sa.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 18, color: Sa.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Sa.border),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('IDENTITY', accent),
                    const SizedBox(height: 10),
                    _textField(_name,
                        hint: 'Agent name (e.g. Quality Inspector)',
                        icon: Icons.badge_outlined),
                    const SizedBox(height: 10),
                    _textField(_codename,
                        hint: 'Codename (optional, e.g. UNIT-07 · SENTRY)',
                        icon: Icons.tag),
                    const SizedBox(height: 10),
                    _textField(_description,
                        hint: 'Short description of what this agent is for',
                        icon: Icons.notes_outlined,
                        maxLines: 2),
                    const SizedBox(height: 20),

                    _label('APPEARANCE', accent),
                    const SizedBox(height: 10),
                    _appearanceRow(accent, logoBytes != null),
                    const SizedBox(height: 20),

                    _label('MISSION · TASKS', accent),
                    const SizedBox(height: 6),
                    Text(
                      'Describe the tasks, or attach a brief / spec file.',
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                    const SizedBox(height: 10),
                    _textField(_tasks,
                        hint:
                            'e.g. Review incoming quality alerts, draft a containment checklist…',
                        maxLines: 4),
                    const SizedBox(height: 8),
                    _attachRow(
                      fileName: _tasksFile,
                      onAttach: () => _attachText(tasks: true),
                      onClear: () => setState(() => _tasksFile = null),
                      accent: accent,
                    ),
                    const SizedBox(height: 20),

                    _label('SKILLS · CAPABILITIES', accent),
                    const SizedBox(height: 6),
                    Text(
                      'List the skills, or attach a capability sheet.',
                      style: Sa.body(size: 10.5, color: Sa.textDim),
                    ),
                    const SizedBox(height: 10),
                    _textField(_skills,
                        hint:
                            'e.g. Root-cause analysis, ISO 9001 knowledge, French + English…',
                        maxLines: 4),
                    const SizedBox(height: 8),
                    _attachRow(
                      fileName: _skillsFile,
                      onAttach: () => _attachText(tasks: false),
                      onClear: () => setState(() => _skillsFile = null),
                      accent: accent,
                    ),
                    const SizedBox(height: 20),

                    _label('MODEL PROVIDER', accent),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final p in _Providers.list)
                          _ProviderTile(
                            provider: p,
                            selected: _provider == p.id,
                            onTap: () => setState(() {
                              _provider = p.id;
                              if (!_modelEdited) {
                                _model.text = p.defaultModel;
                                _modelEdited = false;
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _textField(_model,
                        hint: 'Model id (e.g. ${_providerHint()})',
                        icon: Icons.memory),
                    const SizedBox(height: 12),
                    _textField(
                      _token,
                      hint: _provider == null
                          ? 'API token / key'
                          : 'API token — ${_Providers.of(_provider).tokenHint}',
                      icon: Icons.vpn_key_outlined,
                      obscure: !_revealToken,
                      suffix: IconButton(
                        onPressed: () =>
                            setState(() => _revealToken = !_revealToken),
                        icon: Icon(
                          _revealToken
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16,
                          color: Sa.muted,
                        ),
                      ),
                    ),
                    if (_showError) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.error_outline, size: 14, color: Sa.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'A name and a model provider are required.',
                              style: Sa.body(size: 11.5, color: Sa.red),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: Sa.border),
            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SaButton(
                    label: 'CANCEL',
                    icon: Icons.close,
                    color: Sa.muted,
                    outlined: true,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  SaButton(
                    label: editing ? 'SAVE CHANGES' : 'DEPLOY AGENT',
                    icon: editing ? Icons.save_outlined : Icons.rocket_launch,
                    color: accent,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _providerHint() =>
      _provider == null ? 'gpt-4o' : _Providers.of(_provider).defaultModel;

  Widget _label(String text, Color accent) => Row(
        children: [
          Container(width: 3, height: 14, color: accent),
          const SizedBox(width: 8),
          Text(text, style: Sa.heading(size: 12.5, color: accent)),
        ],
      );

  Widget _textField(
    TextEditingController c, {
    String? hint,
    IconData? icon,
    int maxLines = 1,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: c,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      style: Sa.body(size: 13),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: Sa.body(size: 12, color: Sa.muted),
        prefixIcon:
            icon != null ? Icon(icon, size: 17, color: Sa.muted) : null,
        suffixIcon: suffix,
        isDense: true,
        filled: true,
        fillColor: Sa.bgRaised.withValues(alpha: 0.6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Sa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accent),
        ),
      ),
    );
  }

  Widget _appearanceRow(Color accent, bool hasLogo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SaButton(
              label: hasLogo ? 'REPLACE LOGO' : 'UPLOAD LOGO',
              icon: Icons.image_outlined,
              color: accent,
              outlined: true,
              busy: _logoBusy,
              onPressed: _attachLogo,
            ),
            const SizedBox(width: 10),
            if (hasLogo)
              SaButton(
                label: 'REMOVE',
                icon: Icons.delete_outline,
                color: Sa.red,
                outlined: true,
                onPressed: () => setState(() => _logoData = null),
              ),
            const Spacer(),
            Text(hasLogo ? 'Custom logo set' : 'No logo · pick an icon',
                style: Sa.mono(size: 9, color: Sa.muted)),
          ],
        ),
        if (!hasLogo) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _kAgentIcons.entries)
                GestureDetector(
                  onTap: () => setState(() => _iconKey = entry.key),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _iconKey == entry.key
                          ? accent.withValues(alpha: 0.16)
                          : Sa.bgRaised.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _iconKey == entry.key ? accent : Sa.border,
                        width: _iconKey == entry.key ? 1.4 : 1,
                      ),
                    ),
                    child: Icon(entry.value,
                        size: 18,
                        color: _iconKey == entry.key ? accent : Sa.textDim),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Text('ACCENT', style: Sa.mono(size: 9, color: Sa.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rgb in _kAccentSwatches)
                    GestureDetector(
                      onTap: () => setState(() => _accentHex = _hexOf(rgb)),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | rgb),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _accentHex == _hexOf(rgb)
                                ? Sa.text
                                : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: [
                            if (_accentHex == _hexOf(rgb))
                              BoxShadow(
                                  color: Color(0xFF000000 | rgb)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _attachRow({
    required String? fileName,
    required VoidCallback onAttach,
    required VoidCallback onClear,
    required Color accent,
  }) {
    return Row(
      children: [
        InkWell(
          onTap: onAttach,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.upload_file_outlined, size: 15, color: accent),
                const SizedBox(width: 6),
                Text('ATTACH FILE',
                    style: Sa.mono(
                        size: 9.5, color: accent, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        if ((fileName ?? '').isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Sa.bgRaised.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Sa.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 12, color: Sa.textDim),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Sa.mono(size: 9.5, color: Sa.textDim)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(Icons.close, size: 12, color: Sa.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DELETE CONFIRMATION (blood red)
// ═══════════════════════════════════════════════════════════════════════════

class _DeleteAgentDialog extends StatefulWidget {
  final _AgentSpec agent;
  const _DeleteAgentDialog({required this.agent});

  @override
  State<_DeleteAgentDialog> createState() => _DeleteAgentDialogState();
}

class _DeleteAgentDialogState extends State<_DeleteAgentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  static const Color _blood = Color(0xFFE11D2E);
  static const Color _bloodDeep = Color(0xFF7F0E18);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A0608),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _blood, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Stack(
          children: [
            // Pulsing danger glow.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.7),
                      radius: 1.2,
                      colors: [
                        _blood.withValues(alpha: 0.12 + 0.10 * _c.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (_, __) => Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [_blood, _bloodDeep],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _blood
                                .withValues(alpha: 0.4 + 0.3 * _c.value),
                            blurRadius: 24 + 10 * _c.value,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 38),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'DECOMMISSION AGENT',
                    style: Sa.display(size: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _blood.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _blood.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      widget.agent.name,
                      style: Sa.mono(
                          size: 11,
                          color: const Color(0xFFFFB4BC),
                          weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This permanently removes the agent, its mission brief, skills and stored API credential from the fleet registry.\n\nThis action cannot be undone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Color(0xFFE9C4C8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE9C4C8),
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.25)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('CANCEL',
                              style: Sa.heading(
                                  size: 12.5,
                                  color: const Color(0xFFE9C4C8))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: _blood,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.delete_forever,
                                  size: 17, color: Colors.white),
                              const SizedBox(width: 8),
                              Text('DELETE PERMANENTLY',
                                  style: Sa.heading(
                                      size: 12.5, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

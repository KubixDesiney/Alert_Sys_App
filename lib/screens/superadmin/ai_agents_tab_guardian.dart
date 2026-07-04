// Guardian panel: Control / Actions / Pull Requests subtabs, deploy-mode
// switch + automatic-mode warning, GitHub connection config, incident drills.
//
// This is a part file of ai_agents_tab.dart (one library, split for
// maintainability); private identifiers are shared across all parts.
part of 'ai_agents_tab.dart';

class _GuardianAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  const _GuardianAgentPanel({required this.spec});

  @override
  State<_GuardianAgentPanel> createState() => _GuardianAgentPanelState();
}

class _GuardianAgentPanelState extends State<_GuardianAgentPanel> {
  // The GitHub proxy worker URL + shared secret come from build-time config so
  // the live Actions/PR subtabs work in CI builds without per-widget defines.
  static const _ghUrl = AppConfig.githubWorkerBase;
  static const _wSecret = AppConfig.workerSharedSecret;

  final _cfg = FirebaseDatabase.instance.ref('ai_agents/guardian');
  final _sec = FirebaseDatabase.instance.ref('ai_agent_secrets/guardian');

  static const _gGreen = Color(0xFF3FB950);
  static const _gRed = Color(0xFFF85149);
  static const _gAmber = Color(0xFFD29922);
  static const _gPurple = Color(0xFFA371F7);

  // Non-secret presence flags ({field: true}) mirrored under
  // ai_agents/guardian/secretFlags. The secrets themselves live in the
  // worker-only ai_agent_secrets vault and are never read by the client.
  Map<dynamic, dynamic> _secretFlags = {};
  Offset _simOffset = const Offset(10, 96);
  bool _deployAuto = false;
  Timer? _simTimer;
  int _subtab = 0; // 0 = Control · 1 = Actions · 2 = Pull requests

  // Live GitHub engine: drives the 3D pipeline + terminal + connection badge.
  late final GuardianLiveTracker _tracker = GuardianLiveTracker(
    baseUrl: _ghUrl,
    secret: _wSecret,
  );

  // One-shot "verify connection" affordance state.
  bool _verifying = false;
  bool? _verifyOk;
  String _verifyMsg = '';

  @override
  void initState() {
    super.initState();
    _tracker.start();
    // Presence flags arrive via the _cfg stream (ai_agents/guardian); the
    // secret vault is never read by the client.
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _tracker.dispose();
    super.dispose();
  }

  bool _hasSecret(String k) => _secretFlags[k] == true;
  String _ts() => DateTime.now().toIso8601String().substring(11, 19);

  bool _githubLatched(Map cfg) {
    if (cfg['githubConnected'] != true) return false;
    final repo = GithubService.normalizeRepo((cfg['repo'] ?? '').toString());
    final verifiedRepo = GithubService.normalizeRepo(
      (cfg['githubVerifiedRepo'] ?? '').toString(),
    );
    return repo.isNotEmpty && (verifiedRepo.isEmpty || verifiedRepo == repo);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _cfg.onValue,
      builder: (context, snap) {
        final raw = snap.data?.snapshot.value;
        final cfg = (raw is Map) ? raw : const {};
        _secretFlags =
            (cfg['secretFlags'] is Map) ? cfg['secretFlags'] as Map : const {};
        final settings = (cfg['settings'] is Map)
            ? cfg['settings'] as Map
            : const {};
        final enabled = cfg['enabled'] != false;
        final repo = GithubService.normalizeRepo(
          (cfg['repo'] ?? '').toString(),
        );
        final githubLatched = _githubLatched(cfg);
        if (raw is Map) _tracker.setRepo(repo);
        _deployAuto = (settings['deployMode'] ?? 'human') == 'auto';
        _tracker.mode = _deployAuto ? 'auto' : 'human';
        return LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight.isFinite ? c.maxHeight : 1600.0;
            return SizedBox(
              height: h,
              child: Column(
                children: [
                  _subtabBar(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: IndexedStack(
                      index: _subtab,
                      children: [
                        _controlBody(cfg, settings, enabled),
                        GuardianActionsView(
                          baseUrl: _ghUrl,
                          sharedSecret: _wSecret,
                          repo: repo,
                          connectionLatched: githubLatched,
                        ),
                        GuardianPullsView(
                          baseUrl: _ghUrl,
                          sharedSecret: _wSecret,
                          repo: repo,
                          connectionLatched: githubLatched,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Subtab selector: Control · Actions · Pull requests. The two GitHub subtabs
  /// render in authentic GitHub styling inside [GuardianActionsView] /
  /// [GuardianPullsView]; this bar stays in the command-center theme.
  Widget _subtabBar() {
    const items = [
      (i: 0, label: 'CONTROL', icon: Icons.tune),
      (i: 1, label: 'ACTIONS', icon: Icons.sync_alt),
      (i: 2, label: 'PULL REQUESTS', icon: Icons.merge_type),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _subtab = it.i),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _subtab == it.i
                        ? widget.spec.accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _subtab == it.i
                          ? widget.spec.accent.withValues(alpha: 0.5)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        it.icon,
                        size: 15,
                        color: _subtab == it.i ? widget.spec.accent : Sa.muted,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          context.tr(it.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Sa.body(
                            size: 11.5,
                            color: _subtab == it.i
                                ? widget.spec.accent
                                : Sa.muted,
                          ),
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

  /// The Control subtab: header + live pipeline + terminal + AI/GitHub config.
  Widget _controlBody(Map cfg, Map settings, bool enabled) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      // Rebuild on every live-tracker tick so the pipeline, terminal and the
      // GitHub connection badge stay in lock-step with the real workflow run.
      child: ListenableBuilder(
        listenable: _tracker,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(enabled, settings),
            const SizedBox(height: 14),
            _livePipeline(settings, cfg),
            const SizedBox(height: 14),
            _liveTerminal(),
            const SizedBox(height: 14),
            _aiConfig(settings),
            const SizedBox(height: 14),
            _github(cfg),
            const SizedBox(height: 14),
            _knowledge(cfg),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // Legacy drill helper, kept private and unreachable from the UI.
  // ignore: unused_element
  Widget _simToolbar() {
    final sims = <List<dynamic>>[
      [
        'Login error',
        Icons.login,
        'high',
        'login screen error — users cannot sign in',
        'claude-opus-4-8',
      ],
      [
        'Notifications',
        Icons.notifications_off,
        'high',
        'alerts not reaching supervisors',
        'claude-opus-4-8',
      ],
      [
        'Worker fail',
        Icons.dns,
        'high',
        'cloudflare worker endpoint failing',
        'claude-opus-4-8',
      ],
      [
        'Version',
        Icons.sync_problem,
        'medium',
        'dependency version mismatch breaks build',
        'claude-sonnet-4-6',
      ],
      [
        'Tab broken',
        Icons.tab_unselected,
        'medium',
        'supervisor tab blank / not loading',
        'claude-sonnet-4-6',
      ],
      [
        'Test fail',
        Icons.science,
        'low',
        'flutter test failing on a widget test',
        'claude-haiku-4-5',
      ],
    ];
    return Container(
      width: 166,
      decoration: BoxDecoration(
        color: Sa.panelSolid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.borderBright),
        boxShadow: [
          BoxShadow(
            color: Sa.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.drag_indicator, size: 15, color: Sa.muted),
                  const SizedBox(width: 5),
                  Text('', style: Sa.body(size: 10.5, color: Sa.textDim)),
                ],
              ),
            ),
          ),
          for (final s in sims)
            InkWell(
              onTap: () => _simulateIncident(
                s[0] as String,
                s[2] as String,
                s[3] as String,
                s[4] as String,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      s[1] as IconData,
                      size: 14,
                      color: s[2] == 'high'
                          ? _gRed
                          : (s[2] == 'medium' ? _gAmber : Sa.muted),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s[0] as String,
                      style: Sa.body(size: 12, color: Sa.text),
                    ),
                  ],
                ),
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
          SizedBox(
            width: 40,
            height: 40,
            child: _AgentGlyph(spec: widget.spec, size: 40, radius: 11),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('GUARDIAN'), style: Sa.display(size: 17)),
                Text(
                  context.tr('autonomous fix pipeline'),
                  style: Sa.body(size: 12, color: Sa.muted),
                ),
              ],
            ),
          ),
          _deployToggle(
            context.tr('Automatic'),
            _deployAuto,
            _confirmAutomaticMode,
          ),
          const SizedBox(width: 6),
          _deployToggle(
            context.tr('Human review'),
            !_deployAuto,
            () => _saveSetting('deployMode', 'human'),
          ),
          const SizedBox(width: 12),
          GlowChip(
            label: enabled ? context.tr('ARMED') : context.tr('OFF'),
            color: enabled ? _gGreen : Sa.muted,
            pulse: enabled,
          ),
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
          color: active
              ? widget.spec.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? widget.spec.accent.withValues(alpha: 0.5)
                : Sa.border,
          ),
        ),
        child: Text(
          label,
          style: Sa.body(
            size: 11.5,
            color: active ? widget.spec.accent : Sa.textDim,
          ),
        ),
      ),
    );
  }

  // ── live 3D pipeline (driven by the real GitHub run) ──
  Widget _livePipeline(Map settings, Map cfg) {
    final liveConnected = _tracker.connected;
    final connected = liveConnected || _githubLatched(cfg);
    final nodes = liveConnected
        ? _tracker.nodes
        : computePipelineNodes(
            connected: connected,
            frontier: 0,
            failPhase: -1,
            done: false,
            running: false,
            idleArmed: connected,
            mode: 'human',
          );
    return GuardianPipeline(
      nodes: nodes,
      connected: connected,
      statusLabel: liveConnected
          ? _tracker.stageLabel
          : connected
          ? context.tr('Connected - waiting for live sync')
          : _tracker.stageLabel,
      failed: liveConnected && _tracker.failed,
      running: liveConnected && _tracker.running,
      fixAiLabel: _aiSchemaLabel(settings, 'fix'),
      reviewAiLabel: _aiSchemaLabel(settings, 'review'),
    );
  }

  // ── live terminal (real job/step + raw stdout, or offline preview) ──
  Widget _liveTerminal() {
    return GuardianTerminal(tracker: _tracker);
  }

  String _aiSchemaLabel(Map settings, String role) {
    final provId =
        (settings['${role}Provider'] ??
                (role == 'fix' ? 'anthropic' : 'openai'))
            .toString();
    final prov = _Providers.list.firstWhere(
      (p) => p.id == provId,
      orElse: () => _Providers.list.first,
    );
    final model = (settings['${role}Model'] ?? prov.defaultModel).toString();
    return model.isEmpty ? prov.name : '${prov.name} - $model';
  }

  // ── AI config ──
  Widget _aiConfig(Map settings) {
    final auto = settings['autoModelSelect'] != false;
    return _panel(
      context.tr('AI CONFIGURATION'),
      Icons.memory,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _aiCard(context.tr('Fix AI'), 'fix', settings, Sa.blue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _aiCard(
                  context.tr('Review AI'),
                  'review',
                  settings,
                  _gPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                context.tr('Auto-select model by severity'),
                style: Sa.body(size: 12, color: Sa.textDim),
              ),
              const Spacer(),
              Switch(
                value: auto,
                onChanged: (v) => _saveSetting('autoModelSelect', v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiCard(String title, String role, Map settings, Color accent) {
    final provId =
        (settings['${role}Provider'] ??
                (role == 'fix' ? 'anthropic' : 'openai'))
            .toString();
    final prov = _Providers.list.firstWhere(
      (p) => p.id == provId,
      orElse: () => _Providers.list.first,
    );
    final model = (settings['${role}Model'] ?? prov.defaultModel).toString();
    final keySet = _hasSecret('${role}ApiKey');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Sa.bgRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Sa.body(size: 12.5, color: accent)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickProvider(role, settings),
            child: _fieldRow(Icons.expand_more, '${prov.name} · $model'),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _setSecret(
              '${role}ApiKey',
              context.tr('{title} API key', {'title': title}),
              prov.tokenHint,
            ),
            child: _fieldRow(
              Icons.key,
              keySet ? context.tr('•••••••• set') : context.tr('set API key'),
              trailing: keySet
                  ? Icon(Icons.check, size: 14, color: _gGreen)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(IconData ic, String text, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Sa.bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          Icon(ic, size: 14, color: Sa.muted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: Sa.body(size: 12, color: Sa.text),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ── github connection ──
  Widget _github(Map cfg) {
    final repo = GithubService.normalizeRepo((cfg['repo'] ?? '').toString());
    return GlassPanel(
      accent: widget.spec.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 14, color: Sa.muted),
              const SizedBox(width: 7),
              Text(
                context.tr('GITHUB CONNECTION'),
                style: Sa.body(size: 11, color: Sa.muted),
              ),
              const Spacer(),
              _connBadge(cfg),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _setRepo(repo),
                  child: _fieldRow(
                    Icons.account_tree,
                    repo.isEmpty
                        ? context.tr('link repository (owner/name)')
                        : repo,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _setSecret(
                    'githubToken',
                    context.tr('GitHub token'),
                    'github_pat_…',
                  ),
                  child: Builder(builder: (_) {
                    // Presence flag, or a live worker-verified connection
                    // (covers instances upgraded before secretFlags existed).
                    final tokenSet =
                        _hasSecret('githubToken') || cfg['githubConnected'] == true;
                    return _fieldRow(
                      Icons.vpn_key,
                      tokenSet
                          ? context.tr('•••••••• set')
                          : context.tr('set token'),
                      trailing: tokenSet
                          ? Icon(Icons.check, size: 14, color: _gGreen)
                          : null,
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _verifyRow(repo),
        ],
      ),
    );
  }

  /// Live "Connected / Not connected" badge — fed by the same tracker that polls
  /// the proxy worker's /config, so it flips the moment the worker can reach the repo.
  Widget _connBadge(Map cfg) {
    final ok = _tracker.connected || _githubLatched(cfg);
    final c = ok ? _gGreen : _gRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            ok ? context.tr('Connected') : context.tr('Not connected'),
            style: Sa.body(size: 11, color: c),
          ),
        ],
      ),
    );
  }

  /// Verify button + animated result line: spinner → green check / red cross.
  Widget _verifyRow(String repo) {
    return Row(
      children: [
        SaButton(
          label: _verifying
              ? context.tr('Verifying…')
              : context.tr('Verify connection'),
          icon: Icons.wifi_tethering,
          outlined: true,
          onPressed: () {
            if (!_verifying) _verifyConnection(repo);
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                axis: Axis.horizontal,
                child: child,
              ),
            ),
            child: _verifyStatus(),
          ),
        ),
      ],
    );
  }

  Widget _verifyStatus() {
    if (_verifying) {
      return Row(
        key: const ValueKey('verifying'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: _gAmber),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.tr('contacting GitHub…'),
              overflow: TextOverflow.ellipsis,
              style: Sa.body(size: 11.5, color: Sa.textDim),
            ),
          ),
        ],
      );
    }
    if (_verifyOk == null) return const SizedBox.shrink();
    final ok = _verifyOk!;
    final c = ok ? _gGreen : _gRed;
    return Row(
      key: ValueKey('result_$ok'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.check_circle : Icons.error, size: 15, color: c),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _verifyMsg,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: Sa.body(size: 11.5, color: c),
          ),
        ),
      ],
    );
  }

  Future<void> _verifyConnection(String repo) async {
    setState(() {
      _verifying = true;
      _verifyOk = null;
      _verifyMsg = '';
    });
    final svc = GithubService(
      baseUrl: _ghUrl,
      sharedSecret: _wSecret,
      repo: repo,
    );
    ({bool ok, String repo, int runs, String message}) r;
    try {
      r = await svc.verify();
    } catch (error) {
      r = (
        ok: false,
        repo: '',
        runs: 0,
        message: context.tr(
          'Guardian proxy check failed before credentials were verified: {error}',
          {'error': '$error'},
        ),
      );
    } finally {
      svc.close();
    }
    if (!mounted) return;
    final verifiedRepo = GithubService.normalizeRepo(
      r.repo.isNotEmpty ? r.repo : repo,
    );
    if (r.ok) {
      final now = DateTime.now().toUtc().toIso8601String();
      await _cfg.update({
        if (verifiedRepo.isNotEmpty) 'repo': verifiedRepo,
        'githubConnected': true,
        'githubVerifiedAt': now,
        'githubVerifiedRepo': verifiedRepo,
        'githubConnectionMessage': r.message,
      });
      _tracker.rememberConnected(verifiedRepo);
    }
    setState(() {
      _verifying = false;
      _verifyOk = r.ok;
      _verifyMsg = r.message;
    });
    _tracker.refreshNow();
  }

  /// Guard rail: switching from human review to fully-automatic deploy ships AI
  /// fixes to production with no person in the loop, so confirm it deliberately.
  Future<void> _confirmAutomaticMode() async {
    if (_deployAuto) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AutomaticModeWarningDialog(),
    );
    if (ok == true) {
      await _saveSetting('deployMode', 'auto');
      _tracker.mode = 'auto';
    }
  }

  // ── knowledge ──
  Widget _knowledge(Map cfg) {
    List<String> listOf(String k) {
      final v = cfg[k];
      if (v is List)
        return v
            .map(
              (e) => e is Map ? (e['name'] ?? 'file').toString() : e.toString(),
            )
            .toList();
      return const [];
    }

    return _panel(
      context.tr('KNOWLEDGE · upload .md'),
      Icons.menu_book_outlined,
      Row(
        children: [
          Expanded(
            child: _mdColumn(
              context.tr('Instructions'),
              'instructions',
              listOf('instructions'),
              Sa.blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _mdColumn(
              context.tr('Skills'),
              'skills',
              listOf('skills'),
              _gGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mdColumn(String title, String key, List<String> files, Color accent) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Sa.bgRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: Sa.body(size: 12.5, color: accent)),
              const Spacer(),
              Text(
                '${files.length}',
                style: Sa.body(size: 11, color: Sa.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 13, color: Sa.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      files[i],
                      overflow: TextOverflow.ellipsis,
                      style: Sa.body(size: 11.5, color: Sa.textDim),
                    ),
                  ),
                  InkWell(
                    onTap: () => _deleteMd(key, i),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.delete_outline, size: 15, color: _gRed),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          SaButton(
            label: context.tr('Upload .md'),
            icon: Icons.upload_file,
            outlined: true,
            onPressed: () => _uploadMd(key),
          ),
        ],
      ),
    );
  }

  // ── helpers ──
  Widget _panel(String label, IconData ic, Widget child) {
    return GlassPanel(
      accent: widget.spec.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ic, size: 14, color: Sa.muted),
              const SizedBox(width: 7),
              Text(label, style: Sa.body(size: 11, color: Sa.muted)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Future<void> _saveSetting(String k, dynamic v) => _cfg
      .child('settings')
      .update({k: v, 'updatedAt': DateTime.now().toUtc().toIso8601String()});

  Future<void> _simulateIncident(
    String title,
    String severity,
    String description,
    String model,
  ) async {
    _simTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    final mode = _deployAuto ? 'automatic' : 'human';
    const target = 'tool/guardian_drill_target.mjs';

    // Register the drill in the bug pipeline so the rest of the platform sees it.
    FirebaseDatabase.instance.ref('bugs/client').push().set({
      'area': 'simulation',
      'severity': severity,
      'message': description,
      'at': DateTime.now().toUtc().toIso8601String(),
      'simulated': true,
    });

    var dispatched = false;
    if (_ghUrl.isNotEmpty) {
      final svc = GithubService(
        baseUrl: _ghUrl,
        sharedSecret: _wSecret,
        repo: _tracker.repo,
      );
      try {
        dispatched = await svc.dispatchDrill(mode: mode, target: target);
      } catch (_) {
      } finally {
        svc.close();
      }
    }

    if (dispatched) {
      // The REAL guardian-drill workflow now drives the pipeline + terminal,
      // stage by stage, straight from GitHub. No synthetic preview needed.
      _tracker.expectDrill();
      await _cfg.child('activeRun').remove();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            'Guardian drill dispatched on GitHub (mode=$mode) — the pipeline is now live.',
            style: Sa.body(size: 12.5, color: Sa.text),
          ),
        ),
      );
      return;
    }

    // Offline fallback: staged textual PREVIEW in the terminal (the pipeline
    // stays in its grey "not connected" state until the worker is linked).
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
          return _deployAuto
              ? 'deploy   > merged to main, production live'
              : 'deploy   > opened PR, awaiting human review';
      }
    }

    final logs = <String>[
      '[${_ts()}] dispatch  > local preview (link the GitHub worker to go live)',
      '[${_ts()}] incident: $title ($severity)',
      '[${_ts()}] ${line('detect')}',
    ];
    await _cfg.child('activeRun').set({
      'title': title,
      'severity': severity,
      'description': description,
      'model': model,
      'stage': 'detect',
      'status': 'running',
      'log': logs,
      'simulated': true,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    var i = 0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 1700), (t) async {
      i++;
      if (i >= stages.length) {
        t.cancel();
        logs.add('[${_ts()}] ${line('deploy')}');
        logs.add(
          '[${_ts()}] ${_deployAuto ? '✔ resolved & deployed' : '✔ PR opened — awaiting review'}',
        );
        await _cfg.child('activeRun').update({
          'stage': 'deploy',
          'status': _deployAuto ? 'deployed' : 'pr_open',
          'log': logs,
        });
        return;
      }
      logs.add('[${_ts()}] ${line(stages[i])}');
      await _cfg.child('activeRun').update({
        'stage': stages[i],
        'status': 'running',
        'log': logs,
      });
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in _Providers.list)
                ListTile(
                  leading: Icon(Icons.bolt, color: p.color),
                  title: Text(p.name, style: Sa.body(size: 14, color: Sa.text)),
                  subtitle: Text(
                    p.defaultModel.isEmpty
                        ? context.tr('custom endpoint')
                        : p.defaultModel,
                    style: Sa.body(size: 11, color: Sa.muted),
                  ),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
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
        content: TextField(
          controller: ctl,
          obscureText: true,
          style: Sa.body(size: 13, color: Sa.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: Sa.body(size: 13, color: Sa.muted),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text(
              context.tr('Save'),
              style: Sa.body(size: 13, color: Sa.cyan),
            ),
          ),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      // Secret value → worker-only vault (never read back by the client).
      await _sec.update({
        field: v,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      // Non-secret presence flag → client-readable config node.
      await _cfg.child('secretFlags').update({field: true});
      if (field == 'githubToken') {
        await _markGithubCredentialsChanged();
      }
    }
  }

  Future<void> _setRepo(String currentRepo) async {
    final ctl = TextEditingController(text: currentRepo);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text(
          context.tr('Link GitHub repository'),
          style: Sa.body(size: 15, color: Sa.text),
        ),
        content: TextField(
          controller: ctl,
          style: Sa.body(size: 13, color: Sa.text),
          decoration: InputDecoration(
            hintText: context.tr('owner/repository'),
            hintStyle: Sa.body(size: 13, color: Sa.muted),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text(
              context.tr('Save'),
              style: Sa.body(size: 13, color: Sa.cyan),
            ),
          ),
        ],
      ),
    );
    if (v != null) {
      final trimmed = v.trim();
      if (trimmed.isEmpty) {
        await _cfg.update({'repo': null});
        await _markGithubCredentialsChanged(repo: '');
        _tracker.setRepo('');
        if (mounted) {
          setState(() {
            _verifyOk = false;
            _verifyMsg = context.tr('GitHub repository cleared.');
          });
        }
        return;
      }
      final repo = GithubService.normalizeRepo(v);
      if (repo.isNotEmpty) {
        await _cfg.update({'repo': repo});
        await _markGithubCredentialsChanged(repo: repo);
        _tracker.setRepo(repo);
        return;
      }
      await _cfg.update({'repo': null});
      await _markGithubCredentialsChanged(repo: '');
      _tracker.setRepo('');
      if (mounted) {
        setState(() {
          _verifyOk = false;
          _verifyMsg = context.tr(
            'Invalid GitHub repository. Use owner/name or a GitHub URL.',
          );
        });
      }
    }
  }

  Future<void> _markGithubCredentialsChanged({String? repo}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final currentRepo = repo ?? _tracker.repo;
    GithubService.forgetCachedStatus(baseUrl: _ghUrl, repo: currentRepo);
    _tracker.forgetConnection();
    await _cfg.update({
      'githubConnected': false,
      'githubVerifiedAt': null,
      'githubVerifiedRepo': null,
      'githubConnectionMessage': null,
      'githubCredentialsUpdatedAt': now,
    });
  }

  Future<void> _uploadMd(String key) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: true);
    final snap = await _cfg.child(key).get();
    final list = (snap.value is List)
        ? List<dynamic>.from(snap.value as List)
        : <dynamic>[];
    list.add({
      'name': f.name,
      'content': content,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    await _cfg.child(key).set(list);
  }
}

/// Deliberate, premium warning before arming fully-autonomous deployment.
class _AutomaticModeWarningDialog extends StatelessWidget {
  const _AutomaticModeWarningDialog();

  static const _red = Color(0xFFF85149);
  static const _amber = Color(0xFFD29922);
  static const _green = Color(0xFF3FB950);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            color: Sa.panelSolid,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _red.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: _red.withValues(alpha: 0.18),
                blurRadius: 40,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _red.withValues(alpha: 0.22),
                      _amber.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _red.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _red.withValues(alpha: 0.5)),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: _red,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('Enable automatic deployment?'),
                            style: Sa.display(size: 16),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            context.tr(
                              'Guardian will ship fixes with no human in the loop',
                            ),
                            style: Sa.body(size: 12, color: Sa.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet(
                      Icons.merge,
                      context.tr('Verified AI fixes are pushed straight to '),
                      'main',
                      context.tr(' — no pull request, no review.'),
                    ),
                    _bullet(
                      Icons.rocket_launch_outlined,
                      context.tr('Each healed commit '),
                      context.tr('auto-deploys to production'),
                      context.tr(' (web + app builds).'),
                    ),
                    _bullet(
                      Icons.person_off_outlined,
                      context.tr('A person is only notified '),
                      context.tr('after the fact'),
                      context.tr(', or when a fix fails to verify.'),
                    ),
                    _bullet(
                      Icons.health_and_safety_outlined,
                      context.tr('A safety-restore still protects '),
                      'main',
                      context.tr(' if a fix can’t be validated.'),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 15, color: _amber),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        context.tr(
                          'Recommended only once you trust the Fix + Review AI pairing on your codebase.',
                        ),
                        style: Sa.body(size: 11.5, color: Sa.textDim),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _btn(
                        context,
                        context.tr('Keep human review'),
                        _green,
                        false,
                        filled: false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _btn(
                        context,
                        context.tr('Enable automatic'),
                        _red,
                        true,
                        filled: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(IconData ic, String a, String bold, String b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(ic, size: 15, color: _red.withValues(alpha: 0.85)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: Sa.body(size: 12.5, color: Sa.textDim),
                children: [
                  TextSpan(text: a),
                  TextSpan(
                    text: bold,
                    style: Sa.body(
                      size: 12.5,
                      color: Sa.text,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: b),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(
    BuildContext ctx,
    String label,
    Color c,
    bool value, {
    required bool filled,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? c.withValues(alpha: 0.92) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: filled ? 0.0 : 0.6)),
        ),
        child: Text(
          label,
          style: Sa.body(
            size: 12.5,
            color: filled ? Colors.white : c,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}




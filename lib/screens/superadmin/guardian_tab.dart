import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../services/github_service.dart';
import '../../services/guardian_config_service.dart';
import 'superadmin_theme.dart';

/// Guardian — autonomous fix-pipeline console (SuperAdmin).
/// Theme-aware via [Sa] (light/dark); GitHub status colors stay fixed/semantic;
/// the dispatch log uses the fixed dark terminal surface like the other consoles.
const String _ghWorkerUrl =
    String.fromEnvironment('ALERTSYS_GITHUB_WORKER_URL', defaultValue: '');
const String _workerSecret =
    String.fromEnvironment('ALERTSYS_WORKER_SHARED_SECRET', defaultValue: '');

// GitHub-fixed status colors (semantic, not theme).
const _ghGreen = Color(0xFF3FB950);
const _ghRed = Color(0xFFF85149);
const _ghAmber = Color(0xFFD29922);
const _ghPurple = Color(0xFFA371F7);
const _ghBlue = Color(0xFF58A6FF);

class GuardianTab extends StatefulWidget {
  const GuardianTab({super.key});
  @override
  State<GuardianTab> createState() => _GuardianTabState();
}

class _GuardianTabState extends State<GuardianTab> {
  final GuardianConfigService _cfg = GuardianConfigService();
  final DatabaseReference _agentRef = FirebaseDatabase.instance.ref('bugs/agent');

  List<Map<String, dynamic>> _ghRuns = [];
  List<Map<String, dynamic>> _ghPulls = [];
  bool _ghLoading = false;
  bool _ghConnected = false;

  @override
  void initState() {
    super.initState();
    _loadGithub();
  }

  Future<void> _loadGithub() async {
    if (_ghWorkerUrl.isEmpty) {
      setState(() => _ghConnected = false);
      return;
    }
    setState(() => _ghLoading = true);
    final gh = GithubService(baseUrl: _ghWorkerUrl, sharedSecret: _workerSecret);
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GuardianConfig>(
      stream: _cfg.watch(),
      builder: (context, snap) {
        final cfg = snap.data ?? GuardianConfig.empty;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(cfg),
              const SizedBox(height: 16),
              _pipelineCard(),
              const SizedBox(height: 16),
              _configCard(cfg),
              const SizedBox(height: 16),
              _runsCard(),
              const SizedBox(height: 16),
              _githubCard(),
              const SizedBox(height: 16),
              _logCard(),
            ],
          ),
        );
      },
    );
  }

  // ── header ────────────────────────────────────────────────────────────
  Widget _header(GuardianConfig cfg) {
    return _panel(
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Sa.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Sa.borderBright),
            ),
            child: Icon(Icons.shield_outlined, color: Sa.blue, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Guardian',
                    style: TextStyle(color: Sa.text, fontSize: 16, fontWeight: FontWeight.w500)),
                Text('autonomous fix pipeline',
                    style: TextStyle(color: Sa.muted, fontSize: 12)),
              ],
            ),
          ),
          _miniChip(
            cfg.repo.isEmpty ? 'no repo linked' : cfg.repo,
            Icons.code,
            cfg.repo.isEmpty ? Sa.muted : _ghGreen,
          ),
          const SizedBox(width: 10),
          Text(cfg.enabled ? 'Armed' : 'Off',
              style: TextStyle(color: cfg.enabled ? _ghGreen : Sa.muted, fontSize: 12)),
          Switch(
            value: cfg.enabled,
            onChanged: (v) => _cfg.setEnabled(v),
          ),
        ],
      ),
    );
  }

  // ── pipeline ──────────────────────────────────────────────────────────
  Widget _pipelineCard() {
    final stages = <List<String>>[
      ['Detect', 'UI checks · log watcher · CF cron'],
      ['Orchestrator', 'coordinates the fix pipeline'],
      ['Gather context', 'source · stack traces · DB state'],
      ['Claude generates fix', 'model auto-selected by severity'],
      ['Test + AI review', 'CI dry-run · review token confirms'],
      ['Fix approved?', 'tests pass + review confirms'],
      ['GitHub PR → CI', 'branch · checks · all green'],
      ['Auto-merge / Alert human', 'per deploy-mode setting'],
    ];
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(Icons.route, 'FIX PIPELINE'),
          const SizedBox(height: 12),
          for (var i = 0; i < stages.length; i++)
            _stageRow(stages[i][0], stages[i][1], last: i == stages.length - 1),
        ],
      ),
    );
  }

  Widget _stageRow(String title, String sub, {bool last = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Sa.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: Sa.border),
                ),
                child: Icon(Icons.bolt, size: 14, color: Sa.cyan),
              ),
              if (!last)
                Expanded(child: Container(width: 2, color: Sa.border)),
            ],
          ),
          const SizedBox(width: 11),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Sa.text, fontSize: 13.5, fontWeight: FontWeight.w500)),
                Text(sub, style: TextStyle(color: Sa.muted, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── config ────────────────────────────────────────────────────────────
  Widget _configCard(GuardianConfig cfg) {
    final auto = cfg.deployMode == GuardianDeployMode.auto;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(Icons.tune, 'CONFIGURATION'),
          const SizedBox(height: 12),
          Text('Deploy mode', style: TextStyle(color: Sa.textDim, fontSize: 12)),
          const SizedBox(height: 7),
          Row(
            children: [
              _segment('Automatic', auto,
                  () => _cfg.save(cfg.copyWith(deployMode: GuardianDeployMode.auto))),
              const SizedBox(width: 8),
              _segment('Human review', !auto,
                  () => _cfg.save(cfg.copyWith(deployMode: GuardianDeployMode.humanReview))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Model routing', style: TextStyle(color: Sa.textDim, fontSize: 12)),
              const Spacer(),
              Text(cfg.autoModelSelect ? 'auto by severity' : 'manual',
                  style: TextStyle(color: Sa.cyan, fontSize: 11)),
              Switch(
                value: cfg.autoModelSelect,
                onChanged: (v) => _cfg.save(cfg.copyWith(autoModelSelect: v)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _routeRow('HIGH', _ghRed, cfg.modelHigh, 'notifications · escalation · login'),
          _routeRow('MED', _ghAmber, cfg.modelMedium, 'collaborations · commands'),
          _routeRow('LOW', _ghGreen, cfg.modelLow, 'UI · forecaster adaptation'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _kv(Icons.key, 'Fix token', cfg.fixTokenRef, Sa.blue),
              _kv(Icons.key, 'Review token', cfg.reviewTokenRef, _ghPurple),
              _kv(Icons.menu_book_outlined, 'Skills', '${cfg.skills.length} prompts', _ghGreen),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _editSkills(cfg),
              icon: Icon(Icons.edit_note, size: 18, color: Sa.cyan),
              label: Text('Manage skills & prompts', style: TextStyle(color: Sa.cyan, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Sa.blue.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: active ? Sa.borderBright : Sa.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? Sa.blue : Sa.textDim,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w500 : FontWeight.w400)),
        ),
      ),
    );
  }

  Widget _routeRow(String sev, Color c, String model, String ex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _pill(sev, c),
          const SizedBox(width: 10),
          Text(model, style: TextStyle(color: Sa.text, fontSize: 12.5)),
          const Spacer(),
          Flexible(
            child: Text(ex,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Sa.muted, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ── runs (bugs/agent) ──────────────────────────────────────────────────
  Widget _runsCard() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(Icons.checklist, 'GUARDIAN RUNS'),
          const SizedBox(height: 8),
          StreamBuilder<DatabaseEvent>(
            stream: _agentRef.onValue,
            builder: (context, snap) {
              final raw = snap.data?.snapshot.value;
              if (raw is! Map || raw.isEmpty) {
                return _empty('No Guardian runs yet.');
              }
              final runs = raw.entries
                  .map((e) => Map<String, dynamic>.from(e.value as Map))
                  .toList()
                ..sort((a, b) =>
                    (b['at'] ?? '').toString().compareTo((a['at'] ?? '').toString()));
              return Column(
                children: [for (final r in runs.take(8)) _runRow(r)],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _runRow(Map<String, dynamic> r) {
    final status = (r['status'] ?? r['outcome'] ?? '').toString();
    final color = _statusColor(status);
    final title = (r['summary'] ?? r['area'] ?? r['title'] ?? 'Guardian run').toString();
    final commit = (r['commit'] ?? '').toString();
    final issue = (r['issueUrl'] ?? '').toString();
    final meta = issue.isNotEmpty
        ? 'escalated → issue opened'
        : commit.isNotEmpty
            ? 'committed ${commit.length > 7 ? commit.substring(0, 7) : commit}'
            : status;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Sa.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(status), color: color, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Sa.text, fontSize: 13)),
                Text(meta, style: TextStyle(color: Sa.muted, fontSize: 11)),
              ],
            ),
          ),
          if ((r['model'] ?? '').toString().isNotEmpty)
            _miniChip(r['model'].toString(), Icons.memory, Sa.violet),
        ],
      ),
    );
  }

  // ── github activity ─────────────────────────────────────────────────────
  Widget _githubCard() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionLabel(Icons.hub_outlined, 'GITHUB ACTIVITY'),
              const Spacer(),
              if (_ghLoading)
                SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Sa.cyan))
              else
                InkWell(
                  onTap: _loadGithub,
                  child: Icon(Icons.refresh, size: 18, color: Sa.cyan),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_ghConnected)
            _empty(_ghWorkerUrl.isEmpty
                ? 'GitHub worker URL not configured (set ALERTSYS_GITHUB_WORKER_URL).'
                : 'Not connected. Link a repo + token in Infrastructure.')
          else ...[
            Text('Workflow runs', style: TextStyle(color: Sa.textDim, fontSize: 12)),
            for (final run in _ghRuns.take(5)) _ghRunRow(run),
            const SizedBox(height: 10),
            Text('Pull requests', style: TextStyle(color: Sa.textDim, fontSize: 12)),
            for (final pr in _ghPulls.take(5)) _ghPrRow(pr),
          ],
        ],
      ),
    );
  }

  Widget _ghRunRow(Map<String, dynamic> r) {
    final concl = (r['conclusion'] ?? r['status'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_statusIcon(concl), color: _statusColor(concl), size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${r['name'] ?? 'run'}  ·  ${r['branch'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Sa.text, fontSize: 12.5)),
          ),
          Text((r['event'] ?? '').toString(), style: TextStyle(color: Sa.muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _ghPrRow(Map<String, dynamic> p) {
    final state = (p['state'] ?? '').toString();
    final c = state == 'merged' ? _ghPurple : (state == 'open' ? _ghGreen : Sa.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.call_merge, color: c, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text('#${p['number'] ?? '?'}  ${p['title'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Sa.text, fontSize: 12.5)),
          ),
          _pill(state.toUpperCase(), c),
        ],
      ),
    );
  }

  // ── dispatch log (fixed dark terminal) ──────────────────────────────────
  Widget _logCard() {
    return Container(
      decoration: BoxDecoration(
        color: Sa.termBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.termBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.terminal, size: 15, color: Sa.termDim),
            const SizedBox(width: 6),
            Text('DISPATCH LOG',
                style: TextStyle(color: Sa.termDim, fontSize: 11, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Live command + workflow output streams here when a run is active.\n'
            'Each run records to bugs/agent and the linked GitHub repo.',
            style: TextStyle(
                color: Sa.termText, fontSize: 12, height: 1.6, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  // ── small helpers ───────────────────────────────────────────────────────
  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Sa.panelSolid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Sa.border),
        ),
        child: child,
      );

  Widget _sectionLabel(IconData ic, String text) => Row(
        children: [
          Icon(ic, size: 14, color: Sa.muted),
          const SizedBox(width: 7),
          Text(text,
              style: TextStyle(color: Sa.muted, fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w500)),
        ],
      );

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      );

  Widget _miniChip(String t, IconData ic, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Sa.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 12, color: c),
          const SizedBox(width: 5),
          Text(t, style: TextStyle(color: Sa.textDim, fontSize: 11)),
        ]),
      );

  Widget _kv(IconData ic, String k, String v, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, size: 14, color: c),
          const SizedBox(width: 6),
          Text('$k: ', style: TextStyle(color: Sa.muted, fontSize: 12)),
          Text(v, style: TextStyle(color: Sa.text, fontSize: 12)),
        ],
      );

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(t, style: TextStyle(color: Sa.muted, fontSize: 12.5)),
      );

  Color _statusColor(String s) {
    s = s.toLowerCase();
    if (s.contains('success') || s.contains('fixed') || s.contains('deploy') || s.contains('clean') || s == 'merged') {
      return _ghGreen;
    }
    if (s.contains('fail') || s.contains('reject') || s.contains('error')) return _ghRed;
    if (s.contains('escalat') || s.contains('pending') || s.contains('progress') || s.contains('queued') || s.contains('review')) {
      return _ghAmber;
    }
    return _ghBlue;
  }

  IconData _statusIcon(String s) {
    s = s.toLowerCase();
    if (s.contains('success') || s.contains('fixed') || s.contains('deploy') || s.contains('clean') || s == 'merged') {
      return Icons.check_circle_outline;
    }
    if (s.contains('fail') || s.contains('reject') || s.contains('error')) return Icons.cancel_outlined;
    if (s.contains('escalat')) return Icons.notifications_active_outlined;
    if (s.contains('progress') || s.contains('queued')) return Icons.sync;
    return Icons.radio_button_unchecked;
  }

  Future<void> _editSkills(GuardianConfig cfg) async {
    final controller = TextEditingController(text: cfg.skills.join('\n'));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        title: Text('Guardian skills & instruction prompts',
            style: TextStyle(color: Sa.text, fontSize: 16)),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            maxLines: 10,
            style: TextStyle(color: Sa.text, fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'One instruction/skill per line — fed to the fix model.',
              hintStyle: TextStyle(color: Sa.muted),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Save', style: TextStyle(color: Sa.cyan)),
          ),
        ],
      ),
    );
    if (result != null) {
      final skills = result
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await _cfg.save(cfg.copyWith(skills: skills));
    }
  }
}

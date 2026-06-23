// Guardian autonomous-fix pipeline — a live, 3D-styled command surface.
//
// Three pieces live here:
//   • [GuardianLiveTracker]  — a ChangeNotifier that polls the GitHub proxy
//     worker and turns the REAL workflow run (its jobs + steps + raw logs) into
//     a per-node pipeline state. It also drives "an actual alert happens": it
//     latches onto the newest run automatically, so a genuine CI / autonomous
//     bug-fix run lights the schema automatically.
//   • [GuardianPipeline]     — the headline 3D animated schematic (the flow-
//     chart the operator asked for). Each node glows: grey/transparent when
//     GitHub is not connected, amber while a stage is running, green once it
//     passes, blood-red the instant a stage fails — with flowing energy along
//     the connectors as work moves from stage to stage.
//   • [GuardianTerminal]     — the real terminal: live job/step checklist plus
//     the actual stdout tail (`$ npm test`, build output, …) from the run.
//
// The renderer is deliberately a pure function of its inputs; all the live
// intelligence is in the tracker, so the visuals stay smooth and testable.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/github_service.dart';
import 'superadmin_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Status model + palette
// ─────────────────────────────────────────────────────────────────────────────
enum PipeStatus { off, idle, pending, active, passed, failed }

class _GP {
  _GP._();
  static const green = Color(0xFF3FB950);
  static const red = Color(0xFFF85149);
  static const amber = Color(0xFFD29922);
  static const blue = Color(0xFF58A6FF);
  static const grey = Color(0xFF6E7681);
  static const dim = Color(0xFF3A4458);

  static Color of(PipeStatus s) {
    switch (s) {
      case PipeStatus.passed:
        return green;
      case PipeStatus.active:
        return amber;
      case PipeStatus.failed:
        return red;
      case PipeStatus.idle:
        return green;
      case PipeStatus.pending:
        return grey;
      case PipeStatus.off:
        return dim;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Canonical graph (matches the operator's flow-chart)
// ─────────────────────────────────────────────────────────────────────────────
class _PNode {
  final String id;
  final String label;
  final String sub;
  final IconData icon;
  final int phase; // 0 detect · 1 context · 2 fix · 3 review · 4 gate · 5 ship
  final int row;
  const _PNode(this.id, this.label, this.sub, this.icon, this.phase, this.row);
}

const _kNodes = <_PNode>[
  _PNode(
    'ui_checks',
    'UI checks',
    'Endpoint polling',
    Icons.monitor_outlined,
    0,
    0,
  ),
  _PNode(
    'log_watcher',
    'Log watcher',
    'Console + Sentry',
    Icons.terminal,
    0,
    0,
  ),
  _PNode('cf_cron', 'CF + cron', 'Worker status', Icons.cloud_queue, 0, 0),
  _PNode(
    'orchestrator',
    'Agent orchestrator',
    'Detects bug → coordinates fix',
    Icons.account_tree,
    0,
    1,
  ),
  _PNode('ctx_source', 'Source code', 'Relevant files', Icons.code, 1, 2),
  _PNode(
    'ctx_errors',
    'Error logs',
    'Stack traces',
    Icons.bug_report_outlined,
    1,
    2,
  ),
  _PNode('ctx_db', 'DB state', 'CF workers', Icons.storage_outlined, 1, 2),
  _PNode('claude', 'Fix AI', 'Selected model', Icons.psychology_outlined, 2, 3),
  _PNode(
    'test_suite',
    'Test suite',
    'CI dry run',
    Icons.science_outlined,
    3,
    4,
  ),
  _PNode(
    'ai_review',
    'Review AI',
    'Selected model',
    Icons.reviews_outlined,
    3,
    4,
  ),
  _PNode(
    'gate',
    'Fix approved?',
    'Tests pass + AI review confirms',
    Icons.fact_check_outlined,
    4,
    5,
  ),
  _PNode(
    'alert_human',
    'Alert human',
    'Notify + retry',
    Icons.notifications_active_outlined,
    4,
    5,
  ),
  _PNode(
    'github_pr',
    'GitHub PR',
    'Branch created, tests run',
    Icons.merge_type,
    5,
    6,
  ),
  _PNode('ci_checks', 'CI checks', 'all green', Icons.task_alt, 5, 6),
  _PNode(
    'deploy',
    'Auto-merge + deploy',
    'Push to main → production live',
    Icons.rocket_launch_outlined,
    5,
    7,
  ),
];

class _PEdge {
  final String from;
  final String to;
  final String kind; // flow · no · retry
  final String label;
  const _PEdge(this.from, this.to, {this.kind = 'flow', this.label = ''});
}

const _kEdges = <_PEdge>[
  _PEdge('ui_checks', 'orchestrator'),
  _PEdge('log_watcher', 'orchestrator'),
  _PEdge('cf_cron', 'orchestrator'),
  _PEdge('orchestrator', 'ctx_source'),
  _PEdge('orchestrator', 'ctx_errors'),
  _PEdge('orchestrator', 'ctx_db'),
  _PEdge('ctx_source', 'claude'),
  _PEdge('ctx_errors', 'claude'),
  _PEdge('ctx_db', 'claude'),
  _PEdge('claude', 'test_suite'),
  _PEdge('claude', 'ai_review'),
  _PEdge('test_suite', 'gate'),
  _PEdge('ai_review', 'gate'),
  _PEdge('gate', 'github_pr', label: 'Yes'),
  _PEdge('gate', 'alert_human', kind: 'no', label: 'No'),
  _PEdge('github_pr', 'ci_checks'),
  _PEdge('ci_checks', 'deploy'),
  _PEdge('alert_human', 'claude', kind: 'retry', label: 'retry'),
];

/// Pure mapping from a pipeline phase frontier → the per-node status map both the
/// live run and the offline preview share.
Map<String, PipeStatus> computePipelineNodes({
  required bool connected,
  required int frontier,
  required int failPhase,
  required bool done,
  required bool running,
  required bool idleArmed,
  required String mode,
}) {
  PipeStatus phaseStatus(int p) {
    if (!connected) return PipeStatus.off;
    if (idleArmed) return p == 0 ? PipeStatus.idle : PipeStatus.pending;
    if (failPhase >= 0) {
      if (p < failPhase) return PipeStatus.passed;
      if (p == failPhase) return PipeStatus.failed;
      return PipeStatus.pending;
    }
    if (done) return PipeStatus.passed;
    if (p < frontier) return PipeStatus.passed;
    if (p == frontier) return running ? PipeStatus.active : PipeStatus.passed;
    return PipeStatus.pending;
  }

  final m = <String, PipeStatus>{};
  for (final n in _kNodes) {
    m[n.id] = phaseStatus(n.phase);
  }
  // The "No" branch lights only on failure.
  final fail = connected && failPhase >= 0;
  m['alert_human'] = !connected
      ? PipeStatus.off
      : fail
      ? PipeStatus.failed
      : idleArmed
      ? PipeStatus.idle
      : PipeStatus.pending;
  // Human-review mode: the PR opens & CI runs, but the deploy waits on a person.
  if (connected && done && failPhase < 0 && mode != 'auto') {
    m['github_pr'] = PipeStatus.passed;
    m['ci_checks'] = PipeStatus.passed;
    m['deploy'] = PipeStatus.idle;
  }
  return m;
}

// ═════════════════════════════════════════════════════════════════════════════
// LIVE TRACKER — turns the real GitHub run into pipeline state
// ═════════════════════════════════════════════════════════════════════════════
class GuardianLiveTracker extends ChangeNotifier {
  GuardianLiveTracker({
    required String baseUrl,
    required String secret,
    String repo = '',
  }) : _baseUrl = baseUrl,
       _secret = secret,
       _repoHint = repo {
    _gh = GithubService(baseUrl: _baseUrl, sharedSecret: _secret, repo: repo);
  }

  final String _baseUrl;
  final String _secret;
  late GithubService _gh;
  String _repoHint;
  Timer? _poll;
  bool _disposed = false;

  String mode = 'human';

  // public state
  bool connected = false;
  String repo = '';
  bool busy = false;
  Map<String, dynamic>? run;
  List<Map<String, dynamic>> jobs = const [];
  String rawTail = '';
  String runUrl = '';
  DateTime? lastSync;

  int frontier = 0;
  int failPhase = -1;
  bool running = false;
  bool done = false;
  bool failed = false;

  // drill latch
  DateTime? _expectAfter;
  bool _dispatchPending = false;
  Object? _latchId;

  Map<String, PipeStatus> nodes = computePipelineNodes(
    connected: false,
    frontier: 0,
    failPhase: -1,
    done: false,
    running: false,
    idleArmed: false,
    mode: 'human',
  );

  bool get idleArmed => connected && run == null && !_dispatchPending;

  void start() {
    _tick();
  }

  void setRepo(String value) {
    final next = GithubService.normalizeRepo(value);
    if (next == _repoHint) return;
    _repoHint = next;
    _poll?.cancel();
    _gh.close();
    _gh = GithubService(
      baseUrl: _baseUrl,
      sharedSecret: _secret,
      repo: _repoHint,
    );
    repo = _repoHint;
    connected = false;
    run = null;
    jobs = const [];
    rawTail = '';
    _recompute();
    if (!_disposed) _schedule(Duration.zero);
  }

  void rememberConnected(String value) {
    final next = GithubService.normalizeRepo(value);
    if (next.isNotEmpty && next != _repoHint) {
      _repoHint = next;
      _poll?.cancel();
      _gh.close();
      _gh = GithubService(
        baseUrl: _baseUrl,
        sharedSecret: _secret,
        repo: _repoHint,
      );
    }
    if (next.isNotEmpty) {
      repo = next;
    }
    connected = true;
    _recompute();
    if (!_disposed) {
      notifyListeners();
      _schedule(Duration.zero);
    }
  }

  void forgetConnection() {
    connected = false;
    run = null;
    jobs = const [];
    rawTail = '';
    runUrl = '';
    frontier = 0;
    failPhase = -1;
    running = false;
    done = false;
    failed = false;
    _recompute();
    if (!_disposed) {
      notifyListeners();
      _schedule(Duration.zero);
    }
  }

  /// Called right after a repository_dispatch: latch
  /// onto the next guardian run so the schema reacts immediately.
  void expectDrill() {
    _expectAfter = DateTime.now().toUtc();
    _dispatchPending = true;
    _latchId = null;
    frontier = 0;
    failPhase = -1;
    running = true;
    done = false;
    failed = false;
    _recompute();
    notifyListeners();
    _tick();
  }

  Future<void> refreshNow() => _tick();

  void _schedule(Duration d) {
    _poll?.cancel();
    if (_disposed) return;
    _poll = Timer(d, _tick);
  }

  Future<void> _tick() async {
    if (_disposed) return;
    busy = true;
    notifyListeners();
    try {
      final st = await _gh.status();
      connected = st.connected;
      repo = st.repo;
      if (!connected) {
        run = null;
        jobs = const [];
        rawTail = '';
        _recompute();
        return;
      }
      final runs = await _gh.runs();
      final tracked = _selectRun(runs);
      if (tracked == null) {
        run = null;
        jobs = const [];
        rawTail = '';
        if (!_dispatchPending) {
          frontier = 0;
          failPhase = -1;
          running = false;
          done = false;
          failed = false;
        }
        _recompute();
        return;
      }
      run = tracked;
      runUrl = (tracked['url'] ?? '').toString();
      final status = (tracked['status'] ?? '').toString();
      final concl = (tracked['conclusion'] ?? '').toString();
      done = status == 'completed';
      running = !done;
      final live = running || _recentlyFinished(tracked);
      if (live) {
        jobs = await _gh.runJobs(tracked['id']);
        _computeFromJobs(concl);
        final active = _activeJob();
        if (active != null) {
          rawTail = await _gh.jobLogs(active['id']);
        } else if (jobs.isNotEmpty) {
          rawTail = await _gh.jobLogs(jobs.last['id']);
        }
      } else {
        jobs = const [];
        rawTail = '';
        failed = _isFailConcl(concl);
        failPhase = failed ? 5 : -1;
        frontier = failed ? 5 : 6;
      }
      if (done) _dispatchPending = false;
      _recompute();
    } catch (_) {
      // keep last known state; just reschedule
    } finally {
      busy = false;
      lastSync = DateTime.now();
      _schedule(Duration(seconds: running || _dispatchPending ? 4 : 13));
      if (!_disposed) notifyListeners();
    }
  }

  bool _isFailConcl(String c) =>
      c == 'failure' ||
      c == 'timed_out' ||
      c == 'startup_failure' ||
      c == 'cancelled';

  bool _recentlyFinished(Map run) {
    final u = DateTime.tryParse((run['updatedAt'] ?? '').toString());
    if (u == null) return false;
    return DateTime.now().toUtc().difference(u.toUtc()).inSeconds < 150;
  }

  bool _looksGuardian(Map r) {
    final wf = '${r['workflow'] ?? ''} ${r['name'] ?? ''}'.toLowerCase();
    final ev = (r['event'] ?? '').toString().toLowerCase();
    return ev.contains('dispatch') ||
        wf.contains('guardian') ||
        wf.contains('drill');
  }

  Map<String, dynamic>? _selectRun(List<Map<String, dynamic>> runs) {
    if (runs.isEmpty) return null;
    // 1. Honour an explicit latch on a known guardian run.
    if (_latchId != null) {
      for (final r in runs) {
        if ('${r['id']}' == '$_latchId') return r;
      }
      _latchId = null; // scrolled out of the recent window
    }
    // 2. While waiting on a freshly-dispatched drill, find it and latch on.
    if (_expectAfter != null) {
      for (final r in runs) {
        final created = DateTime.tryParse((r['createdAt'] ?? '').toString());
        final fresh =
            created != null &&
            created.toUtc().isAfter(
              _expectAfter!.subtract(const Duration(seconds: 30)),
            );
        if (fresh && _looksGuardian(r)) {
          _latchId = r['id'];
          _expectAfter = null;
          return r;
        }
      }
      return null; // not created yet — keep the synthetic "dispatching" state
    }
    // 3. General live watch: light up for any in-progress / just-finished run.
    final newest = runs.first;
    if ((newest['status'] ?? '') != 'completed' || _recentlyFinished(newest)) {
      return newest;
    }
    return null;
  }

  Map<String, dynamic>? _activeJob() {
    for (final j in jobs) {
      if ((j['status'] ?? '') != 'completed') return j;
    }
    return jobs.isEmpty ? null : jobs.last;
  }

  /// Proportional frontier: as the run's real steps complete, the schematic
  /// advances stage by stage; the first failing step pins the red stage.
  void _computeFromJobs(String runConcl) {
    int total = 0, completed = 0, failedOrd = -1, runningOrd = -1, ord = 0;
    bool anyRunning = false;
    for (final j in jobs) {
      final steps = (j['steps'] is List) ? j['steps'] as List : const [];
      for (final s in steps) {
        final st = ((s as Map)['status'] ?? '').toString();
        final cc = (s['conclusion'] ?? '').toString();
        total++;
        if (st != 'completed') {
          anyRunning = true;
          if (ord > runningOrd) runningOrd = ord;
        } else {
          completed++;
          if (_isFailConcl(cc) && failedOrd < 0) failedOrd = ord;
        }
        ord++;
      }
      final jc = (j['conclusion'] ?? '').toString();
      if (_isFailConcl(jc) &&
          failedOrd < 0 &&
          (j['status'] ?? '') == 'completed') {
        failedOrd = total > 0 ? total - 1 : 0;
      }
    }
    _dispatchPending = false;
    if (total == 0) {
      frontier = 0;
      failPhase = -1;
      running = (run?['status'] ?? '') != 'completed';
      done = !running;
      failed = _isFailConcl(runConcl);
      if (failed) failPhase = 0;
      return;
    }
    final progress = anyRunning ? (runningOrd + 0.5) : completed.toDouble();
    final frac = (progress / total).clamp(0.0, 1.0);
    frontier = (frac * 6).floor().clamp(0, 5);
    running = anyRunning || (run?['status'] ?? '') != 'completed';
    done = !running;
    failed = failedOrd >= 0 || _isFailConcl(runConcl);
    failPhase = failedOrd >= 0
        ? (((failedOrd + 0.5) / total) * 6).floor().clamp(0, 5)
        : (_isFailConcl(runConcl) ? 5 : -1);
    if (done && !failed) frontier = 6;
  }

  void _recompute() {
    nodes = computePipelineNodes(
      connected: connected,
      frontier: frontier,
      failPhase: failPhase,
      done: done,
      running: running || _dispatchPending,
      idleArmed: idleArmed,
      mode: mode,
    );
  }

  String get stageLabel {
    if (!connected) return 'GitHub not connected';
    if (_dispatchPending && run == null) return 'Dispatching drill…';
    if (idleArmed) return 'Armed · watching the stack';
    if (failed) return 'Stage failed — human alerted';
    if (done)
      return mode == 'auto'
          ? 'Healed & deployed'
          : 'Fix ready — awaiting human review';
    const labels = [
      'Detecting',
      'Gathering context',
      'Generating fix',
      'Testing + review',
      'Approval gate',
      'Shipping',
    ];
    return '${labels[frontier.clamp(0, 5)]}…';
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _gh.close();
    super.dispose();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3D ANIMATED PIPELINE
// ═════════════════════════════════════════════════════════════════════════════
class GuardianPipeline extends StatefulWidget {
  final Map<String, PipeStatus> nodes;
  final bool connected;
  final String statusLabel;
  final bool failed;
  final bool running;
  final String fixAiLabel;
  final String reviewAiLabel;
  const GuardianPipeline({
    super.key,
    required this.nodes,
    required this.connected,
    required this.statusLabel,
    this.failed = false,
    this.running = false,
    this.fixAiLabel = 'Selected model',
    this.reviewAiLabel = 'Selected model',
  });

  @override
  State<GuardianPipeline> createState() => _GuardianPipelineState();
}

class _GuardianPipelineState extends State<GuardianPipeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  static const _rowPitch = 86.0;
  static const _nodeH = 58.0;
  static const _topPad = 10.0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Map<String, Rect> _layout(double w) {
    const pad = 4.0;
    const gap = 12.0;
    final colW = (w - 2 * pad - 2 * gap) / 3;
    double x(int c) => pad + c * (colW + gap);
    double y(int r) => _topPad + r * _rowPitch;
    Rect cell(int c, int r) => Rect.fromLTWH(x(c), y(r), colW, _nodeH);
    Rect wide(int r, double f) {
      final ww = (w - 2 * pad) * f;
      return Rect.fromLTWH((w - ww) / 2, y(r), ww, _nodeH);
    }

    final halfW = (w - 2 * pad - gap) / 2;
    Rect half(int r, bool left) =>
        Rect.fromLTWH(left ? pad : pad + halfW + gap, y(r), halfW, _nodeH);

    return {
      'ui_checks': cell(0, 0),
      'log_watcher': cell(1, 0),
      'cf_cron': cell(2, 0),
      'orchestrator': wide(1, 0.66),
      'ctx_source': cell(0, 2),
      'ctx_errors': cell(1, 2),
      'ctx_db': cell(2, 2),
      'claude': wide(3, 0.66),
      'test_suite': half(4, true),
      'ai_review': half(4, false),
      'gate': Rect.fromLTWH(pad, y(5), (w - 2 * pad) * 0.60, _nodeH),
      'alert_human': Rect.fromLTWH(
        pad + (w - 2 * pad) * 0.66,
        y(5),
        (w - 2 * pad) * 0.34,
        _nodeH,
      ),
      'github_pr': half(6, true),
      'ci_checks': half(6, false),
      'deploy': wide(7, 0.66),
    };
  }

  @override
  Widget build(BuildContext context) {
    const height = _topPad + 7 * _rowPitch + _nodeH + 14;
    return GlassPanel(
      accent: widget.failed
          ? _GP.red
          : (widget.running ? _GP.amber : _GP.green),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 14, color: Sa.muted),
              const SizedBox(width: 7),
              Text(
                'SELF-HEAL PIPELINE',
                style: Sa.body(size: 11, color: Sa.muted),
              ),
              const Spacer(),
              _statusPill(),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (ctx, c) {
                final w = c.maxWidth;
                final rects = _layout(w);
                return RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (ctx, _) {
                      final t = _ctrl.value;
                      final pulse = (math.sin(t * 2 * math.pi) + 1) / 2;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _PipePainter(
                                rects: rects,
                                nodes: widget.nodes,
                                connected: widget.connected,
                                t: t,
                                pulse: pulse,
                              ),
                            ),
                          ),
                          for (final n in _kNodes)
                            if (rects[n.id] != null)
                              Positioned.fromRect(
                                rect: rects[n.id]!,
                                child: _PipeNodeCard(
                                  node: n,
                                  status: widget.nodes[n.id] ?? PipeStatus.off,
                                  pulse: pulse,
                                  subOverride: switch (n.id) {
                                    'claude' => widget.fixAiLabel,
                                    'ai_review' => widget.reviewAiLabel,
                                    _ => null,
                                  },
                                ),
                              ),
                          if (!widget.connected) _disconnectedVeil(),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final c = !widget.connected
        ? Sa.muted
        : widget.failed
        ? _GP.red
        : widget.running
        ? _GP.amber
        : _GP.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.running && widget.connected)
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 2, color: c),
            )
          else
            Icon(
              widget.failed ? Icons.error_outline : Icons.circle,
              size: 9,
              color: c,
            ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              widget.statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Sa.body(size: 11.5, color: c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _disconnectedVeil() {
    return Positioned.fill(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Sa.panelSolid.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Sa.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 16, color: Sa.muted),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  'Connect GitHub to bring the pipeline live',
                  style: Sa.body(size: 12, color: Sa.textDim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── one 3D node card ─────────────────────────────────────────────────────────
class _PipeNodeCard extends StatelessWidget {
  final _PNode node;
  final PipeStatus status;
  final double pulse;
  final String? subOverride;
  const _PipeNodeCard({
    required this.node,
    required this.status,
    required this.pulse,
    this.subOverride,
  });

  @override
  Widget build(BuildContext context) {
    final c = _GP.of(status);
    final lit = status == PipeStatus.active || status == PipeStatus.failed;
    final solid = status == PipeStatus.passed || status == PipeStatus.idle;
    final dimmed = status == PipeStatus.off || status == PipeStatus.pending;

    final glow = lit ? (0.34 + pulse * 0.40) : (solid ? 0.20 : 0.0);
    final scale = lit ? (1.0 + pulse * 0.025) : 1.0;
    final opacity = status == PipeStatus.off
        ? 0.34
        : status == PipeStatus.pending
        ? 0.6
        : 1.0;

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(Sa.bgRaised, c, dimmed ? 0.0 : 0.10)!,
                Color.lerp(Sa.bg, c, dimmed ? 0.0 : 0.04)!,
              ],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: c.withValues(alpha: dimmed ? 0.35 : 0.85),
              width: lit ? 1.5 : 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
              if (glow > 0)
                BoxShadow(
                  color: c.withValues(alpha: glow),
                  blurRadius: 18 + pulse * 8,
                  spreadRadius: 0.5,
                ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              _glyph(c),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: dimmed ? Sa.textDim : Sa.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subOverride ?? node.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.1,
                        color: Sa.muted,
                      ),
                    ),
                  ],
                ),
              ),
              _badge(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glyph(Color c) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Icon(node.icon, size: 16, color: c),
    );
  }

  Widget _badge(Color c) {
    switch (status) {
      case PipeStatus.active:
        return SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 2, color: c),
        );
      case PipeStatus.passed:
        return Icon(Icons.check_circle, size: 15, color: c);
      case PipeStatus.failed:
        return Icon(Icons.cancel, size: 15, color: c);
      case PipeStatus.idle:
        return Icon(
          Icons.radio_button_checked,
          size: 13,
          color: c.withValues(alpha: 0.7),
        );
      default:
        return Icon(Icons.circle_outlined, size: 12, color: Sa.muted);
    }
  }
}

// ── connectors + flowing energy ──────────────────────────────────────────────
class _PipePainter extends CustomPainter {
  final Map<String, Rect> rects;
  final Map<String, PipeStatus> nodes;
  final bool connected;
  final double t;
  final double pulse;
  _PipePainter({
    required this.rects,
    required this.nodes,
    required this.connected,
    required this.t,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // glows behind lit nodes (drawn under the node cards)
    for (final n in _kNodes) {
      final r = rects[n.id];
      if (r == null) continue;
      final s = nodes[n.id] ?? PipeStatus.off;
      if (s == PipeStatus.active || s == PipeStatus.failed) {
        final c = _GP.of(s);
        final p = Paint()
          ..color = c.withValues(alpha: 0.10 + pulse * 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(8), const Radius.circular(18)),
          p,
        );
      }
    }
    for (final e in _kEdges) {
      _drawEdge(canvas, e);
    }
  }

  void _drawEdge(Canvas canvas, _PEdge e) {
    final a = rects[e.from];
    final b = rects[e.to];
    if (a == null || b == null) return;
    final sFrom = nodes[e.from] ?? PipeStatus.off;
    final sTo = nodes[e.to] ?? PipeStatus.off;

    final path = _edgePath(a, b, e.kind);

    final color = _edgeColor(e, sFrom, sTo);
    final flowing = connected && color != _GP.dim;

    // base line
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = (connected ? color : _GP.dim).withValues(
        alpha: flowing ? 0.35 : 0.18,
      );
    canvas.drawPath(path, base);

    if (flowing) {
      // bright trail
      final bright = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = color.withValues(alpha: 0.22 + pulse * 0.10);
      canvas.drawPath(path, bright);
      _drawFlow(canvas, path, color);
    }
    _drawArrowHead(
      canvas,
      path,
      (connected ? color : _GP.dim).withValues(alpha: flowing ? 0.8 : 0.3),
    );
  }

  Path _edgePath(Rect a, Rect b, String kind) {
    final path = Path();
    final horizontal = (a.center.dy - b.center.dy).abs() < 8;
    if (kind == 'retry') {
      // long curve up the right edge from alert_human back to claude
      final start = Offset(a.center.dx, a.top);
      final end = Offset(b.right, b.center.dy);
      final cx = math.max(a.right, b.right) + 46;
      path.moveTo(start.dx, start.dy);
      path.cubicTo(cx, start.dy, cx, end.dy, end.dx, end.dy);
      return path;
    }
    if (horizontal) {
      final start = Offset(a.right, a.center.dy);
      final end = Offset(b.left, b.center.dy);
      final mx = (start.dx + end.dx) / 2;
      path.moveTo(start.dx, start.dy);
      path.cubicTo(mx, start.dy, mx, end.dy, end.dx, end.dy);
      return path;
    }
    final start = Offset(a.center.dx, a.bottom);
    final end = Offset(b.center.dx, b.top);
    final my = (start.dy + end.dy) / 2;
    path.moveTo(start.dx, start.dy);
    path.cubicTo(start.dx, my, end.dx, my, end.dx, end.dy);
    return path;
  }

  void _drawFlow(Canvas canvas, Path path, Color color) {
    for (final metric in path.computeMetrics()) {
      final len = metric.length;
      const spacing = 24.0;
      final base = (t * spacing) % spacing;
      for (double d = base; d < len; d += spacing) {
        final tan = metric.getTangentForOffset(d);
        if (tan == null) continue;
        final headroom = (len - d) / len; // fade as it approaches target
        final dot = Paint()
          ..color = color.withValues(
            alpha: (0.5 + 0.5 * headroom).clamp(0.0, 1.0),
          );
        canvas.drawCircle(tan.position, 2.3, dot);
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Path path, Color color) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.last;
    final tan = m.getTangentForOffset(m.length);
    if (tan == null) return;
    final p = tan.position;
    final ang = tan.angle;
    const size = 5.0;
    final paint = Paint()..color = color;
    final path2 = Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(
        p.dx - size * math.cos(ang - 0.5),
        p.dy - size * math.sin(ang - 0.5),
      )
      ..lineTo(
        p.dx - size * math.cos(ang + 0.5),
        p.dy - size * math.sin(ang + 0.5),
      )
      ..close();
    canvas.drawPath(path2, paint);
  }

  Color _edgeColor(_PEdge e, PipeStatus sFrom, PipeStatus sTo) {
    if (!connected || sFrom == PipeStatus.off) return _GP.dim;
    if (e.kind == 'retry') {
      return sFrom == PipeStatus.failed ? _GP.red : _GP.dim;
    }
    if (sTo == PipeStatus.failed) return _GP.red;
    if (sTo == PipeStatus.active || sFrom == PipeStatus.active)
      return _GP.amber;
    if (sFrom == PipeStatus.passed &&
        (sTo == PipeStatus.passed || sTo == PipeStatus.active)) {
      return _GP.green;
    }
    if (sFrom == PipeStatus.idle) return _GP.green.withValues(alpha: 0.8);
    return _GP.dim;
  }

  @override
  bool shouldRepaint(_PipePainter old) =>
      old.t != t || old.nodes != nodes || old.connected != connected;
}

// ═════════════════════════════════════════════════════════════════════════════
// LIVE TERMINAL — real job/step checklist + raw stdout tail
// ═════════════════════════════════════════════════════════════════════════════
class GuardianTerminal extends StatefulWidget {
  final GuardianLiveTracker tracker;
  final List<String> previewLog;
  const GuardianTerminal({
    super.key,
    required this.tracker,
    this.previewLog = const [],
  });

  @override
  State<GuardianTerminal> createState() => _GuardianTerminalState();
}

class _GuardianTerminalState extends State<GuardianTerminal> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tracker,
      builder: (context, _) {
        final tr = widget.tracker;
        final live =
            tr.connected && (tr.jobs.isNotEmpty || tr.rawTail.isNotEmpty);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
        return Container(
          decoration: BoxDecoration(
            color: Sa.termBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: tr.failed ? _GP.red.withValues(alpha: 0.5) : Sa.termBorder,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.terminal, size: 14, color: Sa.termDim),
                  const SizedBox(width: 6),
                  Text(
                    'GUARDIAN TERMINAL',
                    style: TextStyle(
                      color: Sa.termDim,
                      fontSize: 11,
                      letterSpacing: 0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (tr.repo.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '· ${tr.repo}',
                      style: TextStyle(
                        color: Sa.termMuted,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (tr.busy)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Sa.termDim,
                      ),
                    )
                  else if (tr.running && tr.connected) ...[
                    SizedBox(
                      width: 9,
                      height: 9,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _GP.amber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'live',
                      style: TextStyle(
                        color: _GP.amber,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 188,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: live ? _liveLines(tr) : _fallbackLines(tr),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _fallbackLines(GuardianLiveTracker tr) {
    if (widget.previewLog.isNotEmpty) {
      return [for (final l in widget.previewLog) _line(l, Sa.termText)];
    }
    final msg = tr.connected
        ? 'guardian armed \$ watching for incidents…'
        : 'guardian offline \$ link GitHub to stream live runs…';
    return [_line(msg, Sa.termMuted)];
  }

  List<Widget> _liveLines(GuardianLiveTracker tr) {
    final out = <Widget>[];
    for (final j in tr.jobs) {
      final jn = (j['name'] ?? 'job').toString();
      final jst = (j['status'] ?? '').toString();
      final jcc = (j['conclusion'] ?? '').toString();
      out.add(
        _line(
          '══ $jn  [${jcc.isEmpty ? jst : jcc}]',
          _termJobColor(jst, jcc),
          bold: true,
        ),
      );
      final steps = (j['steps'] is List) ? j['steps'] as List : const [];
      for (final s in steps) {
        final name = ((s as Map)['name'] ?? 'step').toString();
        final st = (s['status'] ?? '').toString();
        final cc = (s['conclusion'] ?? '').toString();
        out.add(_line('  ${_glyphFor(st, cc)} $name', _termStepColor(st, cc)));
      }
    }
    if (tr.rawTail.trim().isNotEmpty) {
      out.add(const SizedBox(height: 6));
      out.add(_line('── live output ──────────────', Sa.termMuted));
      final lines = tr.rawTail.split('\n');
      final tail = lines.length > 140
          ? lines.sublist(lines.length - 140)
          : lines;
      for (final raw in tail) {
        if (raw.trim().isEmpty) continue;
        out.add(_line(raw.replaceAll('\r', ''), _rawColor(raw)));
      }
    }
    return out;
  }

  String _glyphFor(String st, String cc) {
    if (st != 'completed') return '▶';
    switch (cc) {
      case 'success':
        return '✓';
      case 'failure':
      case 'timed_out':
      case 'startup_failure':
        return '✗';
      case 'skipped':
        return '↷';
      case 'cancelled':
        return '∅';
      default:
        return '·';
    }
  }

  Color _termJobColor(String st, String cc) {
    if (st != 'completed') return _GP.amber;
    return _isFail(cc) ? _GP.red : (cc == 'success' ? _GP.green : Sa.termDim);
  }

  Color _termStepColor(String st, String cc) {
    if (st != 'completed') return _GP.amber;
    if (_isFail(cc)) return _GP.red;
    if (cc == 'success') return Sa.termText;
    return Sa.termMuted;
  }

  Color _rawColor(String raw) {
    final l = raw.toLowerCase();
    if (raw.contains('##[error]') ||
        l.contains('error:') ||
        l.contains('failed') ||
        l.contains('✗')) {
      return _GP.red;
    }
    if (l.contains('pass') || l.contains('✓') || l.contains('success'))
      return _GP.green;
    if (raw.trimLeft().startsWith('\$') ||
        raw.trimLeft().startsWith('+ ') ||
        raw.contains('##[group]')) {
      return _GP.blue;
    }
    if (raw.contains('##[warning]') || l.contains('warn')) return _GP.amber;
    return Sa.termText;
  }

  bool _isFail(String c) =>
      c == 'failure' ||
      c == 'timed_out' ||
      c == 'startup_failure' ||
      c == 'cancelled';

  Widget _line(String text, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          height: 1.45,
          fontFamily: 'monospace',
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

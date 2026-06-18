// Authentic GitHub-faithful console surfaces for the Guardian agent.
//
// These two views (Actions workflow runs + Pull requests) deliberately render in
// GitHub's OWN dark palette and row layout — not the command-center `Sa.*` theme —
// so the operator feels like they are looking straight at github.com while never
// leaving the SuperAdmin console. Data comes from the read-only GitHub proxy
// worker via [GithubService]; the token stays server-side. Each view owns its
// own [GithubService] (and HTTP client), polls while mounted, and is only built
// while its subtab is active, so polling stops the moment you leave it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/github_service.dart';

/// GitHub's dark palette (Primer). Kept private to this file so it never bleeds
/// into the rest of the console theme.
class GhTheme {
  GhTheme._();
  static const canvas = Color(0xFF0D1117); // page background
  static const inset = Color(0xFF010409); // deepest inset (filter bar)
  static const surface = Color(0xFF161B22); // cards / headers
  static const surfaceHover = Color(0xFF1C2128);
  static const border = Color(0xFF30363D);
  static const borderMuted = Color(0xFF21262D);
  static const text = Color(0xFFE6EDF3);
  static const muted = Color(0xFF7D8590);
  static const link = Color(0xFF58A6FF);
  static const green = Color(0xFF3FB950);
  static const greenBtn = Color(0xFF238636);
  static const red = Color(0xFFF85149);
  static const yellow = Color(0xFFD29922);
  static const purple = Color(0xFFA371F7);
  static const gray = Color(0xFF6E7681);

  static TextStyle sans({
    double size = 13,
    Color color = text,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) =>
      TextStyle(fontSize: size, color: color, fontWeight: weight, height: height);

  static TextStyle mono({
    double size = 12,
    Color color = muted,
    FontWeight weight = FontWeight.w400,
  }) =>
      TextStyle(
          fontSize: size, color: color, fontWeight: weight, fontFamily: 'monospace');
}

/// GitHub-style relative time ("5 minutes ago", "yesterday", "on 4 Jun").
String ghTimeAgo(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return m <= 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (d.inHours < 24) {
    final h = d.inHours;
    return h <= 1 ? '1 hour ago' : '$h hours ago';
  }
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 30) return '${d.inDays} days ago';
  const mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return 'on ${t.day} ${mon[t.month - 1]}';
}

String _fmtDuration(String? startIso, String? endIso) {
  final s = DateTime.tryParse(startIso ?? '');
  if (s == null) return '';
  final e = DateTime.tryParse(endIso ?? '') ?? DateTime.now().toUtc();
  final secs = e.toUtc().difference(s.toUtc()).inSeconds;
  if (secs < 0) return '';
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60, r = secs % 60;
  if (m < 60) return r == 0 ? '${m}m' : '${m}m ${r}s';
  final h = m ~/ 60;
  return '${h}h ${m % 60}m';
}

// ─────────────────────────────────────────────────────────────────────────────
// Run status glyph (the green ✓ / red ✗ / spinning amber circle GitHub shows).
// ─────────────────────────────────────────────────────────────────────────────
class _RunStatusGlyph extends StatelessWidget {
  final String status; // queued | in_progress | completed | ''
  final String? conclusion; // success | failure | cancelled | skipped | ...
  const _RunStatusGlyph({required this.status, required this.conclusion});

  @override
  Widget build(BuildContext context) {
    const size = 16.0;
    final running = status != 'completed' &&
        (status == 'in_progress' ||
            status == 'queued' ||
            status == 'requested' ||
            status == 'waiting' ||
            status == 'pending' ||
            (conclusion == null && status.isNotEmpty));
    if (running) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: GhTheme.yellow),
      );
    }
    final c = conclusion ?? '';
    switch (c) {
      case 'success':
        return Icon(Icons.check_circle, size: size, color: GhTheme.green);
      case 'failure':
      case 'timed_out':
      case 'startup_failure':
        return Icon(Icons.cancel, size: size, color: GhTheme.red);
      case 'cancelled':
      case 'stale':
        return Icon(Icons.do_not_disturb_on, size: size, color: GhTheme.gray);
      case 'skipped':
        return Icon(Icons.redo, size: size, color: GhTheme.gray);
      case 'action_required':
      case 'neutral':
        return Icon(Icons.error, size: size, color: GhTheme.yellow);
      default:
        return Icon(Icons.circle_outlined, size: size, color: GhTheme.muted);
    }
  }
}

Color _stepColor(String? conclusion, String status) {
  if (status != 'completed') return GhTheme.yellow;
  switch (conclusion) {
    case 'success':
      return GhTheme.green;
    case 'failure':
      return GhTheme.red;
    case 'skipped':
    case 'cancelled':
      return GhTheme.gray;
    default:
      return GhTheme.muted;
  }
}

IconData _stepIcon(String? conclusion, String status) {
  if (status != 'completed') return Icons.timelapse;
  switch (conclusion) {
    case 'success':
      return Icons.check;
    case 'failure':
      return Icons.close;
    case 'skipped':
      return Icons.redo;
    case 'cancelled':
      return Icons.do_not_disturb_on;
    default:
      return Icons.remove;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared chrome
// ─────────────────────────────────────────────────────────────────────────────
class _BranchPill extends StatelessWidget {
  final String branch;
  const _BranchPill(this.branch);
  @override
  Widget build(BuildContext context) {
    if (branch.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: GhTheme.link.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.account_tree_outlined, size: 11, color: GhTheme.link),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhTheme.mono(size: 11, color: GhTheme.link)),
        ),
      ]),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String login;
  final double size;
  const _Avatar(this.login, {this.size = 18});
  @override
  Widget build(BuildContext context) {
    final initial = login.isEmpty ? '?' : login.characters.first.toUpperCase();
    final hue = (login.hashCode % 360).abs().toDouble();
    final c = HSLColor.fromAHSL(1, hue, 0.45, 0.55).toColor();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Text(initial,
          style: TextStyle(
              fontSize: size * 0.5,
              color: Colors.white,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// GitHub-style filter dropdown button ("Event ▾", "Status ▾", …).
class _GhFilter extends StatelessWidget {
  final String label;
  final String value; // current selection ('' == all)
  final List<String> options; // does not include the "all" entry
  final ValueChanged<String> onSelect;
  const _GhFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final active = value.isNotEmpty;
    return PopupMenuButton<String>(
      tooltip: '',
      color: GhTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: GhTheme.border),
      ),
      position: PopupMenuPosition.under,
      onSelected: onSelect,
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: '',
          height: 36,
          child: Text('All ${label.toLowerCase()}s',
              style: GhTheme.sans(
                  size: 12.5,
                  color: value.isEmpty ? GhTheme.text : GhTheme.muted)),
        ),
        for (final o in options)
          PopupMenuItem<String>(
            value: o,
            height: 36,
            child: Row(children: [
              if (o == value)
                Icon(Icons.check, size: 14, color: GhTheme.text)
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Flexible(
                child: Text(o,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhTheme.sans(
                        size: 12.5,
                        color: o == value ? GhTheme.text : GhTheme.muted)),
              ),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(active ? '$label: $value' : label,
              style: GhTheme.sans(
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: active ? GhTheme.text : GhTheme.muted)),
          const SizedBox(width: 3),
          Icon(Icons.arrow_drop_down, size: 16, color: GhTheme.muted),
        ]),
      ),
    );
  }
}

class _GhBlankslate extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _GhBlankslate(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: GhTheme.muted),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: GhTheme.sans(
                    size: 16, weight: FontWeight.w600, color: GhTheme.text)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(body,
                  textAlign: TextAlign.center,
                  style: GhTheme.sans(size: 12.5, color: GhTheme.muted, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared scaffold giving both views the GitHub canvas + a rounded bordered box.
class _GhScaffold extends StatelessWidget {
  final Widget child;
  const _GhScaffold({required this.child});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: GhTheme.canvas,
        child: child,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ACTIONS VIEW
// ═════════════════════════════════════════════════════════════════════════════
class GuardianActionsView extends StatefulWidget {
  final String baseUrl;
  final String sharedSecret;
  final String repo;
  const GuardianActionsView({
    super.key,
    required this.baseUrl,
    required this.sharedSecret,
    this.repo = '',
  });

  @override
  State<GuardianActionsView> createState() => _GuardianActionsViewState();
}

class _GuardianActionsViewState extends State<GuardianActionsView> {
  late final GithubService _gh =
      GithubService(baseUrl: widget.baseUrl, sharedSecret: widget.sharedSecret, repo: widget.repo);
  Timer? _poll;

  bool _firstLoad = true;
  bool _refreshing = false;
  bool _connected = false;
  String _repo = '';
  List<Map<String, dynamic>> _runs = [];

  // filters
  String _fEvent = '', _fStatus = '', _fBranch = '', _fActor = '';

  // expansion
  final Set<String> _open = {};
  final Map<String, List<Map<String, dynamic>>> _jobs = {};
  final Set<String> _jobsLoading = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gh.close();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() {});
    try {
      final st = await _gh.status();
      final runs = st.connected ? await _gh.runs() : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _connected = st.connected;
        _repo = st.repo;
        _runs = runs;
        _firstLoad = false;
      });
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleRun(String id) async {
    if (_open.contains(id)) {
      setState(() => _open.remove(id));
      return;
    }
    setState(() => _open.add(id));
    if (_jobs.containsKey(id)) return;
    setState(() => _jobsLoading.add(id));
    try {
      final jobs = await _gh.runJobs(id);
      if (!mounted) return;
      setState(() => _jobs[id] = jobs);
    } finally {
      if (mounted) setState(() => _jobsLoading.remove(id));
    }
  }

  List<String> _distinct(String key) {
    final s = <String>{};
    for (final r in _runs) {
      final v = (r[key] ?? '').toString();
      if (v.isNotEmpty) s.add(v);
    }
    final l = s.toList()..sort();
    return l;
  }

  bool _matchStatus(Map<String, dynamic> r) {
    if (_fStatus.isEmpty) return true;
    final status = (r['status'] ?? '').toString();
    final concl = (r['conclusion'] ?? '').toString();
    switch (_fStatus) {
      case 'In progress':
        return status != 'completed';
      case 'Success':
        return concl == 'success';
      case 'Failure':
        return concl == 'failure' || concl == 'timed_out' || concl == 'startup_failure';
      case 'Cancelled':
        return concl == 'cancelled';
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _filtered => _runs.where((r) {
        if (_fEvent.isNotEmpty && (r['event'] ?? '') != _fEvent) return false;
        if (_fBranch.isNotEmpty && (r['branch'] ?? '') != _fBranch) return false;
        if (_fActor.isNotEmpty && (r['actor'] ?? '') != _fActor) return false;
        return _matchStatus(r);
      }).toList();

  @override
  Widget build(BuildContext context) {
    if (_firstLoad) {
      return const _GhScaffold(
        child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: GhTheme.muted))),
      );
    }
    if (!_connected) {
      return const _GhScaffold(
        child: _GhBlankslate(
          icon: Icons.link_off,
          title: 'GitHub not connected',
          body: 'Add the repository and a read-only GitHub token in the Control '
              'tab (GITHUB CONNECTION). Workflow runs stream here automatically '
              'once the proxy worker can reach your repo.',
        ),
      );
    }
    final runs = _filtered;
    return _GhScaffold(
      child: Column(
        children: [
          _header(),
          _filterBar(),
          Expanded(
            child: runs.isEmpty
                ? const _GhBlankslate(
                    icon: Icons.play_circle_outline,
                    title: 'No workflow runs match',
                    body: 'Nothing matches the current filters yet.')
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: runs.length,
                    itemBuilder: (ctx, i) => _runRow(runs[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: GhTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_alt, size: 18, color: GhTheme.text),
          const SizedBox(width: 8),
          Text('Actions', style: GhTheme.sans(size: 15, weight: FontWeight.w600)),
          const SizedBox(width: 10),
          if (_repo.isNotEmpty)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: GhTheme.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.book_outlined, size: 12, color: GhTheme.muted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(_repo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhTheme.mono(size: 11.5, color: GhTheme.muted)),
                  ),
                ]),
              ),
            ),
          const Spacer(),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: GhTheme.muted)),
            ),
          InkWell(
            onTap: () => _refresh(),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.refresh, size: 18, color: GhTheme.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final count = _filtered.length;
    return Container(
      color: GhTheme.inset,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Text('$count workflow run${count == 1 ? '' : 's'}',
            style: GhTheme.sans(size: 12.5, weight: FontWeight.w600, color: GhTheme.text)),
        const Spacer(),
        _GhFilter(
            label: 'Event',
            value: _fEvent,
            options: _distinct('event'),
            onSelect: (v) => setState(() => _fEvent = v)),
        _GhFilter(
            label: 'Status',
            value: _fStatus,
            options: const ['In progress', 'Success', 'Failure', 'Cancelled'],
            onSelect: (v) => setState(() => _fStatus = v)),
        _GhFilter(
            label: 'Branch',
            value: _fBranch,
            options: _distinct('branch'),
            onSelect: (v) => setState(() => _fBranch = v)),
        _GhFilter(
            label: 'Actor',
            value: _fActor,
            options: _distinct('actor'),
            onSelect: (v) => setState(() => _fActor = v)),
      ]),
    );
  }

  Widget _runRow(Map<String, dynamic> r) {
    final id = '${r['id']}';
    final status = (r['status'] ?? '').toString();
    final concl = r['conclusion']?.toString();
    final title = (r['name'] ?? 'workflow run').toString();
    final workflow = (r['workflow'] ?? '').toString().split('/').last;
    final actor = (r['actor'] ?? '').toString();
    final number = r['runNumber'];
    final event = (r['event'] ?? '').toString();
    final branch = (r['branch'] ?? '').toString();
    final expanded = _open.contains(id);
    final dur = _fmtDuration(r['createdAt']?.toString(), r['updatedAt']?.toString());

    return Column(
      children: [
        InkWell(
          onTap: () => _toggleRun(id),
          hoverColor: GhTheme.surfaceHover,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: GhTheme.borderMuted)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _RunStatusGlyph(status: status, conclusion: concl),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhTheme.sans(
                              size: 14, weight: FontWeight.w600, color: GhTheme.text)),
                      const SizedBox(height: 3),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            '${workflow.isEmpty ? 'workflow' : workflow}'
                            '${number != null ? ' #$number' : ''}'
                            '${event.isEmpty ? '' : ': $event'}',
                            style: GhTheme.sans(size: 12, color: GhTheme.muted),
                          ),
                          if (actor.isNotEmpty) ...[
                            _Avatar(actor, size: 15),
                            Text(actor, style: GhTheme.sans(size: 12, color: GhTheme.muted)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _BranchPill(branch),
                    const SizedBox(height: 5),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (dur.isNotEmpty) ...[
                        Icon(Icons.timer_outlined, size: 12, color: GhTheme.muted),
                        const SizedBox(width: 3),
                        Text(dur, style: GhTheme.sans(size: 11.5, color: GhTheme.muted)),
                        const SizedBox(width: 8),
                      ],
                      Text(ghTimeAgo(r['createdAt']?.toString()),
                          style: GhTheme.sans(size: 11.5, color: GhTheme.muted)),
                    ]),
                  ],
                ),
                const SizedBox(width: 6),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: GhTheme.muted),
              ],
            ),
          ),
        ),
        if (expanded) _jobsPanel(id),
      ],
    );
  }

  Widget _jobsPanel(String id) {
    final loading = _jobsLoading.contains(id);
    final jobs = _jobs[id] ?? const [];
    return Container(
      width: double.infinity,
      color: GhTheme.inset,
      padding: const EdgeInsets.fromLTRB(44, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2, color: GhTheme.muted)),
                const SizedBox(width: 9),
                Text('Loading jobs…', style: GhTheme.sans(size: 12, color: GhTheme.muted)),
              ]),
            )
          else if (jobs.isEmpty)
            Text('No jobs reported for this run.',
                style: GhTheme.sans(size: 12, color: GhTheme.muted))
          else
            for (final j in jobs) _jobBlock(j),
        ],
      ),
    );
  }

  Widget _jobBlock(Map<String, dynamic> j) {
    final status = (j['status'] ?? '').toString();
    final concl = j['conclusion']?.toString();
    final steps = (j['steps'] is List) ? j['steps'] as List : const [];
    final dur = _fmtDuration(j['startedAt']?.toString(), j['completedAt']?.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_stepIcon(concl, status), size: 14, color: _stepColor(concl, status)),
            const SizedBox(width: 8),
            Expanded(
              child: Text((j['name'] ?? 'job').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhTheme.sans(size: 12.5, weight: FontWeight.w600, color: GhTheme.text)),
            ),
            if (dur.isNotEmpty)
              Text(dur, style: GhTheme.mono(size: 11, color: GhTheme.muted)),
          ]),
          const SizedBox(height: 4),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 3),
              child: Row(children: [
                Icon(_stepIcon((s as Map)['conclusion']?.toString(), (s['status'] ?? '').toString()),
                    size: 12, color: _stepColor(s['conclusion']?.toString(), (s['status'] ?? '').toString())),
                const SizedBox(width: 8),
                Expanded(
                  child: Text((s['name'] ?? 'step').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GhTheme.sans(size: 11.5, color: GhTheme.muted)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PULL REQUESTS VIEW
// ═════════════════════════════════════════════════════════════════════════════
class GuardianPullsView extends StatefulWidget {
  final String baseUrl;
  final String sharedSecret;
  final String repo;
  const GuardianPullsView({
    super.key,
    required this.baseUrl,
    required this.sharedSecret,
    this.repo = '',
  });

  @override
  State<GuardianPullsView> createState() => _GuardianPullsViewState();
}

class _GuardianPullsViewState extends State<GuardianPullsView> {
  late final GithubService _gh =
      GithubService(baseUrl: widget.baseUrl, sharedSecret: widget.sharedSecret, repo: widget.repo);
  Timer? _poll;
  final _searchCtl = TextEditingController();

  bool _firstLoad = true;
  bool _refreshing = false;
  bool _connected = false;
  String _repo = '';
  List<Map<String, dynamic>> _pulls = [];
  bool _showOpen = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchCtl.dispose();
    _gh.close();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() {});
    try {
      final st = await _gh.status();
      final pulls = st.connected ? await _gh.pulls() : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _connected = st.connected;
        _repo = st.repo;
        _pulls = pulls;
        _firstLoad = false;
      });
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  bool _isOpen(Map<String, dynamic> p) => (p['state'] ?? '') == 'open';
  int get _openCount => _pulls.where(_isOpen).length;
  int get _closedCount => _pulls.where((p) => !_isOpen(p)).length;

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _pulls.where((p) {
      if (_showOpen != _isOpen(p)) return false;
      if (q.isEmpty) return true;
      final hay =
          '${p['title'] ?? ''} #${p['number'] ?? ''} ${p['user'] ?? ''} ${p['branch'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLoad) {
      return const _GhScaffold(
        child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: GhTheme.muted))),
      );
    }
    if (!_connected) {
      return const _GhScaffold(
        child: _GhBlankslate(
          icon: Icons.link_off,
          title: 'GitHub not connected',
          body: 'Add the repository and a read-only GitHub token in the Control '
              'tab (GITHUB CONNECTION). Pull requests stream here automatically '
              'once the proxy worker can reach your repo.',
        ),
      );
    }
    final pulls = _filtered;
    return _GhScaffold(
      child: Column(
        children: [
          _header(),
          _searchRow(),
          _stateTabs(),
          Expanded(
            child: pulls.isEmpty
                ? _GhBlankslate(
                    icon: Icons.merge_type,
                    title: _showOpen ? 'No open pull requests' : 'No closed pull requests',
                    body: _showOpen
                        ? 'When Guardian opens a fix as a pull request, it shows up here.'
                        : 'Merged and closed pull requests will appear here.')
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: pulls.length,
                    itemBuilder: (ctx, i) => _prRow(pulls[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: GhTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.merge_type, size: 18, color: GhTheme.text),
          const SizedBox(width: 8),
          Text('Pull requests', style: GhTheme.sans(size: 15, weight: FontWeight.w600)),
          const SizedBox(width: 10),
          if (_repo.isNotEmpty)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: GhTheme.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.book_outlined, size: 12, color: GhTheme.muted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(_repo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhTheme.mono(size: 11.5, color: GhTheme.muted)),
                  ),
                ]),
              ),
            ),
          const Spacer(),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: GhTheme.muted)),
            ),
          InkWell(
            onTap: () => _refresh(),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.refresh, size: 18, color: GhTheme.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Container(
      color: GhTheme.inset,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: GhTheme.canvas,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: GhTheme.border),
        ),
        child: Row(children: [
          const SizedBox(width: 9),
          Icon(Icons.search, size: 15, color: GhTheme.muted),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) => setState(() => _query = v),
              style: GhTheme.sans(size: 12.5, color: GhTheme.text),
              cursorColor: GhTheme.link,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search pull requests',
                hintStyle: GhTheme.sans(size: 12.5, color: GhTheme.muted),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            InkWell(
              onTap: () {
                _searchCtl.clear();
                setState(() => _query = '');
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close, size: 14, color: GhTheme.muted),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _stateTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: GhTheme.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        _stateTab(
            icon: Icons.merge_type,
            label: '$_openCount Open',
            active: _showOpen,
            color: GhTheme.green,
            onTap: () => setState(() => _showOpen = true)),
        const SizedBox(width: 18),
        _stateTab(
            icon: Icons.check,
            label: '$_closedCount Closed',
            active: !_showOpen,
            color: GhTheme.muted,
            onTap: () => setState(() => _showOpen = false)),
      ]),
    );
  }

  Widget _stateTab({
    required IconData icon,
    required String label,
    required bool active,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: active ? GhTheme.text : GhTheme.muted),
        const SizedBox(width: 6),
        Text(label,
            style: GhTheme.sans(
                size: 13,
                weight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? GhTheme.text : GhTheme.muted)),
      ]),
    );
  }

  Widget _prRow(Map<String, dynamic> p) {
    final state = (p['state'] ?? '').toString();
    final draft = p['draft'] == true;
    IconData icon;
    Color color;
    if (state == 'merged') {
      icon = Icons.merge_type;
      color = GhTheme.purple;
    } else if (state == 'open') {
      icon = draft ? Icons.commit : Icons.merge_type;
      color = draft ? GhTheme.gray : GhTheme.green;
    } else {
      icon = Icons.cancel;
      color = GhTheme.red;
    }
    final number = p['number'];
    final user = (p['user'] ?? '').toString();
    final branch = (p['branch'] ?? '').toString();
    final bot = user.toLowerCase().contains('bot') ||
        user.toLowerCase().contains('actions') ||
        user.toLowerCase().contains('guardian');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: GhTheme.borderMuted)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 7,
                  runSpacing: 4,
                  children: [
                    Text((p['title'] ?? '').toString(),
                        style: GhTheme.sans(
                            size: 14, weight: FontWeight.w600, color: GhTheme.text)),
                    if (draft) _tag('Draft', GhTheme.gray),
                    if (bot) _tag('bot', GhTheme.muted),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '#${number ?? '?'} '
                  '${state == 'merged' ? 'by $user was merged' : state == 'closed' ? 'by $user was closed' : 'opened ${ghTimeAgo(p['createdAt']?.toString())} by $user'}',
                  style: GhTheme.sans(size: 12, color: GhTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _BranchPill(branch),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label,
          style: GhTheme.sans(size: 10.5, color: color, weight: FontWeight.w500)),
    );
  }
}

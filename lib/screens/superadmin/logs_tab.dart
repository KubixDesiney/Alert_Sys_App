import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_logger.dart';
import 'superadmin_theme.dart';

/// SuperAdmin tab 3: platform observability.
///
/// Sections: Bugs (client + autonomous agent, with AI fix / GitHub escalation
/// status), live app console, security telemetry, worker cron health, and a
/// live database conception map with per-node health.
class SuperAdminLogsTab extends StatefulWidget {
  const SuperAdminLogsTab({super.key});

  @override
  State<SuperAdminLogsTab> createState() => _SuperAdminLogsTabState();
}

class _SuperAdminLogsTabState extends State<SuperAdminLogsTab> {
  int _section = 0;

  static const _sections = [
    (icon: Icons.bug_report_outlined, label: 'BUGS'),
    (icon: Icons.terminal, label: 'CONSOLE'),
    (icon: Icons.security_outlined, label: 'SECURITY'),
    (icon: Icons.monitor_heart_outlined, label: 'CRON HEALTH'),
    (icon: Icons.schema_outlined, label: 'DATABASE'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _SectionPill(
                      icon: _sections[i].icon,
                      label: _sections[i].label,
                      selected: _section == i,
                      onTap: () => setState(() => _section = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: switch (_section) {
                0 => const _BugsSection(),
                1 => const _ConsoleSection(),
                2 => const _SecuritySection(),
                3 => const _CronHealthSection(),
                _ => const _DatabaseSection(),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SectionPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Sa.cyan.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? Sa.cyan : Sa.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: selected ? Sa.cyan : Sa.muted),
            const SizedBox(width: 7),
            Text(label,
                style: Sa.mono(
                    size: 10.5,
                    color: selected ? Sa.cyan : Sa.muted,
                    weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUGS
// ═══════════════════════════════════════════════════════════════════════════

class _BugsSection extends StatefulWidget {
  const _BugsSection();

  @override
  State<_BugsSection> createState() => _BugsSectionState();
}

class _BugsSectionState extends State<_BugsSection> {
  StreamSubscription<DatabaseEvent>? _clientSub;
  List<Map<String, dynamic>> _clientBugs = const [];
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _clientSub = FirebaseDatabase.instance
        .ref('bugs/client')
        .limitToLast(120)
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      final list = <Map<String, dynamic>>[];
      if (v is Map) {
        v.forEach((k, val) {
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            m['id'] = k.toString();
            list.add(m);
          }
        });
        list.sort((a, b) => (b['lastSeenAt'] ?? '')
            .toString()
            .compareTo((a['lastSeenAt'] ?? '').toString()));
      }
      if (mounted) setState(() => _clientBugs = list);
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _clientSub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered => _statusFilter == 'all'
      ? _clientBugs
      : _clientBugs
          .where((b) => (b['status'] ?? 'detected') == _statusFilter)
          .toList();

  @override
  Widget build(BuildContext context) {
    final detected =
        _clientBugs.where((b) => (b['status'] ?? 'detected') == 'detected').length;
    final fixed = _clientBugs.where((b) => b['status'] == 'ai_fixed').length;
    final escalated =
        _clientBugs.where((b) => b['status'] == 'escalated').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SaSectionHeader(
                      icon: Icons.bug_report_outlined,
                      title: 'DETECTED BUGS',
                      subtitle:
                          'Runtime errors from every client, deduplicated. The autonomous agent marks what it fixed or escalated.',
                      accent: Sa.red,
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          GlowChip(label: '$detected OPEN', color: Sa.amber),
                          GlowChip(label: '$fixed AI FIXED', color: Sa.green),
                          GlowChip(label: '$escalated ESCALATED', color: Sa.red),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final f in const [
                          ('all', 'ALL'),
                          ('detected', 'DETECTED'),
                          ('ai_fixed', 'AI FIXED'),
                          ('escalated', 'ESCALATED'),
                        ])
                          _SectionPill(
                            icon: Icons.filter_alt_outlined,
                            label: f.$2,
                            selected: _statusFilter == f.$1,
                            onTap: () => setState(() => _statusFilter = f.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_error != null)
                      SaEmptyState(
                        icon: Icons.lock_outline,
                        title: 'Cannot read bug records',
                        message: _error!,
                        accent: Sa.red,
                      )
                    else if (_filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: SaEmptyState(
                          icon: Icons.verified_outlined,
                          title: 'No bugs on record',
                          message:
                              'Client errors land here automatically the moment any user hits one.',
                          accent: Sa.green,
                        ),
                      )
                    else
                      ..._filtered.map((b) => _BugCard(bug: b)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BugCard extends StatefulWidget {
  final Map<String, dynamic> bug;
  const _BugCard({required this.bug});

  @override
  State<_BugCard> createState() => _BugCardState();
}

class _BugCardState extends State<_BugCard> {
  bool _expanded = false;

  static Map<String, Color> get _areaColors => {
        'auth': Sa.amber,
        'notifications': Sa.cyan,
        'database': Sa.red,
        'locator': Sa.blue,
        'supervisors': Sa.violet,
        'voice': Sa.pink,
        'shifts': Sa.green,
        'ai': Sa.violet,
        'app': Sa.muted,
      };

  @override
  Widget build(BuildContext context) {
    final b = widget.bug;
    final status = (b['status'] ?? 'detected').toString();
    final area = (b['area'] ?? 'app').toString();
    final count = (b['count'] as num?)?.toInt() ?? 1;
    final issueUrl = (b['issueUrl'] ?? '').toString();
    final commit = (b['fixCommit'] ?? '').toString();

    final (statusColor, statusLabel, statusIcon) = switch (status) {
      'ai_fixed' => (Sa.green, 'AI FIXED', Icons.auto_fix_high),
      'escalated' => (Sa.red, 'ESCALATED TO GITHUB', Icons.fork_right),
      _ => (Sa.amber, 'DETECTED', Icons.radar),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GlowChip(
                      label: area.toUpperCase(),
                      color: _areaColors[area] ?? Sa.muted),
                  const SizedBox(width: 8),
                  GlowChip(
                      label: statusLabel, color: statusColor, icon: statusIcon),
                  const Spacer(),
                  Text('×$count', style: Sa.mono(size: 11, color: Sa.textDim)),
                  const SizedBox(width: 10),
                  Text(_shortTime(b['lastSeenAt']),
                      style: Sa.mono(size: 10, color: Sa.muted)),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: Sa.muted),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (b['message'] ?? '').toString(),
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: Sa.body(size: 12.5),
              ),
              if (_expanded) ...[
                if ((b['error'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MonoBlock(text: (b['error'] ?? '').toString()),
                ],
                if ((b['stack'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MonoBlock(text: (b['stack'] ?? '').toString()),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Text('first seen ${_shortTime(b['firstSeenAt'])}',
                        style: Sa.mono(size: 9.5, color: Sa.muted)),
                    Text('platform ${b['platform'] ?? '—'}',
                        style: Sa.mono(size: 9.5, color: Sa.muted)),
                    if (commit.isNotEmpty)
                      Text('fix commit $commit',
                          style: Sa.mono(size: 9.5, color: Sa.green)),
                  ],
                ),
                if (issueUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () =>
                        launchUrl(Uri.parse(issueUrl), mode: LaunchMode.externalApplication),
                    icon: Icon(Icons.open_in_new, size: 13, color: Sa.cyan),
                    label: Text('Open GitHub issue',
                        style: Sa.mono(size: 10.5, color: Sa.cyan)),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonoBlock extends StatelessWidget {
  final String text;
  const _MonoBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    // Terminal block: stays dark in both themes for log readability.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Sa.termBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Sa.termBorder),
      ),
      child: SelectableText(text,
          style: Sa.mono(size: 10, color: Sa.termDim), maxLines: 14),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONSOLE
// ═══════════════════════════════════════════════════════════════════════════

class _ConsoleSection extends StatefulWidget {
  const _ConsoleSection();

  @override
  State<_ConsoleSection> createState() => _ConsoleSectionState();
}

class _ConsoleSectionState extends State<_ConsoleSection> {
  StreamSubscription<List<AppLogEntry>>? _sub;
  List<AppLogEntry> _entries = AppLogBuffer.instance.entries;
  String _levelFilter = 'ALL';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _sub = AppLogBuffer.instance.stream.listen((entries) {
      if (!mounted) return;
      setState(() => _entries = entries);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // Fixed bright colors: console lines render on the dark terminal surface
  // in both themes.
  static const _levelColors = {
    'ERROR': Color(0xFFF87171),
    'WARN': Color(0xFFFBBF24),
    'INFO': Color(0xFF3B82F6),
    'DEBUG': Color(0xFF64748B),
  };

  @override
  Widget build(BuildContext context) {
    final filtered = _levelFilter == 'ALL'
        ? _entries
        : _entries.where((e) => e.level == _levelFilter).toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.terminal,
              title: 'LIVE APPLICATION CONSOLE',
              subtitle:
                  'In-memory log buffer of this session (${_entries.length}/${AppLogBuffer.capacity} lines).',
              accent: Sa.cyan,
              trailing: TextButton.icon(
                onPressed: () => AppLogBuffer.instance.clear(),
                icon: Icon(Icons.delete_sweep_outlined,
                    size: 15, color: Sa.muted),
                label:
                    Text('CLEAR', style: Sa.mono(size: 10, color: Sa.muted)),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final lvl in const ['ALL', 'ERROR', 'WARN', 'INFO', 'DEBUG'])
                  _SectionPill(
                    icon: Icons.circle,
                    label: lvl,
                    selected: _levelFilter == lvl,
                    onTap: () => setState(() => _levelFilter = lvl),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF020710),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Sa.termBorder),
                ),
                child: filtered.isEmpty
                    ? Center(
                        child: Text('— console buffer empty —',
                            style: Sa.mono(size: 11, color: Sa.termMuted)))
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          final color = _levelColors[e.level] ?? Sa.termDim;
                          final hh = e.at.hour.toString().padLeft(2, '0');
                          final mm = e.at.minute.toString().padLeft(2, '0');
                          final ss = e.at.second.toString().padLeft(2, '0');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: SelectableText.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                      text: '[$hh:$mm:$ss] ',
                                      style: Sa.mono(
                                          size: 10.5, color: Sa.termMuted)),
                                  TextSpan(
                                      text: '[${e.level}] ',
                                      style: Sa.mono(
                                          size: 10.5,
                                          color: color,
                                          weight: FontWeight.w700)),
                                  TextSpan(
                                      text: e.message,
                                      style: Sa.mono(
                                          size: 10.5, color: Sa.termText)),
                                  if (e.error != null)
                                    TextSpan(
                                        text: '  ⟵ ${e.error}',
                                        style: Sa.mono(
                                            size: 10.5, color: color)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECURITY
// ═══════════════════════════════════════════════════════════════════════════

class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  StreamSubscription<DatabaseEvent>? _logsSub;
  StreamSubscription<DatabaseEvent>? _actionsSub;
  List<Map<String, dynamic>> _logs = const [];
  List<Map<String, dynamic>> _actions = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _logsSub = FirebaseDatabase.instance
        .ref('security/logs')
        .limitToLast(60)
        .onValue
        .listen((e) {
      if (mounted) setState(() => _logs = _decode(e.snapshot.value));
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
    _actionsSub = FirebaseDatabase.instance
        .ref('security/actions')
        .limitToLast(60)
        .onValue
        .listen((e) {
      if (mounted) setState(() => _actions = _decode(e.snapshot.value));
    }, onError: (_) {});
  }

  static List<Map<String, dynamic>> _decode(Object? v) {
    final list = <Map<String, dynamic>>[];
    if (v is Map) {
      v.forEach((k, val) {
        if (val is Map) {
          final m = Map<String, dynamic>.from(val);
          m['id'] = k.toString();
          list.add(m);
        }
      });
      list.sort(
          (a, b) => (b['at'] ?? '').toString().compareTo((a['at'] ?? '').toString()));
    }
    return list;
  }

  @override
  void dispose() {
    _logsSub?.cancel();
    _actionsSub?.cancel();
    super.dispose();
  }

  static Map<String, Color> get _kindColors => {
        'rate_limit': Sa.amber,
        'prompt_injection': Sa.red,
        'blocked': Sa.red,
        'sanitize': Sa.amber,
        'alert_flood': Sa.red,
        'malformed_alerts': Sa.amber,
        'notification_backlog': Sa.blue,
        'auth_surge': Sa.violet,
      };

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: SaEmptyState(
          icon: Icons.lock_outline,
          title: 'Security telemetry unavailable',
          message:
              'Reading security/logs failed: $_error\nDeploy the updated database rules to grant SuperAdmin read access.',
          accent: Sa.red,
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            final blocked = GlassPanel(
              child: _eventList(
                'PREVENTED ATTACKS & ENFORCEMENTS',
                'Rate limits, injection blocks and sanitizations applied by the edge security agent.',
                Icons.gpp_good_outlined,
                Sa.red,
                _actions,
                emptyText:
                    'No enforcement actions — nothing hostile has hit the workers recently.',
              ),
            );
            final observed = GlassPanel(
              child: _eventList(
                'ANOMALY OBSERVATIONS',
                'Floods, malformed payloads, backlogs and auth surges spotted by the scan.',
                Icons.radar_outlined,
                Sa.amber,
                _logs,
                emptyText: 'No anomalies observed in the last scans.',
              ),
            );
            if (narrow) {
              return Column(children: [blocked, const SizedBox(height: 16), observed]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: blocked),
                const SizedBox(width: 16),
                Expanded(child: observed),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _eventList(
    String title,
    String subtitle,
    IconData icon,
    Color accent,
    List<Map<String, dynamic>> events, {
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SaSectionHeader(
          icon: icon,
          title: title,
          subtitle: subtitle,
          accent: accent,
          trailing: GlowChip(label: '${events.length}', color: accent),
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(emptyText, style: Sa.body(size: 12, color: Sa.textDim)),
          )
        else
          ...events.take(30).map((e) {
            final kind = (e['kind'] ?? '').toString();
            final color = _kindColors[kind] ?? Sa.cyan;
            final endpoint = (e['endpoint'] ?? '').toString();
            final fp = (e['fingerprint'] ?? '').toString();
            final reason = (e['reason'] ?? e['matches'] ?? '').toString();
            return Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Sa.bgRaised.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Sa.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(kind.isEmpty ? 'event' : kind,
                              style: Sa.mono(
                                  size: 10.5,
                                  color: color,
                                  weight: FontWeight.w700)),
                          if (endpoint.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(endpoint,
                                style: Sa.mono(size: 10, color: Sa.textDim)),
                          ],
                        ]),
                        if (reason.isNotEmpty)
                          Text(reason,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Sa.body(size: 11, color: Sa.muted)),
                      ],
                    ),
                  ),
                  if (fp.isNotEmpty)
                    Text(
                      fp.length > 8 ? '…${fp.substring(fp.length - 8)}' : fp,
                      style: Sa.mono(size: 9, color: Sa.muted),
                    ),
                  const SizedBox(width: 8),
                  Text(_shortTime(e['at']),
                      style: Sa.mono(size: 9.5, color: Sa.muted)),
                ],
              ),
            );
          }),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CRON HEALTH
// ═══════════════════════════════════════════════════════════════════════════

class _CronHealthSection extends StatefulWidget {
  const _CronHealthSection();

  @override
  State<_CronHealthSection> createState() => _CronHealthSectionState();
}

class _CronHealthSectionState extends State<_CronHealthSection> {
  StreamSubscription<DatabaseEvent>? _aiSub;
  StreamSubscription<DatabaseEvent>? _notifySub;
  StreamSubscription<DatabaseEvent>? _backupSub;
  StreamSubscription<DatabaseEvent>? _monitorSub;
  Map<String, dynamic>? _ai;
  Map<String, dynamic>? _notify;
  Map<String, dynamic>? _backup;
  Map<String, dynamic>? _monitor;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _aiSub = FirebaseDatabase.instance
        .ref('workers/health/lastRun')
        .onValue
        .listen((e) {
      if (mounted) {
        setState(() =>
            _ai = e.snapshot.value is Map ? Map<String, dynamic>.from(e.snapshot.value as Map) : null);
      }
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
    _notifySub = FirebaseDatabase.instance
        .ref('workers/health/notifyLastRun')
        .onValue
        .listen((e) {
      if (mounted) {
        setState(() => _notify =
            e.snapshot.value is Map ? Map<String, dynamic>.from(e.snapshot.value as Map) : null);
      }
    }, onError: (_) {});
    _backupSub = FirebaseDatabase.instance
        .ref('workers/health/backup')
        .onValue
        .listen((e) {
      if (mounted) {
        setState(() => _backup =
            e.snapshot.value is Map ? Map<String, dynamic>.from(e.snapshot.value as Map) : null);
      }
    }, onError: (_) {});
    _monitorSub = FirebaseDatabase.instance
        .ref('workers/health/monitor')
        .onValue
        .listen((e) {
      if (mounted) {
        setState(() => _monitor =
            e.snapshot.value is Map ? Map<String, dynamic>.from(e.snapshot.value as Map) : null);
      }
    }, onError: (_) {});
    // Re-render every 10s so the freshness ages tick.
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _aiSub?.cancel();
    _notifySub?.cancel();
    _backupSub?.cancel();
    _monitorSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: SaEmptyState(
          icon: Icons.lock_outline,
          title: 'Worker health unavailable',
          message: _error!,
          accent: Sa.red,
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            final ai = _WorkerHealthCard(
              title: 'AI & SECURITY WORKER',
              subtitle: 'alert-notifier — assignments, escalations, predictions, security',
              icon: Icons.psychology_outlined,
              accent: Sa.violet,
              data: _ai,
              metricKeys: const [
                ('aiAssignments', 'AI assignments'),
                ('collaborations', 'Collaborations'),
                ('handovers', 'Handovers'),
                ('securityActions', 'Security actions'),
                ('lstmPredictions', 'Edge forecasts'),
                ('errorCount', 'Errors'),
              ],
            );
            final notify = _WorkerHealthCard(
              title: 'NOTIFICATIONS WORKER',
              subtitle: 'alertsys — push fan-out, FCM, queue sweep',
              icon: Icons.notifications_active_outlined,
              accent: Sa.cyan,
              data: _notify,
              metricKeys: const [
                ('alertsPushed', 'Alerts pushed'),
                ('notificationsPushed', 'Notifications pushed'),
                ('fanout', 'Fan-out'),
                ('tokensCleaned', 'Tokens cleaned'),
                ('errorCount', 'Errors'),
              ],
            );
            final backup = _backupCard();
            final monitor = _monitorCard();
            if (narrow) {
              return Column(children: [
                ai, const SizedBox(height: 16), notify,
                const SizedBox(height: 16), backup,
                const SizedBox(height: 16), monitor,
              ]);
            }
            return Column(children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ai),
                  const SizedBox(width: 16),
                  Expanded(child: notify),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: backup),
                  const SizedBox(width: 16),
                  Expanded(child: monitor),
                ],
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _backupCard() {
    final b = _backup;
    final ok = b != null && b['ok'] != false;
    final at = DateTime.tryParse((b?['at'] ?? '').toString());
    final age = at == null ? null : DateTime.now().toUtc().difference(at.toUtc());
    // Daily backup: healthy if it succeeded and ran within the last 26h.
    final stale = age == null || age.inHours >= 26;
    final color = b == null ? Sa.muted : (!ok ? Sa.red : (stale ? Sa.amber : Sa.green));
    final bytes = b != null && b['bytes'] is num ? (b['bytes'] as num).toInt() : null;
    return GlassPanel(
      accent: color,
      glow: b != null && ok && !stale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.cloud_done_outlined,
            title: 'BACKUP WORKER',
            subtitle: 'alertsys-backup — nightly RTDB snapshot to R2',
            accent: Sa.cyan,
            trailing: GlowChip(
              label: b == null ? 'NO DATA' : (!ok ? 'FAILED' : (stale ? 'STALE' : 'HEALTHY')),
              color: color,
              pulse: b != null && ok && !stale,
            ),
          ),
          const SizedBox(height: 14),
          if (b == null)
            Text(
              'No backup pulse yet. Deploy the backup worker (wrangler.backup.toml) '
              'and run it once.',
              style: Sa.body(size: 12, color: Sa.textDim),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'last backup',
                  value: age == null
                      ? '—'
                      : age.inHours < 1
                          ? '${age.inMinutes}m ago'
                          : '${age.inHours}h ago',
                  icon: Icons.schedule,
                  color: color,
                ),
                if (bytes != null)
                  SaStatTile(
                    label: 'snapshot',
                    value: '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB',
                    icon: Icons.save_alt,
                    color: Sa.cyan,
                  ),
                if (b['ok'] == false)
                  SaStatTile(
                    label: 'error',
                    value: (b['error'] ?? 'failed').toString(),
                    icon: Icons.error_outline,
                    color: Sa.red,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _RawDataExpander(data: b),
          ],
        ],
      ),
    );
  }

  Widget _monitorCard() {
    final m = _monitor;
    final state = (m?['state'] ?? '').toString();
    final degraded = state == 'degraded';
    final at = DateTime.tryParse((m?['at'] ?? '').toString());
    final age = at == null ? null : DateTime.now().toUtc().difference(at.toUtc());
    final color = m == null ? Sa.muted : (degraded ? Sa.red : Sa.green);
    final problems = m?['problems'] is List ? (m!['problems'] as List) : const [];
    return GlassPanel(
      accent: color,
      glow: m != null && !degraded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: Icons.radar_outlined,
            title: 'SYSTEM MONITOR',
            subtitle: 'alertsys-monitor — deadman switch, 5-min checks',
            accent: degraded ? Sa.red : Sa.green,
            trailing: GlowChip(
              label: m == null ? 'NO DATA' : (degraded ? 'DEGRADED' : 'NOMINAL'),
              color: color,
              pulse: m != null && !degraded,
            ),
          ),
          const SizedBox(height: 14),
          if (m == null)
            Text(
              'No monitor pulse yet. Deploy the monitor worker (wrangler.monitor.toml).',
              style: Sa.body(size: 12, color: Sa.textDim),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'last check',
                  value: age == null
                      ? '—'
                      : age.inMinutes < 1
                          ? 'just now'
                          : '${age.inMinutes}m ago',
                  icon: Icons.schedule,
                  color: color,
                ),
                SaStatTile(
                  label: 'issues',
                  value: '${problems.length}',
                  icon: Icons.report_outlined,
                  color: problems.isEmpty ? Sa.green : Sa.red,
                ),
              ],
            ),
            if (problems.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...problems.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 13, color: Sa.red),
                        const SizedBox(width: 7),
                        Expanded(child: Text(p.toString(), style: Sa.body(size: 11.5, color: Sa.textDim))),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 12),
            _RawDataExpander(data: m),
          ],
        ],
      ),
    );
  }
}

class _WorkerHealthCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Map<String, dynamic>? data;
  final List<(String, String)> metricKeys;

  const _WorkerHealthCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.data,
    required this.metricKeys,
  });

  @override
  Widget build(BuildContext context) {
    final at = DateTime.tryParse(
        (data?['at'] ?? data?['finishedAt'] ?? data?['ranAt'] ?? '').toString());
    final age = at == null ? null : DateTime.now().toUtc().difference(at.toUtc());
    final fresh = age != null && age.inMinutes <= 3;
    final statusColor = data == null || age == null
        ? Sa.muted
        : fresh
            ? Sa.green
            : (age.inMinutes <= 10 ? Sa.amber : Sa.red);

    return GlassPanel(
      accent: statusColor,
      glow: fresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SaSectionHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            accent: accent,
            trailing: GlowChip(
              label: data == null || age == null
                  ? 'NO DATA'
                  : fresh
                      ? 'LIVE'
                      : '${age.inMinutes}m STALE',
              color: statusColor,
              pulse: fresh,
            ),
          ),
          const SizedBox(height: 14),
          if (data == null)
            Text(
              'No health pulse found. The worker may not have run yet, or the '
              'updated database rules are not deployed.',
              style: Sa.body(size: 12, color: Sa.textDim),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'last run',
                  value: age == null
                      ? '—'
                      : age.inSeconds < 90
                          ? '${age.inSeconds}s ago'
                          : '${age.inMinutes}m ago',
                  icon: Icons.schedule,
                  color: statusColor,
                ),
                if (data!['durationMs'] != null)
                  SaStatTile(
                    label: 'duration',
                    value: '${data!['durationMs']}ms',
                    icon: Icons.speed,
                    color: Sa.blue,
                  ),
                for (final (key, label) in metricKeys)
                  if (data![key] != null)
                    SaStatTile(
                      label: label,
                      value: '${data![key]}',
                      icon: Icons.tag,
                      color: key == 'errorCount' &&
                              (data![key] as num? ?? 0) > 0
                          ? Sa.red
                          : accent,
                    ),
              ],
            ),
            const SizedBox(height: 12),
            _RawDataExpander(data: data!),
          ],
        ],
      ),
    );
  }
}

class _RawDataExpander extends StatefulWidget {
  final Map<String, dynamic> data;
  const _RawDataExpander({required this.data});

  @override
  State<_RawDataExpander> createState() => _RawDataExpanderState();
}

class _RawDataExpanderState extends State<_RawDataExpander> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.data_object,
              size: 14, color: Sa.muted),
          label: Text(_open ? 'HIDE RAW PULSE' : 'RAW PULSE',
              style: Sa.mono(size: 9.5, color: Sa.muted)),
        ),
        if (_open)
          _MonoBlock(
            text: const JsonEncoder.withIndent('  ').convert(
              widget.data.map((k, v) => MapEntry(k, v is Map ? Map.from(v) : v)),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATABASE CONCEPTION MAP
// ═══════════════════════════════════════════════════════════════════════════

class _DbNodeSpec {
  final String path;
  final String label;
  final String domain;
  final double x; // normalized 0..1
  final double y;
  const _DbNodeSpec(this.path, this.label, this.domain, this.x, this.y);
}

class _DatabaseSection extends StatefulWidget {
  const _DatabaseSection();

  @override
  State<_DatabaseSection> createState() => _DatabaseSectionState();
}

class _DatabaseSectionState extends State<_DatabaseSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final ValueNotifier<double> _tick = ValueNotifier<double>(0);
  int _lastFrameMs = 0;
  final Map<String, int?> _counts = {};
  final Map<String, bool> _reachable = {};
  bool _probing = false;
  DateTime? _probedAt;

  // Theme-aware colors for chips and stat tiles on the glass panel.
  static Map<String, Color> get _domainColors => {
        'operations': Sa.cyan,
        'people': Sa.blue,
        'ai': Sa.violet,
        'coordination': Sa.green,
        'platform': Sa.amber,
      };

  // Fixed bright colors for the map itself — it paints on the dark terminal
  // surface in both themes.
  static const _mapColors = {
    'operations': Color(0xFF22D3EE),
    'people': Color(0xFF3B82F6),
    'ai': Color(0xFFA78BFA),
    'coordination': Color(0xFF34D399),
    'platform': Color(0xFFFBBF24),
  };

  // Hand-placed conceptual layout, grouped by domain.
  static const _nodes = [
    _DbNodeSpec('alerts', 'alerts', 'operations', 0.18, 0.30),
    _DbNodeSpec('alertCounter', 'alertCounter', 'operations', 0.06, 0.14),
    _DbNodeSpec('supervisor_active_alerts', 'active_claims', 'operations', 0.20, 0.58),
    _DbNodeSpec('hierarchy', 'hierarchy', 'operations', 0.07, 0.46),
    _DbNodeSpec('assets', 'assets', 'operations', 0.07, 0.72),
    _DbNodeSpec('users', 'users', 'people', 0.42, 0.16),
    _DbNodeSpec('notifications', 'notifications', 'people', 0.44, 0.44),
    _DbNodeSpec('collaboration_requests', 'collaborations', 'coordination', 0.36, 0.70),
    _DbNodeSpec('help_requests', 'help_requests', 'coordination', 0.50, 0.86),
    _DbNodeSpec('shifts', 'shifts', 'coordination', 0.62, 0.66),
    _DbNodeSpec('shift_presence', 'shift_presence', 'coordination', 0.74, 0.84),
    _DbNodeSpec('ai_decisions', 'ai_decisions', 'ai', 0.62, 0.18),
    _DbNodeSpec('ai_predictions', 'ai_predictions', 'ai', 0.74, 0.38),
    _DbNodeSpec('ai_forecast', 'ai_forecast', 'ai', 0.88, 0.20),
    _DbNodeSpec('ai_briefing', 'ai_briefing', 'ai', 0.86, 0.54),
    _DbNodeSpec('security/logs', 'security', 'platform', 0.90, 0.76),
    _DbNodeSpec('workers/health', 'worker_health', 'platform', 0.74, 0.10),
    _DbNodeSpec('bugs/client', 'bugs', 'platform', 0.94, 0.40),
  ];

  static const _edges = [
    ('alerts', 'users'),
    ('alerts', 'alertCounter'),
    ('alerts', 'supervisor_active_alerts'),
    ('alerts', 'hierarchy'),
    ('hierarchy', 'assets'),
    ('users', 'notifications'),
    ('alerts', 'notifications'),
    ('alerts', 'collaboration_requests'),
    ('collaboration_requests', 'help_requests'),
    ('users', 'shifts'),
    ('shifts', 'shift_presence'),
    ('alerts', 'ai_decisions'),
    ('ai_decisions', 'ai_predictions'),
    ('ai_forecast', 'ai_predictions'),
    ('ai_predictions', 'ai_briefing'),
    ('workers/health', 'ai_decisions'),
    ('workers/health', 'security/logs'),
    ('bugs/client', 'workers/health'),
  ];

  @override
  void initState() {
    super.initState();
    _anim =
        AnimationController(vsync: this, duration: const Duration(seconds: 24))
          ..addListener(_onFrame)
          ..repeat();
    _probe();
  }

  void _onFrame() {
    // Cap the map animation at ~25fps; the drift is slow enough that this is
    // visually identical while keeping the tab light.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameMs < 40) return;
    _lastFrameMs = now;
    _tick.value = _anim.value;
  }

  @override
  void dispose() {
    _anim.dispose();
    _tick.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    if (_probing) return;
    setState(() => _probing = true);
    final dbUrl =
        FirebaseDatabase.instance.app.options.databaseURL?.replaceAll(RegExp(r'/$'), '');
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    for (final node in _nodes) {
      var count = _counts[node.path];
      var ok = false;
      if (dbUrl != null && token != null) {
        try {
          final res = await http
              .get(Uri.parse('$dbUrl/${node.path}.json?shallow=true&auth=$token'))
              .timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            ok = true;
            final body = jsonDecode(res.body);
            count = body is Map ? body.length : (body == null ? 0 : 1);
          }
        } catch (_) {}
      }
      _counts[node.path] = count;
      _reachable[node.path] = ok;
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() {
        _probing = false;
        _probedAt = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaSectionHeader(
                  icon: Icons.schema_outlined,
                  title: 'DATABASE CONCEPTION — REALTIME TOPOLOGY',
                  subtitle:
                      'Live map of the Realtime Database roots, their relationships and per-node health.',
                  accent: Sa.green,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_probedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                              'probed ${_shortTime(_probedAt!.toIso8601String())}',
                              style: Sa.mono(size: 9.5, color: Sa.muted)),
                        ),
                      SaButton(
                        label: 'RESCAN',
                        icon: Icons.radar,
                        outlined: true,
                        busy: _probing,
                        onPressed: _probing ? null : _probe,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final d in _domainColors.entries)
                      GlowChip(label: d.key.toUpperCase(), color: d.value),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  final height =
                      math.max(420.0, constraints.maxWidth * 0.46);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: height,
                      decoration: BoxDecoration(
                        color: Sa.termBg,
                        border: Border.all(color: Sa.termBorder),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SchemaPainter(
                            tick: _tick,
                            nodes: _nodes,
                            edges: _edges,
                            counts: _counts,
                            reachable: _reachable,
                            domainColors: _mapColors,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final n in _nodes)
                      SaStatTile(
                        label: n.label,
                        value: _counts[n.path] == null
                            ? '—'
                            : '${_counts[n.path]}',
                        icon: _reachable[n.path] == true
                            ? Icons.check_circle_outline
                            : Icons.help_outline,
                        color: _reachable[n.path] == true
                            ? (_domainColors[n.domain] ?? Sa.cyan)
                            : Sa.muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SchemaPainter extends CustomPainter {
  final ValueNotifier<double> tick;
  final List<_DbNodeSpec> nodes;
  final List<(String, String)> edges;
  final Map<String, int?> counts;
  final Map<String, bool> reachable;
  final Map<String, Color> domainColors;

  _SchemaPainter({
    required this.tick,
    required this.nodes,
    required this.edges,
    required this.counts,
    required this.reachable,
    required this.domainColors,
  }) : super(repaint: tick);

  double get t => tick.value;

  @override
  void paint(Canvas canvas, Size size) {
    final pos = <String, Offset>{};
    for (final n in nodes) {
      // Tiny orbital wobble keeps the map alive.
      final wobble = math.sin(t * math.pi * 2 + n.x * 13 + n.y * 7) * 3;
      pos[n.path] = Offset(
        n.x * (size.width - 140) + 70,
        n.y * (size.height - 90) + 45 + wobble,
      );
    }

    // Edges with travelling pulses.
    for (final (a, b) in edges) {
      final pa = pos[a];
      final pb = pos[b];
      if (pa == null || pb == null) continue;
      canvas.drawLine(
        pa,
        pb,
        Paint()
          ..color = const Color(0x2238BDF8)
          ..strokeWidth = 1,
      );
      final pulseT = (t * 2 + (a.hashCode % 17) / 17) % 1.0;
      final pulsePos = Offset.lerp(pa, pb, pulseT)!;
      canvas.drawCircle(pulsePos, 2,
          Paint()..color = const Color(0xFF22D3EE).withValues(alpha: 0.55));
    }

    // Nodes (always on the dark terminal surface; fixed bright colors).
    for (final n in nodes) {
      final p = pos[n.path]!;
      final color = domainColors[n.domain] ?? const Color(0xFF22D3EE);
      final ok = reachable[n.path] == true;
      final count = counts[n.path];

      final glow = 0.5 + 0.5 * math.sin(t * math.pi * 4 + n.x * 20);
      canvas.drawCircle(
        p,
        20 + glow * 2,
        Paint()..color = color.withValues(alpha: ok ? 0.10 : 0.04),
      );
      canvas.drawCircle(
        p,
        14,
        Paint()
          ..color = const Color(0xFF081127)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        p,
        14,
        Paint()
          ..color =
              ok ? color : const Color(0xFF64748B).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );

      // Health dot.
      canvas.drawCircle(
        p + const Offset(10, -10),
        3.2,
        Paint()
          ..color = ok ? const Color(0xFF34D399) : const Color(0xFF64748B),
      );

      _text(canvas, n.label, p + const Offset(0, 22), color, 10,
          FontWeight.w600);
      if (count != null) {
        _text(canvas, '$count', p, Sa.termText, 9, FontWeight.w700);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset center, Color color, double size,
      FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SchemaPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════

String _shortTime(Object? iso) {
  final dt = DateTime.tryParse((iso ?? '').toString());
  if (dt == null) return '—';
  final local = dt.toLocal();
  final now = DateTime.now();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '$hh:$mm';
  }
  return '${local.day}/${local.month} $hh:$mm';
}

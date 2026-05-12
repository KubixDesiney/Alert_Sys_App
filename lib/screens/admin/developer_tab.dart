// Admin Developer tab — surfaced only when developer mode is enabled.
//
// Renders a single scrollable workspace with four sections:
//   1. Worker Health Pulse  — live snapshot of the last cron run, including
//      the new `securityActions` counter from the worker.
//   2. Security Actions     — live list of recent BLOCKS (rate-limit hits,
//      prompt-injection rejections, anomaly catches).
//   3. Security Logs        — live list of recent OBSERVATIONS (heartbeats,
//      malformed payloads, etc.).
//   4. Console Logs         — in-memory ring buffer of the Flutter app's
//      logger output.
//
// All Firebase reads are streamed, so the tab updates without manual
// refresh. Reads are gated by the new `security` / `workers` rules added
// to database.rules.json; non-admin users will not have access and the
// stream will surface a friendly error.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../services/app_logger.dart';
import '../../theme.dart';

class AdminDeveloperTab extends StatefulWidget {
  const AdminDeveloperTab({super.key});

  @override
  State<AdminDeveloperTab> createState() => _AdminDeveloperTabState();
}

class _AdminDeveloperTabState extends State<AdminDeveloperTab> {
  late final DatabaseReference _healthRef;
  late final Query _logsQuery;
  late final Query _actionsQuery;

  Map<String, dynamic>? _health;
  List<_SecEvent> _logs = const [];
  List<_SecEvent> _actions = const [];
  List<AppLogEntry> _console = const [];

  StreamSubscription<DatabaseEvent>? _healthSub;
  StreamSubscription<DatabaseEvent>? _logsSub;
  StreamSubscription<DatabaseEvent>? _actionsSub;
  StreamSubscription<List<AppLogEntry>>? _consoleSub;

  String? _healthError;
  String? _logsError;
  String? _actionsError;

  @override
  void initState() {
    super.initState();
    _healthRef = FirebaseDatabase.instance.ref('workers/health/lastRun');
    _logsQuery = FirebaseDatabase.instance
        .ref('security/logs')
        .orderByChild('at')
        .limitToLast(50);
    _actionsQuery = FirebaseDatabase.instance
        .ref('security/actions')
        .orderByChild('at')
        .limitToLast(50);

    _healthSub = _healthRef.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        if (!mounted) return;
        setState(() {
          _health = raw is Map ? Map<String, dynamic>.from(raw) : null;
          _healthError = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _healthError = e.toString());
      },
    );

    _logsSub = _logsQuery.onValue.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _logs = _decodeEvents(event.snapshot.value);
          _logsError = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _logsError = e.toString());
      },
    );

    _actionsSub = _actionsQuery.onValue.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _actions = _decodeEvents(event.snapshot.value);
          _actionsError = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _actionsError = e.toString());
      },
    );

    // Console logs come from the in-memory ring buffer; seed with the
    // current snapshot, then track new lines via the broadcast stream.
    _console = AppLogBuffer.instance.entries.reversed.toList(growable: false);
    _consoleSub = AppLogBuffer.instance.stream.listen((entries) {
      if (!mounted) return;
      setState(() => _console = entries.reversed.toList(growable: false));
    });
  }

  @override
  void dispose() {
    _healthSub?.cancel();
    _logsSub?.cancel();
    _actionsSub?.cancel();
    _consoleSub?.cancel();
    super.dispose();
  }

  /// Decodes a snapshot of /security/logs or /security/actions. Values are
  /// keyed by random ID; we collect them, then sort newest-first by `at`.
  List<_SecEvent> _decodeEvents(Object? raw) {
    if (raw is! Map) return const [];
    final list = <_SecEvent>[];
    raw.forEach((k, v) {
      if (v is Map) {
        list.add(_SecEvent.fromMap(Map<String, dynamic>.from(v)));
      }
    });
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      color: t.scaffold,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DevHeader(),
            const SizedBox(height: 16),
            _HealthPulseCard(health: _health, error: _healthError),
            const SizedBox(height: 14),
            // Two-column on wide screens, stacked on narrow.
            LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth > 980;
                final actionsCard = _EventsCard(
                  title: 'Security Actions',
                  subtitle: 'Blocks taken by the security agent',
                  icon: Icons.shield_outlined,
                  accent: t.red,
                  events: _actions,
                  emptyText: 'No security actions yet — system is calm.',
                  error: _actionsError,
                );
                final logsCard = _EventsCard(
                  title: 'Security Logs',
                  subtitle: 'Recent observations & scan heartbeats',
                  icon: Icons.notes_outlined,
                  accent: t.blue,
                  events: _logs,
                  emptyText: 'Waiting for the first scan heartbeat…',
                  error: _logsError,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: actionsCard),
                      const SizedBox(width: 14),
                      Expanded(child: logsCard),
                    ],
                  );
                }
                return Column(
                  children: [actionsCard, const SizedBox(height: 14), logsCard],
                );
              },
            ),
            const SizedBox(height: 14),
            _ConsoleCard(entries: _console),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────

class _DevHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.navy.withValues(alpha: 0.92),
            t.purple.withValues(alpha: 0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: t.navy.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: const Icon(
              Icons.build_circle_outlined,
              size: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Developer Console',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Security agent telemetry · worker health · live logs',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, size: 13, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
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

// ─────────────────────────────────────────────────────────────────────────
// Worker health pulse
// ─────────────────────────────────────────────────────────────────────────

class _HealthPulseCard extends StatelessWidget {
  final Map<String, dynamic>? health;
  final String? error;

  const _HealthPulseCard({required this.health, required this.error});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final hasData = health != null;

    return _SectionCard(
      title: 'Worker Health Pulse',
      subtitle: hasData
          ? 'Last cron run: ${_fmtAt(health!['timestamp'])}'
          : 'Awaiting first cron tick…',
      icon: Icons.favorite_outline,
      accent: t.green,
      child: error != null
          ? _ErrorBlock(message: error!)
          : !hasData
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          : LayoutBuilder(
              builder: (context, box) {
                final tiles = _buildTiles(context);
                // Wrap so tiles flow on narrow screens.
                return Wrap(spacing: 12, runSpacing: 12, children: tiles);
              },
            ),
    );
  }

  List<Widget> _buildTiles(BuildContext context) {
    final h = health!;
    final t = context.appTheme;
    final errors = (h['errors'] is List)
        ? (h['errors'] as List).cast<dynamic>()
        : const <dynamic>[];
    final secActions = (h['securityActions'] is num)
        ? (h['securityActions'] as num).toInt()
        : 0;

    Color statusColor = t.green;
    String statusText = 'Healthy';
    if (errors.isNotEmpty) {
      statusColor = t.red;
      statusText = '${errors.length} error${errors.length == 1 ? '' : 's'}';
    } else if (secActions > 0) {
      statusColor = t.orange;
      statusText = 'Active defense';
    }

    return [
      _HealthTile(
        label: 'Status',
        value: statusText,
        icon: Icons.health_and_safety_outlined,
        color: statusColor,
      ),
      _HealthTile(
        label: 'Duration',
        value: '${h['durationMs'] ?? 0} ms',
        icon: Icons.timer_outlined,
        color: t.blue,
      ),
      _HealthTile(
        label: 'AI assignments',
        value: '${h['assignmentsMade'] ?? 0}',
        icon: Icons.psychology_outlined,
        color: t.purple,
      ),
      _HealthTile(
        label: 'Collaborations',
        value: '${h['collaborationsApproved'] ?? 0}',
        icon: Icons.handshake_outlined,
        color: t.green,
      ),
      _HealthTile(
        label: 'Handovers',
        value: '${h['handoversGenerated'] ?? 0}',
        icon: Icons.assignment_outlined,
        color: t.orange,
      ),
      _HealthTile(
        label: 'Security actions',
        value: '$secActions',
        icon: Icons.shield_outlined,
        color: secActions > 0 ? t.red : t.muted,
        highlight: secActions > 0,
      ),
    ];
  }
}

class _HealthTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool highlight;

  const _HealthTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.12) : t.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? color.withValues(alpha: 0.5) : t.border,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.textDark,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: t.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Events list (security actions & logs share this widget)
// ─────────────────────────────────────────────────────────────────────────

class _EventsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<_SecEvent> events;
  final String emptyText;
  final String? error;

  const _EventsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.events,
    required this.emptyText,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return _SectionCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      trailing: events.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${events.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
      child: error != null
          ? _ErrorBlock(message: error!)
          : events.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  emptyText,
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                primary: false,
                shrinkWrap: true,
                itemCount: events.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: t.border),
                itemBuilder: (_, i) => _EventRow(event: events[i]),
              ),
            ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final _SecEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final color = _kindColor(event.kind, t);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.kind,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.textDark,
                      ),
                    ),
                    if (event.endpoint != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: t.navyLt,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '/${event.endpoint}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: t.navy,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _fmtTimeShort(event.at),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: t.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (event.summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      event.summary,
                      style: TextStyle(fontSize: 11.5, color: t.text),
                    ),
                  ),
                if (event.fingerprint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'fp ${event.fingerprint}',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: t.muted,
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

// ─────────────────────────────────────────────────────────────────────────
// Console log buffer
// ─────────────────────────────────────────────────────────────────────────

class _ConsoleCard extends StatelessWidget {
  final List<AppLogEntry> entries;

  const _ConsoleCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return _SectionCard(
      title: 'Console',
      subtitle: 'Last ${entries.length} app log lines (in-memory)',
      icon: Icons.terminal_outlined,
      accent: t.muted,
      trailing: TextButton.icon(
        onPressed: () => AppLogBuffer.instance.clear(),
        icon: Icon(Icons.delete_sweep, size: 16, color: t.red),
        label: Text(
          'Clear',
          style: TextStyle(
            color: t.red,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No console output captured yet.',
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          : Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: context.isDark
                    ? const Color(0xFF0B1220)
                    : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.45,
                      color: Color(0xFFE2E8F0),
                    ),
                    children: entries.map(_consoleLine).toList(),
                  ),
                ),
              ),
            ),
    );
  }

  TextSpan _consoleLine(AppLogEntry e) {
    final levelColor = switch (e.level) {
      'ERROR' => const Color(0xFFF87171),
      'WARN' => const Color(0xFFFBBF24),
      'INFO' => const Color(0xFF60A5FA),
      _ => const Color(0xFF94A3B8),
    };
    final time = _fmtTimeShort(e.at);
    return TextSpan(
      children: [
        TextSpan(
          text: '$time ',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        TextSpan(
          text: '[${e.level.padRight(5)}] ',
          style: TextStyle(color: levelColor, fontWeight: FontWeight.w700),
        ),
        TextSpan(text: '${e.message}\n'),
        if (e.error != null)
          TextSpan(
            text: '          → ${e.error}\n',
            style: const TextStyle(color: Color(0xFFFCA5A5)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Generic section card
// ─────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.18 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: t.textDark,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  const _ErrorBlock({required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.red.withValues(alpha: 0.08),
        border: Border.all(color: t.red.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: t.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: t.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────

class _SecEvent {
  final DateTime at;
  final String kind;
  final String? endpoint;
  final String? fingerprint;
  final String summary;
  final Map<String, dynamic> raw;

  _SecEvent({
    required this.at,
    required this.kind,
    required this.summary,
    this.endpoint,
    this.fingerprint,
    required this.raw,
  });

  factory _SecEvent.fromMap(Map<String, dynamic> m) {
    final atStr = m['at']?.toString();
    final at = atStr != null
        ? (DateTime.tryParse(atStr) ?? DateTime.now())
        : DateTime.now();
    final kind = (m['kind'] ?? 'event').toString();
    final endpoint = m['endpoint']?.toString();
    final fp = m['fingerprint']?.toString();
    // Build a human summary from whichever extra fields are present.
    final parts = <String>[];
    if (m['observed'] != null && m['limit'] != null) {
      parts.add('observed ${m['observed']} / limit ${m['limit']}');
    }
    if (m['count'] != null) parts.add('count ${m['count']}');
    if (m['threshold'] != null) parts.add('threshold ${m['threshold']}');
    if (m['matches'] is List) {
      parts.add('matches: ${(m['matches'] as List).join(', ')}');
    }
    if (m['field'] != null) parts.add('field ${m['field']}');
    if (m['reason'] != null) parts.add(m['reason'].toString());
    if (m['total'] != null) parts.add('total ${m['total']}');
    if (m['windowMin'] != null) parts.add('window ${m['windowMin']} min');
    if (m['alertsScanned'] != null) {
      parts.add('alerts ${m['alertsScanned']}');
    }
    return _SecEvent(
      at: at,
      kind: kind,
      endpoint: endpoint,
      fingerprint: fp,
      summary: parts.join(' · '),
      raw: m,
    );
  }
}

// Light-touch color mapping so the eye can pick out blocks from heartbeats.
Color _kindColor(String kind, AppTheme t) {
  switch (kind) {
    case 'rate_limit_block':
    case 'prompt_injection_block':
    case 'auth_failure_surge':
    case 'alert_flood_detected':
    case 'notifications_backlog':
      return t.red;
    case 'bad_payload':
      return t.orange;
    case 'malformed_alerts_seen':
      return t.yellow;
    case 'scan_heartbeat':
      return t.green;
    case 'scan_error':
      return t.red;
    default:
      return t.blue;
  }
}

String _fmtAt(Object? raw) {
  if (raw == null) return '—';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  return _fmtTimeShort(dt);
}

String _fmtTimeShort(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  final s = local.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

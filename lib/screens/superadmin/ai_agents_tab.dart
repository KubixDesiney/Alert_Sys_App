import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'superadmin_theme.dart';

/// SuperAdmin tab: the AI AGENT FLEET.
///
/// Every autonomous intelligence in the platform gets a face here: the Shift
/// Commander, the Briefing officer, the AI Assist co-pilot, the Security
/// Sentinel, the Predictive Core and the (under construction) Guardian. Each
/// agent can be toggled on/off platform-wide, exposes its full action log
/// with in-depth details, a live stats deck, and agent-specific controls —
/// the AI Assist prompt template is editable, the Security Sentinel's
/// defenses can be armed per-feature, and the Predictive Core shows its
/// learning curves, absorption and self-graded forecast accuracy.
///
/// Master switches and per-agent settings live under `ai_agents/{id}` in
/// RTDB; the Cloudflare AI worker reads the same node (60s cache) and gates
/// its cron + HTTP behavior accordingly.
class AiAgentsTab extends StatefulWidget {
  const AiAgentsTab({super.key});

  @override
  State<AiAgentsTab> createState() => _AiAgentsTabState();
}

/// Static identity of one fleet agent.
class _AgentSpec {
  final String id;
  final String name;
  final String role;
  final String codename;
  final IconData icon;
  final bool maintenance;

  const _AgentSpec({
    required this.id,
    required this.name,
    required this.role,
    required this.codename,
    required this.icon,
    this.maintenance = false,
  });

  Color get accent => switch (id) {
        'shift' => Sa.cyan,
        'briefing' => Sa.blue,
        'assist' => Sa.green,
        'security' => Sa.red,
        'predictive' => Sa.violet,
        _ => Sa.amber,
      };
}

const List<_AgentSpec> _kAgents = [
  _AgentSpec(
    id: 'shift',
    name: 'SHIFT COMMANDER',
    codename: 'UNIT-01 · ORCHESTRA',
    role: 'Runs shifts: AI assignments, collaborations, handovers',
    icon: Icons.military_tech_outlined,
  ),
  _AgentSpec(
    id: 'briefing',
    name: 'BRIEFING OFFICER',
    codename: 'UNIT-02 · HERALD',
    role: 'Writes the morning briefings every PM reads',
    icon: Icons.campaign_outlined,
  ),
  _AgentSpec(
    id: 'assist',
    name: 'AI ASSIST',
    codename: 'UNIT-03 · MENTOR',
    role: 'Suggests resolutions to supervisors from past fixes',
    icon: Icons.support_agent_outlined,
  ),
  _AgentSpec(
    id: 'security',
    name: 'SECURITY SENTINEL',
    codename: 'UNIT-04 · AEGIS',
    role: 'Blocks injections, floods and anomalies at the edge',
    icon: Icons.gpp_good_outlined,
  ),
  _AgentSpec(
    id: 'predictive',
    name: 'PREDICTIVE CORE',
    codename: 'UNIT-05 · ORACLE',
    role: 'Forecasts machine failures and grades itself daily',
    icon: Icons.online_prediction_outlined,
  ),
  _AgentSpec(
    id: 'guardian',
    name: 'GUARDIAN',
    codename: 'UNIT-06 · CLASSIFIED',
    role: 'Under maintenance — capabilities not yet disclosed',
    icon: Icons.shield_moon_outlined,
    maintenance: true,
  ),
];

class _AiAgentsTabState extends State<AiAgentsTab> {
  int _selected = 0;
  final Map<String, bool> _enabled = {};
  final List<StreamSubscription<DatabaseEvent>> _subs = [];
  Map<String, dynamic>? _health;

  @override
  void initState() {
    super.initState();
    for (final agent in _kAgents) {
      _subs.add(FirebaseDatabase.instance
          .ref('ai_agents/${agent.id}/enabled')
          .onValue
          .listen((event) {
        if (mounted) {
          setState(() => _enabled[agent.id] = event.snapshot.value != false);
        }
      }, onError: (_) {}));
    }
    _subs.add(FirebaseDatabase.instance
        .ref('workers/health/lastRun')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted && v is Map) {
        setState(() => _health = Map<String, dynamic>.from(v));
      }
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool _isEnabled(String id) => _enabled[id] ?? true;

  Future<void> _setEnabled(_AgentSpec agent, bool value) async {
    setState(() => _enabled[agent.id] = value);
    try {
      await FirebaseDatabase.instance.ref('ai_agents/${agent.id}').update({
        'enabled': value,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            value
                ? '${agent.name} is back online.'
                : '${agent.name} taken offline — the worker stands down within 60s.',
            style: Sa.body(size: 12.5),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enabled[agent.id] = !value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Could not update ${agent.name}: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = _kAgents[_selected];
    final online =
        _kAgents.where((a) => !a.maintenance && _isEnabled(a.id)).length;
    final cronAt = DateTime.tryParse((_health?['timestamp'] ?? '').toString());
    final cronFresh = cronAt != null &&
        DateTime.now().toUtc().difference(cronAt.toUtc()).inMinutes <= 3;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _FleetStrip(
            online: online,
            total: _kAgents.length,
            cronFresh: cronFresh,
            health: _health,
            enabledOf: _isEnabled,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kAgents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final a = _kAgents[i];
                return _AgentCard(
                  spec: a,
                  selected: i == _selected,
                  enabled: _isEnabled(a.id),
                  onTap: () => setState(() => _selected = i),
                  onToggle: a.maintenance
                      ? null
                      : (v) => _setEnabled(a, v),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(
              key: ValueKey(agent.id),
              child: switch (agent.id) {
                'shift' => _ShiftAgentPanel(
                    spec: agent, enabled: _isEnabled('shift'), health: _health),
                'briefing' =>
                  _BriefingAgentPanel(spec: agent, enabled: _isEnabled('briefing')),
                'assist' =>
                  _AssistAgentPanel(spec: agent, enabled: _isEnabled('assist')),
                'security' => _SecurityAgentPanel(
                    spec: agent, enabled: _isEnabled('security'), health: _health),
                'predictive' => _PredictiveAgentPanel(
                    spec: agent, enabled: _isEnabled('predictive')),
                _ => _GuardianAgentPanel(spec: agent),
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLEET STRIP + AGENT CARDS
// ═══════════════════════════════════════════════════════════════════════════

class _FleetStrip extends StatelessWidget {
  final int online;
  final int total;
  final bool cronFresh;
  final Map<String, dynamic>? health;
  final bool Function(String) enabledOf;

  const _FleetStrip({
    required this.online,
    required this.total,
    required this.cronFresh,
    required this.health,
    required this.enabledOf,
  });

  @override
  Widget build(BuildContext context) {
    final assignments = (health?['assignmentsMade'] as num?)?.toInt() ?? 0;
    final secActions = (health?['securityActions'] as num?)?.toInt() ?? 0;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: _FleetCorePulse(color: cronFresh ? Sa.cyan : Sa.amber),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI AGENT FLEET', style: Sa.display(size: 15)),
                Text(
                  'Six autonomous units · toggles propagate to the edge worker within 60 seconds',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.mono(size: 9, color: Sa.muted),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              GlowChip(
                label: '$online/$total UNITS ONLINE',
                color: online == total ? Sa.green : Sa.amber,
                pulse: true,
              ),
              GlowChip(
                label: cronFresh ? 'EDGE LINK LIVE' : 'EDGE LINK STALE',
                color: cronFresh ? Sa.cyan : Sa.red,
                icon: Icons.cell_tower,
              ),
              GlowChip(
                label: '$assignments ASSIGNED · LAST CRON',
                color: Sa.violet,
                icon: Icons.auto_awesome,
              ),
              if (secActions > 0)
                GlowChip(
                  label: '$secActions THREATS BLOCKED',
                  color: Sa.red,
                  icon: Icons.gpp_maybe_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pulsing reactor core for the fleet header.
class _FleetCorePulse extends StatefulWidget {
  final Color color;
  const _FleetCorePulse({required this.color});

  @override
  State<_FleetCorePulse> createState() => _FleetCorePulseState();
}

class _FleetCorePulseState extends State<_FleetCorePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CorePainter(color: widget.color, tick: _c),
      ),
    );
  }
}

class _CorePainter extends CustomPainter {
  final Color color;
  final Animation<double> tick;
  _CorePainter({required this.color, required this.tick})
      : super(repaint: tick);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final t = tick.value;
    final r = size.shortestSide / 2;
    // Two counter-rotating orbital arcs.
    for (var k = 0; k < 2; k++) {
      final sweep = math.pi * (0.9 + 0.4 * k);
      final start = (k == 0 ? 1 : -1) * t * math.pi * 2 + k * 2.1;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 2 - k * 4),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.55 - k * 0.2),
      );
    }
    final glow = 0.5 + 0.5 * math.sin(t * math.pi * 4);
    canvas.drawCircle(
        c, r * 0.42, Paint()..color = color.withValues(alpha: 0.12 + 0.1 * glow));
    canvas.drawCircle(c, r * 0.22, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CorePainter old) => old.color != color;
}

class _AgentCard extends StatefulWidget {
  final _AgentSpec spec;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;

  const _AgentCard({
    required this.spec,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onToggle,
  });

  @override
  State<_AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<_AgentCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final accent = spec.accent;
    final live = widget.enabled && !spec.maintenance;
    final borderColor = widget.selected
        ? accent
        : _hover
            ? accent.withValues(alpha: 0.55)
            : Sa.border;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 234,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.selected
                ? accent.withValues(alpha: Sa.isDark ? 0.10 : 0.07)
                : Sa.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: [
              if (widget.selected)
                BoxShadow(
                    color: accent.withValues(alpha: 0.22), blurRadius: 18),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        accent.withValues(alpha: 0.30),
                        accent.withValues(alpha: 0.08),
                      ]),
                      borderRadius: BorderRadius.circular(9),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.55)),
                    ),
                    child: Icon(spec.icon, size: 17, color: accent),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(spec.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Sa.heading(size: 11.5)),
                        Text(spec.codename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Sa.mono(size: 7.5, color: Sa.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  spec.role,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 10.5, color: Sa.textDim),
                ),
              ),
              Row(
                children: [
                  if (spec.maintenance)
                    GlowChip(label: 'MAINTENANCE', color: Sa.amber)
                  else
                    GlowChip(
                      label: live ? 'ONLINE' : 'OFFLINE',
                      color: live ? Sa.green : Sa.muted,
                      pulse: live,
                    ),
                  const Spacer(),
                  if (widget.onToggle != null)
                    _NeonToggle(
                      value: widget.enabled,
                      accent: accent,
                      onChanged: widget.onToggle!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact glowing toggle used across the fleet.
class _NeonToggle extends StatelessWidget {
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _NeonToggle({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 21,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: value
              ? accent.withValues(alpha: 0.30)
              : Sa.muted.withValues(alpha: 0.18),
          border: Border.all(
              color: value ? accent : Sa.muted.withValues(alpha: 0.6)),
          boxShadow: [
            if (value)
              BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 9),
          ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? accent : Sa.muted,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED PANEL SCAFFOLDING
// ═══════════════════════════════════════════════════════════════════════════

class _AgentScroll extends StatelessWidget {
  final List<Widget> children;
  const _AgentScroll({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final _AgentSpec spec;
  const _OfflineBanner({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Sa.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Sa.red.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.power_off_outlined, size: 16, color: Sa.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${spec.name} is OFFLINE. The edge worker skips its duties until you re-enable it; '
              'history below stays readable.',
              style: Sa.body(size: 12, color: Sa.red),
            ),
          ),
        ],
      ),
    );
  }
}

String _agoIso(Object? iso) {
  final t = DateTime.tryParse((iso ?? '').toString());
  if (t == null) return '—';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

List<Map<String, dynamic>> _mapToSortedList(Object? value, String sortKey) {
  final list = <Map<String, dynamic>>[];
  if (value is Map) {
    value.forEach((k, v) {
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        m['id'] = k.toString();
        list.add(m);
      }
    });
    list.sort((a, b) =>
        (b[sortKey] ?? '').toString().compareTo((a[sortKey] ?? '').toString()));
  }
  return list;
}

/// One activity row with an in-depth details dialog.
class _LogTile extends StatelessWidget {
  final String kind;
  final Color color;
  final String title;
  final String? at;
  final Map<String, dynamic> details;

  const _LogTile({
    required this.kind,
    required this.color,
    required this.title,
    required this.at,
    required this.details,
  });

  void _openDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Sa.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GlowChip(label: kind.toUpperCase(), color: color),
                    const Spacer(),
                    Text(_agoIso(at), style: Sa.mono(size: 10, color: Sa.muted)),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, size: 16, color: Sa.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(title, style: Sa.heading(size: 14)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Sa.termBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Sa.termBorder),
                      ),
                      child: SelectableText(
                        details.entries
                            .where((e) =>
                                e.key != 'id' &&
                                (e.value ?? '').toString().isNotEmpty)
                            .map((e) => '${e.key.padRight(16)} ${e.value}')
                            .join('\n'),
                        style: Sa.mono(size: 10.5, color: Sa.termDim),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Sa.border),
      ),
      child: InkWell(
        onTap: () => _openDetails(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 148,
                child: Text(
                  kind.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      Sa.mono(size: 9, color: color, weight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.body(size: 11.5, color: Sa.textDim),
                ),
              ),
              const SizedBox(width: 8),
              Text(_agoIso(at), style: Sa.mono(size: 9.5, color: Sa.muted)),
              const SizedBox(width: 6),
              Icon(Icons.open_in_full, size: 11, color: Sa.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggleable defense/setting row that writes straight to RTDB.
class _SettingTile extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: value ? accent.withValues(alpha: 0.35) : Sa.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: value ? accent : Sa.muted),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Sa.heading(size: 12.5)),
                Text(description,
                    style: Sa.body(size: 10.5, color: Sa.textDim)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _NeonToggle(value: value, accent: accent, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Horizontal labelled bar (used for per-kind activity breakdowns).
class _KindBar extends StatelessWidget {
  final String label;
  final int count;
  final int max;
  final Color color;

  const _KindBar({
    required this.label,
    required this.count,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final frac = max <= 0 ? 0.0 : (count / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Sa.mono(size: 9.5, color: Sa.textDim)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: Sa.border.withValues(alpha: 0.5)),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: frac),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, w, __) => FractionallySizedBox(
                        widthFactor: w,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              color,
                              color.withValues(alpha: 0.55),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: Sa.mono(size: 10.5, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-01 · SHIFT COMMANDER
// ═══════════════════════════════════════════════════════════════════════════

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

  @override
  void initState() {
    super.initState();
    _latestSub = FirebaseDatabase.instance
        .ref('ai_briefing/latest')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted && v is Map) {
        setState(() => _latest = Map<String, dynamic>.from(v));
      }
    }, onError: (_) {});
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
  }

  Future<void> _probeCounts() async {
    try {
      final hist =
          await FirebaseDatabase.instance.ref('ai_briefing/history').get();
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

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.briefingEndpoint}?force=1'))
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
            const SizedBox(height: 14),
            if (latest == null)
              SaEmptyState(
                icon: Icons.hourglass_empty,
                title: 'No briefing yet today',
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
                color: Sa.termBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Sa.termBorder),
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

class _SecurityAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  final Map<String, dynamic>? health;
  const _SecurityAgentPanel(
      {required this.spec, required this.enabled, required this.health});

  @override
  State<_SecurityAgentPanel> createState() => _SecurityAgentPanelState();
}

class _SecurityAgentPanelState extends State<_SecurityAgentPanel> {
  StreamSubscription<DatabaseEvent>? _actionsSub;
  StreamSubscription<DatabaseEvent>? _settingsSub;
  List<Map<String, dynamic>> _actions = const [];
  Map<String, dynamic> _settings = const {};
  String? _error;

  static const _defenses = [
    (
      key: 'promptInjection',
      title: 'Prompt-injection shield',
      desc:
          'Scans every user text field for 12 attack signatures before it can reach Llama.',
      icon: Icons.shield_outlined,
    ),
    (
      key: 'rateLimiting',
      title: 'Rate limiting',
      desc:
          'Per-fingerprint sliding-window budgets on every endpoint (DDoS / quota-burn protection).',
      icon: Icons.speed_outlined,
    ),
    (
      key: 'sanitization',
      title: 'Input sanitization',
      desc:
          'Strips control characters and clamps text length so payloads cannot break prompt framing.',
      icon: Icons.cleaning_services_outlined,
    ),
    (
      key: 'anomalyScan',
      title: 'Anomaly scan',
      desc:
          'Every 30 min: alert floods, malformed records, notification backlogs, auth-failure surges.',
      icon: Icons.radar_outlined,
    ),
    (
      key: 'siemExport',
      title: 'SIEM export',
      desc: 'Ships security events to the external Elastic SOC pipeline.',
      icon: Icons.outbox_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _actionsSub = FirebaseDatabase.instance
        .ref('security/actions')
        .limitToLast(50)
        .onValue
        .listen((event) {
      if (mounted) {
        setState(
            () => _actions = _mapToSortedList(event.snapshot.value, 'at'));
      }
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/security/settings')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _settings = v is Map ? Map<String, dynamic>.from(v) : const {});
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _actionsSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  bool _defenseOn(String key) => _settings[key] != false;

  Future<void> _setDefense(String key, bool value) async {
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/security/settings/$key')
          .set(value);
      if (!value && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text(
            'Defense disabled. The edge worker drops this shield within 60s — re-arm it when done testing.',
            style: Sa.body(size: 12.5, color: Sa.amber),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Sa.panelSolid,
          content: Text('Update failed: $e',
              style: Sa.body(size: 12.5, color: Sa.red)),
        ));
      }
    }
  }

  Color _kindColor(String kind) {
    if (kind.contains('injection')) return Sa.red;
    if (kind.contains('rate')) return Sa.amber;
    if (kind.contains('flood') || kind.contains('backlog')) return Sa.violet;
    if (kind.contains('auth')) return Sa.pink;
    return Sa.blue;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final dayAgo = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final recent = _actions.where((a) {
      final t = DateTime.tryParse((a['at'] ?? '').toString());
      return t != null && t.toUtc().isAfter(dayAgo);
    }).toList();
    final byKind = <String, int>{};
    for (final a in recent) {
      final k = (a['kind'] ?? 'other').toString();
      byKind[k] = (byKind[k] ?? 0) + 1;
    }
    final maxKind = byKind.values.isEmpty ? 0 : byKind.values.reduce(math.max);
    final armed = _defenses.where((d) => _defenseOn(d.key)).length;

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
              title: 'THREAT CONSOLE',
              subtitle:
                  'Standing guard on every worker endpoint. Blocks are logged with the exact signature that fired.',
              accent: spec.accent,
              trailing: GlowChip(
                label: '$armed/${_defenses.length} DEFENSES ARMED',
                color: armed == _defenses.length ? Sa.green : Sa.amber,
                pulse: true,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Blocks · 24h',
                  value: '${recent.length}',
                  icon: Icons.block_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Actions · last cron',
                  value:
                      '${(widget.health?['securityActions'] as num?)?.toInt() ?? 0}',
                  icon: Icons.gpp_maybe_outlined,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Attack signatures',
                  value: '12',
                  icon: Icons.fingerprint,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Last block',
                  value: _actions.isEmpty ? '—' : _agoIso(_actions.first['at']),
                  icon: Icons.schedule,
                  color: Sa.blue,
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
              icon: Icons.tune,
              title: 'DEFENSE GRID',
              subtitle:
                  'Arm or stand down individual shields. Changes reach the edge worker within 60 seconds.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            for (final d in _defenses)
              _SettingTile(
                title: d.title,
                description: d.desc,
                icon: d.icon,
                accent: spec.accent,
                value: _defenseOn(d.key),
                onChanged: (v) => _setDefense(d.key, v),
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
              title: 'THREAT MIX · 24H',
              subtitle: 'What the sentinel has been deflecting.',
              accent: spec.accent,
            ),
            const SizedBox(height: 14),
            if (byKind.isEmpty)
              Text('Clean skies — no blocks in the last 24 hours.',
                  style: Sa.body(size: 12, color: Sa.textDim))
            else
              ...byKind.entries.map((e) => _KindBar(
                    label: e.key,
                    count: e.value,
                    max: maxKind,
                    color: _kindColor(e.key),
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
              title: 'ENFORCEMENT LOG',
              subtitle:
                  'Every block with endpoint, fingerprint and matched patterns. Tap for the full record.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SaEmptyState(
                icon: Icons.lock_outline,
                title: 'Cannot read security actions',
                message: _error!,
                accent: Sa.red,
              )
            else if (_actions.isEmpty)
              SaEmptyState(
                icon: Icons.verified_user_outlined,
                title: 'No enforcement actions',
                message: 'The sentinel has not needed to block anything yet.',
                accent: Sa.green,
              )
            else
              ..._actions.take(30).map((a) {
                final kind = (a['kind'] ?? 'action').toString();
                final fp = (a['fingerprint'] ?? '').toString();
                return _LogTile(
                  kind: kind,
                  color: _kindColor(kind),
                  title:
                      '${a['endpoint'] ?? '—'} · ${fp.length > 10 ? fp.substring(fp.length - 10) : fp}',
                  at: (a['at'] ?? '').toString(),
                  details: a,
                );
              }),
          ],
        ),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-05 · PREDICTIVE CORE
// ═══════════════════════════════════════════════════════════════════════════

class _PredictiveAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  final bool enabled;
  const _PredictiveAgentPanel({required this.spec, required this.enabled});

  @override
  State<_PredictiveAgentPanel> createState() => _PredictiveAgentPanelState();
}

class _PredictiveAgentPanelState extends State<_PredictiveAgentPanel> {
  StreamSubscription<DatabaseEvent>? _accSub;
  StreamSubscription<DatabaseEvent>? _histSub;
  StreamSubscription<DatabaseEvent>? _versionSub;
  StreamSubscription<DatabaseEvent>? _forecastSub;
  StreamSubscription<DatabaseEvent>? _settingsSub;

  Map<String, dynamic>? _accuracy;
  List<Map<String, dynamic>> _gradeHistory = const [];
  Map<String, dynamic> _modelMeta = const {};
  Map<String, dynamic>? _liveForecast;
  Map<String, dynamic> _settings = const {};

  @override
  void initState() {
    super.initState();
    _accSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/latest')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _accuracy = v is Map ? Map<String, dynamic>.from(v) : null);
      }
    }, onError: (_) {});
    _histSub = FirebaseDatabase.instance
        .ref('ai_forecast/accuracy/history')
        .limitToLast(30)
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      final list = <Map<String, dynamic>>[];
      if (v is Map) {
        v.forEach((k, val) {
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            m['day'] = k.toString();
            list.add(m);
          }
        });
        list.sort(
            (a, b) => (a['day'] ?? '').toString().compareTo((b['day'] ?? '').toString()));
      }
      if (mounted) setState(() => _gradeHistory = list);
    }, onError: (_) {});
    // Watch the version only; re-fetch the light metadata children when it
    // bumps (the weights blob never enters this screen).
    _versionSub = FirebaseDatabase.instance
        .ref('ai_forecast/model/version')
        .onValue
        .listen((_) => _loadModelMeta(), onError: (_) {});
    _forecastSub = FirebaseDatabase.instance
        .ref('ai_predictions/forecast')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _liveForecast = v is Map ? Map<String, dynamic>.from(v) : null);
      }
    }, onError: (_) {});
    _settingsSub = FirebaseDatabase.instance
        .ref('ai_agents/predictive/settings')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (mounted) {
        setState(() =>
            _settings = v is Map ? Map<String, dynamic>.from(v) : const {});
      }
    }, onError: (_) {});
  }

  Future<void> _loadModelMeta() async {
    const keys = [
      'version',
      'trainedAt',
      'lastAdaptedAt',
      'datasetName',
      'sampleCount',
      'valLoss',
      'valAccuracy',
      'rounds',
      'adaptedRounds',
      'learning',
      'algo',
    ];
    try {
      final reads = await Future.wait([
        for (final k in keys)
          FirebaseDatabase.instance.ref('ai_forecast/model/$k').get(),
      ]);
      final meta = <String, dynamic>{};
      for (var i = 0; i < keys.length; i++) {
        meta[keys[i]] = reads[i].value;
      }
      if (mounted) setState(() => _modelMeta = meta);
    } catch (_) {}
  }

  Future<void> _setSetting(String key, bool value) async {
    try {
      await FirebaseDatabase.instance
          .ref('ai_agents/predictive/settings/$key')
          .set(value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _histSub?.cancel();
    _versionSub?.cancel();
    _forecastSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final deployed = _modelMeta['trainedAt'] != null;
    final version = (_modelMeta['version'] as num?)?.toInt() ?? 0;
    final adapted = (_modelMeta['adaptedRounds'] as num?)?.toInt() ?? 0;
    final pairs = (_accuracy?['gradedPairs'] as num?)?.toInt() ?? 0;
    final tp = (_accuracy?['tp'] as num?)?.toInt() ?? 0;
    final fp = (_accuracy?['fp'] as num?)?.toInt() ?? 0;
    final fn = (_accuracy?['fn'] as num?)?.toInt() ?? 0;
    final precision = (tp + fp) == 0 ? 0.0 : tp / (tp + fp);
    final recall = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
    final brier = pairs == 0
        ? 0.0
        : ((_accuracy?['brierSum'] as num?)?.toDouble() ?? 0) / pairs;
    final machines = (_liveForecast?['machineCount'] as num?)?.toInt() ?? 0;

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
              title: 'MODEL CORE',
              subtitle: deployed
                  ? 'On-device gradient-boosted forecaster, live on every Production Manager dashboard.'
                  : 'No model deployed yet — train one in the AI Training tab.',
              accent: spec.accent,
              trailing: Wrap(
                spacing: 6,
                children: [
                  GlowChip(
                    label: 'SIA-GBDT v$version',
                    color: spec.accent,
                    icon: Icons.account_tree_outlined,
                  ),
                  if (_modelMeta['learning'] == true)
                    GlowChip(label: 'LEARNING ✓', color: Sa.green),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SaStatTile(
                  label: 'Dataset',
                  value: (_modelMeta['datasetName'] ?? '—').toString(),
                  icon: Icons.dataset_outlined,
                  color: spec.accent,
                ),
                SaStatTile(
                  label: 'Training samples',
                  value: '${(_modelMeta['sampleCount'] as num?)?.toInt() ?? 0}',
                  icon: Icons.grain,
                  color: Sa.blue,
                ),
                SaStatTile(
                  label: 'Boosted rounds',
                  value:
                      '${(_modelMeta['rounds'] as num?)?.toInt() ?? 0} + $adapted adapted',
                  icon: Icons.forest_outlined,
                  color: Sa.green,
                ),
                SaStatTile(
                  label: 'Val accuracy',
                  value:
                      '${(((_modelMeta['valAccuracy'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%',
                  icon: Icons.verified_outlined,
                  color: Sa.violet,
                ),
                SaStatTile(
                  label: 'Machines forecast',
                  value: '$machines',
                  icon: Icons.precision_manufacturing_outlined,
                  color: Sa.amber,
                ),
                SaStatTile(
                  label: 'Trained',
                  value: _agoIso(_modelMeta['trainedAt']),
                  icon: Icons.schedule,
                  color: Sa.muted,
                ),
              ],
            ),
          ],
        ),
      ),
      GlassPanel(
        accent: spec.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaSectionHeader(
              icon: Icons.psychology_outlined,
              title: 'CONTINUOUS LEARNING',
              subtitle:
                  'The core snapshots tomorrow’s forecast daily, grades itself against the alerts that really happened, and boosts adaptation trees on fresh data.',
              accent: spec.accent,
              trailing: GlowChip(
                label: _accuracy == null
                    ? 'AWAITING FIRST GRADE'
                    : '${(_accuracy?['gradedDays'] as num?)?.toInt() ?? 0} DAYS GRADED',
                color: _accuracy == null ? Sa.muted : Sa.green,
                pulse: _accuracy != null,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (ctx, c) {
              final wide = c.maxWidth >= 760;
              final gauges = Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RingGauge(
                      label: 'PRECISION',
                      value: precision,
                      color: spec.accent),
                  _RingGauge(label: 'RECALL', value: recall, color: Sa.cyan),
                  _RingGauge(
                    label: 'BRIER',
                    value: (1 - brier).clamp(0.0, 1.0),
                    display: brier.toStringAsFixed(3),
                    color: Sa.green,
                  ),
                ],
              );
              final chart = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FORECAST QUALITY TREND · BRIER PER GRADED DAY',
                      style: Sa.mono(size: 8.5, color: Sa.muted)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 110,
                    child: _gradeHistory.isEmpty
                        ? Center(
                            child: Text(
                              'Trend appears after the first graded day.',
                              style: Sa.body(size: 11, color: Sa.muted),
                            ),
                          )
                        : CustomPaint(
                            size: Size.infinite,
                            painter: _BrierTrendPainter(
                              history: _gradeHistory,
                              color: spec.accent,
                              gridColor: Sa.border,
                              textColor: Sa.muted,
                            ),
                          ),
                  ),
                ],
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 330, child: gauges),
                    const SizedBox(width: 20),
                    Expanded(child: chart),
                  ],
                );
              }
              return Column(children: [gauges, const SizedBox(height: 16), chart]);
            }),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('DATA ABSORPTION · ADAPTATION BUDGET',
                        style: Sa.mono(size: 8.5, color: Sa.muted)),
                    const Spacer(),
                    Text('$adapted / 60 extra trees per type',
                        style: Sa.mono(size: 9.5, color: spec.accent)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 8,
                    child: Stack(children: [
                      Container(color: Sa.border.withValues(alpha: 0.5)),
                      FractionallySizedBox(
                        widthFactor: (adapted / 60).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [spec.accent, Sa.cyan]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Graded $pairs machine-type pairs · $tp confirmed hits · last adapted ${_agoIso(_modelMeta['lastAdaptedAt'])} · a full retrain resets the budget.',
                  style: Sa.body(size: 10.5, color: Sa.textDim),
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
              icon: Icons.tune,
              title: 'LEARNING CONTROLS',
              subtitle:
                  'Pause parts of the learning loop without undeploying the model.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            _SettingTile(
              title: 'Continuous adaptation',
              description:
                  'Boost a few stiffly-regularized trees onto the live ensemble (~daily) from recent production alerts.',
              icon: Icons.auto_mode,
              accent: spec.accent,
              value: _settings['adaptationEnabled'] != false,
              onChanged: (v) => _setSetting('adaptationEnabled', v),
            ),
            _SettingTile(
              title: 'Outcome grading',
              description:
                  'Snapshot tomorrow’s forecast each day and grade it against reality (precision/recall/Brier above).',
              icon: Icons.fact_check_outlined,
              accent: spec.accent,
              value: _settings['outcomeGrading'] != false,
              onChanged: (v) => _setSetting('outcomeGrading', v),
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
              title: 'GRADED DAYS',
              subtitle:
                  'Each elapsed forecast day, scored against the alerts that materialized.',
              accent: spec.accent,
            ),
            const SizedBox(height: 12),
            if (_gradeHistory.isEmpty)
              SaEmptyState(
                icon: Icons.pending_actions_outlined,
                title: 'No graded days yet',
                message:
                    'The first grade lands the day after a forecast snapshot — fully automatic, server-side.',
                accent: spec.accent,
              )
            else
              ..._gradeHistory.reversed.take(20).map((g) => _LogTile(
                    kind: 'graded',
                    color: spec.accent,
                    title:
                        '${g['day']} · ${g['pairs'] ?? 0} pairs · ${g['tp'] ?? 0} hits · Brier ${((g['brier'] as num?)?.toDouble() ?? 0).toStringAsFixed(3)}',
                    at: (g['gradedAt'] ?? '').toString(),
                    details: g,
                  )),
          ],
        ),
      ),
    ]);
  }
}

/// Circular gauge with a sweeping arc — precision/recall/Brier display.
class _RingGauge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String? display;

  const _RingGauge({
    required this.label,
    required this.value,
    required this.color,
    this.display,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              painter: _RingPainter(
                  value: v, color: color, track: Sa.border),
              child: Center(
                child: Text(
                  display ?? '${(v * 100).round()}%',
                  style: Sa.mono(size: 13, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Sa.mono(size: 8.5, color: Sa.muted)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  _RingPainter({required this.value, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = track.withValues(alpha: 0.6);
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [color.withValues(alpha: 0.5), color],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        math.pi * 2 * value, false, arc);
    canvas.drawCircle(
        c, r + 4, Paint()..color = color.withValues(alpha: 0.06 * value));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

/// Brier-per-day trend: line + soft area + hit markers. Lower is better.
class _BrierTrendPainter extends CustomPainter {
  final List<Map<String, dynamic>> history;
  final Color color;
  final Color gridColor;
  final Color textColor;

  _BrierTrendPainter({
    required this.history,
    required this.color,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    final briers = [
      for (final h in history) ((h['brier'] as num?)?.toDouble() ?? 0)
    ];
    var maxB = briers.reduce(math.max);
    if (maxB <= 0) maxB = 0.1;
    maxB *= 1.2;

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    Offset pt(int i) {
      final x = history.length == 1
          ? size.width / 2
          : size.width * i / (history.length - 1);
      final y = size.height * (1 - (briers[i] / maxB).clamp(0.0, 1.0));
      return Offset(x, y);
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    final area = Path()..moveTo(pt(0).dx, size.height);
    area.lineTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < history.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
      area.lineTo(pt(i).dx, pt(i).dy);
    }
    area.lineTo(pt(history.length - 1).dx, size.height);
    area.close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    for (var i = 0; i < history.length; i++) {
      canvas.drawCircle(pt(i), 2.4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BrierTrendPainter old) =>
      old.history != history || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT-06 · GUARDIAN
// ═══════════════════════════════════════════════════════════════════════════

class _GuardianAgentPanel extends StatefulWidget {
  final _AgentSpec spec;
  const _GuardianAgentPanel({required this.spec});

  @override
  State<_GuardianAgentPanel> createState() => _GuardianAgentPanelState();
}

class _GuardianAgentPanelState extends State<_GuardianAgentPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return Center(
      child: GlassPanel(
        accent: spec.accent,
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GuardianScanPainter(color: spec.accent, tick: _c),
                  child: Center(
                    child: Icon(spec.icon, size: 36, color: spec.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text('GUARDIAN', style: Sa.display(size: 18)),
            const SizedBox(height: 6),
            GlowChip(label: 'UNDER MAINTENANCE', color: spec.accent, pulse: true),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Unit-06 is being assembled in the hangar. Its mission profile is classified '
                'until commissioning — check back after the next fleet upgrade.',
                textAlign: TextAlign.center,
                style: Sa.body(size: 12.5, color: Sa.textDim),
              ),
            ),
          ],
        ),
      ),
    );
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

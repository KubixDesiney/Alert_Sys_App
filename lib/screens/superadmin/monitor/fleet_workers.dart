import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../hardware/hw_machines.dart';
import '../superadmin_theme.dart';
import 'monitor_data.dart';
import 'monitor_kit.dart';

// ════════════════════════════════════════════════════════════════════════════
//  AI FLEET CONSTELLATION
// ════════════════════════════════════════════════════════════════════════════

class _FleetAgent {
  final String id;
  final String name;
  final String code;
  final IconData icon;
  final String blurb;
  const _FleetAgent(this.id, this.name, this.code, this.icon, this.blurb);

  Color get accent => switch (id) {
        'shift' => Sa.cyan,
        'briefing' => Sa.blue,
        'assist' => Sa.green,
        'security' => Sa.red,
        'predictive' => Sa.violet,
        _ => Sa.amber,
      };
}

// Names and blurbs are translated at render time via `context.tr(...)` — see
// `_AgentNode` and `_AgentDetailPopoverState` below.
const List<_FleetAgent> _kFleet = [
  _FleetAgent('shift', 'SHIFT CMDR', 'UNIT-01', Icons.military_tech_outlined,
      'Runs AI supervisor assignment, cross-factory transfers and shift handovers during active shifts.'),
  _FleetAgent('briefing', 'BRIEFING', 'UNIT-02', Icons.campaign_outlined,
      'Generates the morning briefing — factory-scoped summaries, top predicted failure and top performer.'),
  _FleetAgent('assist', 'AI ASSIST', 'UNIT-03', Icons.support_agent_outlined,
      'Serves resolution suggestions to supervisors from validated alert history.'),
  _FleetAgent('security', 'SENTINEL', 'UNIT-04', Icons.gpp_good_outlined,
      'Guards every endpoint — rate limiting, prompt-injection detection, sanitization and anomaly scans.'),
  _FleetAgent('predictive', 'ORACLE', 'UNIT-05', Icons.online_prediction_outlined,
      'On-device gradient-boosted forecaster — next-24h machine risk, graded continuously against reality.'),
  _FleetAgent('guardian', 'GUARDIAN', 'UNIT-06', Icons.shield_moon_outlined,
      'Autonomous CI self-heal pipeline — detects, fixes and verifies build/test failures.'),
];

class FleetConstellation extends StatefulWidget {
  final MonitorController controller;
  const FleetConstellation({super.key, required this.controller});

  @override
  State<FleetConstellation> createState() => _FleetConstellationState();
}

class _FleetConstellationState extends State<FleetConstellation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final ValueNotifier<double> _tick = ValueNotifier(0);
  int _lastMs = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..addListener(() {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastMs < 33) return;
        _lastMs = now;
        _tick.value = _anim.value;
      })
      ..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = _kFleet.where((a) => widget.controller.agent(a.id).enabled).length;
    return HoloPanel(
      accent: Sa.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoloHeader(
            icon: Icons.hub_outlined,
            title: context.tr('AI AGENT FLEET'),
            subtitle: context.tr(
              'Six autonomous units, live across the platform edge.',
            ),
            accent: Sa.violet,
            trailing: GlowChip(
              label: context.tr('{online} / {total} ONLINE', {
                'online': '$online',
                'total': '${_kFleet.length}',
              }),
              color: online == _kFleet.length ? Sa.green : Sa.amber,
              pulse: true,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 380,
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth, h = c.maxHeight;
              final center = Offset(w / 2, h / 2);
              const sw = 130.0, sh = 112.0;
              final radius = math.min(w, h) / 2 - 68;
              final points = <Offset>[];
              for (var i = 0; i < _kFleet.length; i++) {
                final ang = i / _kFleet.length * math.pi * 2 - math.pi / 2;
                points.add(Offset(
                  center.dx + radius * math.cos(ang),
                  center.dy + radius * math.sin(ang),
                ));
              }
              final onlineFlags = [
                for (final a in _kFleet) widget.controller.agent(a.id).enabled
              ];
              return Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _ConstellationPainter(
                          tick: _tick,
                          center: center,
                          points: points,
                          online: onlineFlags,
                          colors: [for (final a in _kFleet) a.accent],
                        ),
                      ),
                    ),
                  ),
                  // Central core label.
                  Positioned(
                    left: center.dx - 50,
                    top: center.dy - 22,
                    width: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.tr('AI CORE'),
                            style: Sa.display(size: 13, color: Sa.cyan)),
                        Text(
                            context.tr('{online} ACTIVE', {
                              'online': '$online',
                            }),
                            style: Sa.mono(size: 9, color: Sa.muted)),
                      ],
                    ),
                  ),
                  for (var i = 0; i < _kFleet.length; i++)
                    Positioned(
                      left: points[i].dx - sw / 2,
                      top: points[i].dy - sh / 2,
                      width: sw,
                      height: sh,
                      child: _AgentNode(
                        agent: _kFleet[i],
                        runtime: widget.controller.agent(_kFleet[i].id),
                        onTap: (anchorContext) => _openAgentDetail(
                          anchorContext,
                          _kFleet[i],
                          widget.controller.agent(_kFleet[i].id),
                          widget.controller,
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  void _openAgentDetail(
    BuildContext anchorContext,
    _FleetAgent agent,
    AgentRuntime runtime,
    MonitorController controller,
  ) {
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlayBox == null || anchorBox == null) return;

    final anchorRect = MatrixUtils.transformRect(
      anchorBox.getTransformTo(overlayBox),
      Offset.zero & anchorBox.size,
    );
    const width = 330.0;
    const gap = 12.0;
    const margin = 12.0;
    final overlaySize = overlayBox.size;
    final fitsRight =
        anchorRect.right + gap + width <= overlaySize.width - margin;
    final placement = fitsRight
        ? _AgentPopoverPlacement.right
        : _AgentPopoverPlacement.left;
    final maxLeft = overlaySize.width - width - margin;
    final left = fitsRight
        ? anchorRect.right + gap
        : (anchorRect.left - gap - width).clamp(
            margin,
            maxLeft < margin ? margin : maxLeft,
          );
    final maxTop = overlaySize.height - margin - 280;
    final top = (anchorRect.top - 10).clamp(
      margin,
      maxTop < margin ? margin : maxTop,
    );

    OverlayEntry? entry;
    void close() {
      entry?.remove();
      entry = null;
    }

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: close,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left.toDouble(),
            top: top.toDouble(),
            width: width,
            child: _AgentDetailPopover(
              agent: agent,
              runtime: runtime,
              controller: controller,
              placement: placement,
              onClose: close,
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry!);
  }
}

enum _AgentPopoverPlacement { left, right }

class _AgentDetailPopover extends StatefulWidget {
  final _FleetAgent agent;
  final AgentRuntime runtime;
  final MonitorController controller;
  final _AgentPopoverPlacement placement;
  final VoidCallback onClose;

  const _AgentDetailPopover({
    required this.agent,
    required this.runtime,
    required this.controller,
    required this.placement,
    required this.onClose,
  });

  @override
  State<_AgentDetailPopover> createState() => _AgentDetailPopoverState();
}

class _AgentDetailPopoverState extends State<_AgentDetailPopover> {
  Map<String, dynamic>? _latestLog;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.controller.fetchLatestAgentLog(widget.agent.id).then((log) {
      if (!mounted) return;
      setState(() {
        _latestLog = log;
        _loading = false;
      });
    });
  }

  String get _latestActionSummary {
    if (_loading) return context.tr('Loading…');
    final l = _latestLog;
    if (l == null) return context.tr('No recorded actions yet.');
    final reason = (l['reason'] ?? '').toString().trim();
    final kind = (l['kind'] ?? '').toString().trim();
    final who = (l['supervisorName'] ?? '').toString().trim();
    final alert = (l['alertLabel'] ?? '').toString().trim();
    final parts = <String>[
      if (alert.isNotEmpty) alert,
      if (who.isNotEmpty) '→ $who',
    ];
    if (reason.isNotEmpty) return reason;
    if (parts.isNotEmpty) return parts.join(' ');
    if (kind.isNotEmpty) return kind;
    return context.tr('No recorded actions yet.');
  }

  String get _latestActionAt {
    final at = (_latestLog?['at'] ?? '').toString();
    if (at.isEmpty) return '';
    final d = DateTime.tryParse(at);
    if (d == null) return at;
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final runtime = widget.runtime;
    final online = runtime.enabled;
    final c = agent.accent;
    final placement = widget.placement;
    final latestAt = _latestActionAt;

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: placement == _AgentPopoverPlacement.right ? -7 : null,
            right: placement == _AgentPopoverPlacement.left ? -7 : null,
            top: 28,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Sa.panelSolid,
                  border: Border(
                    left: placement == _AgentPopoverPlacement.right
                        ? BorderSide(color: c.withValues(alpha: 0.58))
                        : BorderSide.none,
                    bottom: placement == _AgentPopoverPlacement.left
                        ? BorderSide(color: c.withValues(alpha: 0.58))
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Sa.panelSolid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withValues(alpha: 0.58)),
              boxShadow: [
                BoxShadow(
                  color: Sa.shadow,
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      c.withValues(alpha: 0.18),
                      c.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(agent.icon, size: 15, color: c),
                                    const SizedBox(width: 7),
                                    Flexible(
                                      child: Text(
                                        context.tr(agent.name),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Sa.heading(size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                _AgentStatusPill(online: online, color: c),
                              ],
                            ),
                          ),
                          _PopoverIconButton(
                            icon: Icons.close,
                            tooltip: context.tr('Close'),
                            color: Sa.textDim,
                            onTap: widget.onClose,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _AgentInfoLine(context.tr('ID'), agent.id),
                      _AgentInfoLine(context.tr('CODE'), agent.code),
                      _AgentInfoLine(context.tr('BRIEF INSIGHT'),
                          context.tr(agent.blurb), maxLines: 3),
                      _AgentInfoLine(
                        context.tr('LATEST ACTION'),
                        _latestActionSummary,
                        maxLines: 3,
                      ),
                      if (latestAt.isNotEmpty)
                        _AgentInfoLine(context.tr('AT'), latestAt),
                      _AgentInfoLine(
                        context.tr('STATUS'),
                        online
                            ? context.tr('Enabled · {headline}', {
                                'headline': '${runtime.headline}',
                              })
                            : context.tr('Disabled'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentStatusPill extends StatelessWidget {
  final bool online;
  final Color color;
  const _AgentStatusPill({required this.online, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = online ? color : Sa.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: c),
          const SizedBox(width: 6),
          Text(
            online ? context.tr('ONLINE') : context.tr('OFFLINE'),
            style: Sa.mono(size: 8.5, color: c, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AgentInfoLine extends StatelessWidget {
  final String label;
  final String value;
  final int maxLines;

  const _AgentInfoLine(this.label, this.value, {this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: Sa.mono(size: 8.5, color: Sa.muted)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: Sa.body(size: 11.5, color: Sa.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopoverIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _PopoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

class _AgentNode extends StatelessWidget {
  final _FleetAgent agent;
  final AgentRuntime runtime;
  final void Function(BuildContext anchorContext) onTap;
  const _AgentNode({
    required this.agent,
    required this.runtime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final online = runtime.enabled;
    final c = online ? agent.accent : Sa.muted;
    return InkWell(
      onTap: () => onTap(context),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.withValues(alpha: 0.3), c.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: c.withValues(alpha: online ? 0.85 : 0.4), width: 1.6),
              boxShadow: online
                  ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 16)]
                  : null,
            ),
            child: Icon(agent.icon, color: c, size: 26),
          ),
          const SizedBox(height: 10),
          Text(context.tr(agent.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Sa.heading(size: 12, color: online ? Sa.text : Sa.muted)),
          const SizedBox(height: 3),
          Text(online ? '${runtime.headline}' : context.tr('OFFLINE'),
              style: Sa.mono(size: 9.5, color: c, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  final ValueNotifier<double> tick;
  final Offset center;
  final List<Offset> points;
  final List<bool> online;
  final List<Color> colors;

  _ConstellationPainter({
    required this.tick,
    required this.center,
    required this.points,
    required this.online,
    required this.colors,
  }) : super(repaint: tick);

  double get t => tick.value;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (points.first - center).distance;

    // Orbit rings.
    for (final rr in [radius, radius * 0.62]) {
      canvas.drawCircle(
        center,
        rr,
        Paint()
          ..color = const Color(0x1A22D3EE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // Rotating tick marks on the outer orbit.
    for (var i = 0; i < 48; i++) {
      final a = i / 48 * math.pi * 2 + t * math.pi * 2 * 0.2;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (radius + 3);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * (radius + (i % 4 == 0 ? 9 : 5));
      canvas.drawLine(p1, p2, Paint()..color = const Color(0x2622D3EE)..strokeWidth = 1);
    }

    // Links + travelling pulses.
    for (var i = 0; i < points.length; i++) {
      final on = online[i];
      final col = colors[i];
      canvas.drawLine(
        center,
        points[i],
        Paint()
          ..color = (on ? col : const Color(0xFF64748B)).withValues(alpha: on ? 0.32 : 0.12)
          ..strokeWidth = on ? 1.4 : 0.8,
      );
      if (on) {
        for (var k = 0; k < 2; k++) {
          final pp = (t * 1.4 + i * 0.17 + k * 0.5) % 1.0;
          final pos = Offset.lerp(center, points[i], pp)!;
          canvas.drawCircle(pos, 2.2, Paint()..color = col);
          canvas.drawCircle(pos, 5.5, Paint()..color = col.withValues(alpha: 0.3));
        }
      }
    }

    // Central core.
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    canvas.drawCircle(center, 30 + pulse * 6,
        Paint()..color = const Color(0x1A22D3EE));
    canvas.drawCircle(center, 22, Paint()..color = const Color(0xFF0A1A33));
    canvas.drawCircle(
      center,
      22,
      Paint()
        ..shader = SweepGradient(
          colors: const [Color(0xFF22D3EE), Color(0xFFA78BFA), Color(0xFF22D3EE)],
          transform: GradientRotation(t * math.pi * 2),
        ).createShader(Rect.fromCircle(center: center, radius: 22))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.online != online || old.points != points;
}

// ════════════════════════════════════════════════════════════════════════════
//  CLOUDFLARE WORKERS — HEARTBEAT GRID
// ════════════════════════════════════════════════════════════════════════════

class WorkersGrid extends StatelessWidget {
  final MonitorController controller;
  const WorkersGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _WorkerCard(
        title: context.tr('AI · SECURITY'),
        worker: 'alert-notifier',
        icon: Icons.psychology_outlined,
        accent: Sa.violet,
        data: controller.aiHealth,
        onlineMaxMin: 3,
        idleMaxMin: 10,
        metrics: [
          ('aiAssignments', context.tr('assigns')),
          ('securityActions', context.tr('security')),
          ('errorCount', context.tr('errors')),
        ],
      ),
      _WorkerCard(
        title: context.tr('NOTIFICATIONS'),
        worker: 'alertsys',
        icon: Icons.notifications_active_outlined,
        accent: Sa.cyan,
        data: controller.notifyHealth,
        onlineMaxMin: 3,
        idleMaxMin: 10,
        metrics: [
          ('alertsPushed', context.tr('alerts')),
          ('notificationsPushed', context.tr('notifs')),
          ('errorCount', context.tr('errors')),
        ],
      ),
      _WorkerCard(
        title: context.tr('BACKUP'),
        worker: 'alertsys-backup',
        icon: Icons.cloud_done_outlined,
        accent: Sa.blue,
        data: controller.backupHealth,
        onlineMaxMin: 26 * 60,
        idleMaxMin: 50 * 60,
        okKey: 'ok',
        metrics: [('bytes', context.tr('snapshot'))],
      ),
      _WorkerCard(
        title: context.tr('MONITOR'),
        worker: 'alertsys-monitor',
        icon: Icons.radar_outlined,
        accent: Sa.green,
        data: controller.monitorHealth,
        onlineMaxMin: 7,
        idleMaxMin: 20,
        stateKey: 'state',
        metrics: [('problems', context.tr('issues'))],
      ),
      _GithubWorkerCard(controller: controller),
    ];

    return HoloPanel(
      accent: Sa.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoloHeader(
            icon: Icons.dns_outlined,
            title: context.tr('CLOUDFLARE EDGE WORKERS'),
            subtitle: context.tr(
              'Five workers at the edge — live cron heartbeat and throughput.',
            ),
            accent: Sa.cyan,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 1100
                ? 3
                : c.maxWidth >= 720
                    ? 2
                    : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: (c.maxWidth - (cols - 1) * 12) / cols,
                    child: card,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  final String title;
  final String worker;
  final IconData icon;
  final Color accent;
  final Map<String, dynamic>? data;
  final int onlineMaxMin;
  final int idleMaxMin;
  final String? okKey;
  final String? stateKey;
  final List<(String, String)> metrics;

  const _WorkerCard({
    required this.title,
    required this.worker,
    required this.icon,
    required this.accent,
    required this.data,
    required this.onlineMaxMin,
    required this.idleMaxMin,
    required this.metrics,
    this.okKey,
    this.stateKey,
  });

  @override
  Widget build(BuildContext context) {
    final at = DateTime.tryParse(
        (data?['at'] ?? data?['finishedAt'] ?? data?['ranAt'] ?? '').toString());
    LiveState state;
    String ageLabel;
    if (data == null || at == null) {
      state = LiveState.unknown;
      ageLabel = '—';
    } else {
      final age = DateTime.now().toUtc().difference(at.toUtc());
      ageLabel = _ago(context, age);
      final mins = age.inMinutes;
      state = mins <= onlineMaxMin
          ? LiveState.online
          : (mins <= idleMaxMin ? LiveState.idle : LiveState.offline);
    }
    // Failure overrides.
    if (okKey != null && data?[okKey] == false) state = LiveState.offline;
    if (stateKey != null && (data?[stateKey] ?? '').toString() == 'degraded') {
      state = LiveState.offline;
    }
    final c = liveColor(state);

    return _InnerCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Sa.heading(size: 13)),
                    Text(worker, style: Sa.mono(size: 8.5, color: Sa.muted)),
                  ],
                ),
              ),
              StatePip(state: state),
            ],
          ),
          const SizedBox(height: 10),
          Heartbeat(state: state),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 12, color: c),
              const SizedBox(width: 5),
              Text(ageLabel, style: Sa.mono(size: 9.5, color: Sa.textDim)),
              const Spacer(),
              for (final (k, label) in metrics)
                if (data?[k] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _metric(label, _fmt(k, data![k])),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(String key, Object? v) {
    if (key == 'bytes' && v is num) {
      return '${(v / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    if (key == 'problems' && v is List) return '${v.length}';
    return '$v';
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Sa.mono(size: 11, color: Sa.text, weight: FontWeight.w700)),
        Text(label.toUpperCase(), style: Sa.mono(size: 7.5, color: Sa.muted)),
      ],
    );
  }

  static String _ago(BuildContext context, Duration d) {
    if (d.inSeconds < 90) {
      return context.tr('{n}s ago', {'n': '${d.inSeconds}'});
    }
    if (d.inMinutes < 90) {
      return context.tr('{n}m ago', {'n': '${d.inMinutes}'});
    }
    if (d.inHours < 48) {
      return context.tr('{n}h ago', {'n': '${d.inHours}'});
    }
    return context.tr('{n}d ago', {'n': '${d.inDays}'});
  }
}

class _GithubWorkerCard extends StatelessWidget {
  final MonitorController controller;
  const _GithubWorkerCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final gh = controller.github;
    final probing = controller.githubProbing;
    final connected = gh?.connected == true;
    final state = gh == null
        ? LiveState.unknown
        : (connected ? LiveState.online : LiveState.offline);
    return _InnerCard(
      accent: Sa.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 17, color: Sa.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('GITHUB PROXY'), style: Sa.heading(size: 13)),
                    Text('alertsys-github', style: Sa.mono(size: 8.5, color: Sa.muted)),
                  ],
                ),
              ),
              if (probing)
                SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Sa.amber))
              else
                StatePip(
                    state: state,
                    labelOverride: connected
                        ? context.tr('CONNECTED')
                        : context.tr('OFFLINE')),
            ],
          ),
          const SizedBox(height: 10),
          Heartbeat(state: connected ? LiveState.online : LiveState.offline),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 12, color: Sa.amber),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  connected
                      ? (gh!.repo.isEmpty
                          ? context.tr('guardian console link')
                          : gh.repo)
                      : context.tr('no cron · pure HTTP proxy'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.mono(size: 9.5, color: Sa.textDim),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InnerCard extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _InnerCard({required this.child, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.55 : 0.92),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: child,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  OPERATIONAL INSIGHT — domain health rings
// ════════════════════════════════════════════════════════════════════════════

class OperationalInsight extends StatelessWidget {
  final MonitorController controller;
  const OperationalInsight({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Fleet.
    final fleetOnline = _kFleet.where((a) => controller.agent(a.id).enabled).length;

    // Hardware.
    final machines = controller.catalog?.machines ?? const [];
    final activeMachines =
        machines.where((m) => m.status == HwMachineStatus.active).length;

    // Workers.
    final workerStates = [
      workerLiveState(controller.aiHealth, onMin: 3, idleMin: 10),
      workerLiveState(controller.notifyHealth, onMin: 3, idleMin: 10),
      workerLiveState(controller.backupHealth,
          onMin: 26 * 60, idleMin: 50 * 60, okKey: 'ok'),
      workerLiveState(controller.monitorHealth,
          onMin: 7, idleMin: 20, stateKey: 'state'),
    ];
    final workersLive = workerStates.where((s) => s != LiveState.offline && s != LiveState.unknown).length;

    // Database.
    final dbReach = controller.dbReachableCount;

    final cards = [
      _InsightCard(
        icon: Icons.hub_outlined,
        label: context.tr('AI FLEET'),
        value: fleetOnline / _kFleet.length,
        center: '$fleetOnline/${_kFleet.length}',
        verdict: fleetOnline == _kFleet.length
            ? context.tr('All units online')
            : context.tr('Some units paused'),
        accent: Sa.violet,
      ),
      _InsightCard(
        icon: Icons.memory_outlined,
        label: context.tr('HARDWARE'),
        value: machines.isEmpty ? 0 : activeMachines / machines.length,
        center: '${machines.isEmpty ? 0 : (activeMachines / machines.length * 100).round()}%',
        verdict: context.tr('{active} of {total} active', {
          'active': '$activeMachines',
          'total': '${machines.length}',
        }),
        accent: Sa.cyan,
      ),
      _InsightCard(
        icon: Icons.dns_outlined,
        label: context.tr('WORKERS'),
        value: workersLive / 4,
        center: '$workersLive/4',
        verdict: workersLive == 4
            ? context.tr('Edge nominal')
            : context.tr('Edge degraded'),
        accent: Sa.green,
      ),
      _InsightCard(
        icon: Icons.schema_outlined,
        label: context.tr('DATABASE'),
        value: dbReach / kDbNodes.length,
        center: '$dbReach/${kDbNodes.length}',
        verdict: context.tr('{count} roots reachable', {
          'count': '$dbReach',
        }),
        accent: Sa.amber,
      ),
    ];

    return HoloPanel(
      accent: Sa.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoloHeader(
            icon: Icons.insights_outlined,
            title: context.tr('OPERATIONAL INSIGHT'),
            subtitle: context.tr(
              'One-glance posture across fleet, hardware, edge and data.',
            ),
            accent: Sa.green,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 760 ? 4 : 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: (c.maxWidth - (cols - 1) * 12) / cols, child: card),
              ],
            );
          }),
        ],
      ),
    );
  }

}

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final String center;
  final String verdict;
  final Color accent;

  const _InsightCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.center,
    required this.verdict,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.5 : 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          RingGauge(value: value, accent: accent, size: 92, center: center),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(label, style: Sa.heading(size: 12, color: accent)),
            ],
          ),
          const SizedBox(height: 3),
          Text(verdict,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Sa.body(size: 10.5, color: Sa.textDim)),
        ],
      ),
    );
  }
}

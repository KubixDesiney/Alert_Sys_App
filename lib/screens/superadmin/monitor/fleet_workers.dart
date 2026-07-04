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
    final ctrl = widget.controller;
    final flags = [for (final a in _kFleet) ctrl.agent(a.id).enabled];
    final online = flags.where((e) => e).length;
    final headlines = [for (final a in _kFleet) ctrl.agent(a.id).headline];
    var totalActions = 0;
    for (final n in headlines) {
      totalActions += n;
    }
    var busiestIdx = -1, busiestVal = -1;
    for (var i = 0; i < _kFleet.length; i++) {
      if (flags[i] && headlines[i] > busiestVal) {
        busiestVal = headlines[i];
        busiestIdx = i;
      }
    }

    return HoloPanel(
      accent: Sa.violet,
      glow: true,
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
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final h = w >= 1180 ? 520.0 : (w >= 760 ? 470.0 : 430.0);
            final sw = w >= 760 ? 152.0 : 122.0;
            const sh = 144.0;
            final center = Offset(w / 2, h / 2);
            final rx = math.min(w * 0.34, 380.0);
            final ry = (h / 2 - sh / 2 - 6).clamp(70.0, h / 2 - 20);
            final points = <Offset>[];
            for (var i = 0; i < _kFleet.length; i++) {
              final ang = i / _kFleet.length * math.pi * 2 - math.pi / 2;
              points.add(Offset(
                center.dx + rx * math.cos(ang),
                center.dy + ry * math.sin(ang),
              ));
            }
            return SizedBox(
              height: h,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _ConstellationPainter(
                          tick: _tick,
                          center: center,
                          rx: rx,
                          ry: ry,
                          points: points,
                          online: flags,
                          colors: [for (final a in _kFleet) a.accent],
                          isDark: Sa.isDark,
                        ),
                      ),
                    ),
                  ),
                  // Central core label, riding the painted nucleus.
                  Positioned(
                    left: center.dx - 70,
                    top: center.dy - 17,
                    width: 140,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.tr('AI CORE'),
                            style: Sa.display(size: 15, color: Sa.cyan)),
                        const SizedBox(height: 2),
                        Text(
                            context.tr('{online} UNITS LIVE', {
                              'online': '$online',
                            }),
                            style: Sa.mono(size: 8.5, color: Sa.muted)),
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
                        runtime: ctrl.agent(_kFleet[i].id),
                        tick: _tick,
                        onTap: (anchorContext) => _openAgentDetail(
                          anchorContext,
                          _kFleet[i],
                          ctrl.agent(_kFleet[i].id),
                          ctrl,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SaStatTile(
                label: context.tr('Online units'),
                value: '$online/${_kFleet.length}',
                icon: Icons.power_settings_new,
                color: online == _kFleet.length ? Sa.green : Sa.amber,
              ),
              SaStatTile(
                label: context.tr('Fleet actions'),
                value: '$totalActions',
                icon: Icons.bolt,
                color: Sa.violet,
              ),
              if (busiestIdx >= 0)
                SaStatTile(
                  label: context.tr('Busiest unit'),
                  value: context.tr(_kFleet[busiestIdx].name),
                  icon: Icons.local_fire_department_outlined,
                  color: Sa.cyan,
                ),
            ],
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

class _AgentNode extends StatefulWidget {
  final _FleetAgent agent;
  final AgentRuntime runtime;
  final ValueNotifier<double> tick;
  final void Function(BuildContext anchorContext) onTap;
  const _AgentNode({
    required this.agent,
    required this.runtime,
    required this.tick,
    required this.onTap,
  });

  @override
  State<_AgentNode> createState() => _AgentNodeState();
}

class _AgentNodeState extends State<_AgentNode> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final online = widget.runtime.enabled;
    final c = online ? agent.accent : Sa.muted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.onTap(context),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _hover ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: SizedBox(
                width: 76,
                height: 76,
                child: AnimatedBuilder(
                  animation: widget.tick,
                  builder: (_, __) => CustomPaint(
                    painter: _AgentOrbPainter(
                      t: widget.tick.value,
                      color: c,
                      online: online,
                      hover: _hover,
                    ),
                    child: Center(child: Icon(agent.icon, color: c, size: 28)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(context.tr(agent.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Sa.heading(size: 12.5, color: online ? Sa.text : Sa.muted)),
            const SizedBox(height: 1),
            Text(agent.code,
                style: Sa.mono(size: 7.5, color: Sa.muted, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (online)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${widget.runtime.headline}',
                      style: Sa.display(size: 15, color: c)),
                  const SizedBox(width: 4),
                  Text(context.tr('RUNS'),
                      style: Sa.mono(size: 8, color: Sa.muted)),
                ],
              )
            else
              Text(context.tr('OFFLINE'),
                  style: Sa.mono(size: 9.5, color: Sa.muted, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Paints one fleet agent's orb: a glowing nucleus with a rotating activity
/// arc + orbiting satellite (online) and a breathing halo. Driven by the
/// shared constellation clock so it never spins up its own controller.
class _AgentOrbPainter extends CustomPainter {
  final double t;
  final Color color;
  final bool online;
  final bool hover;
  _AgentOrbPainter({
    required this.t,
    required this.color,
    required this.online,
    required this.hover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = size.center(Offset.zero);
    const orbR = 27.0;
    final breathe = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 2);

    // Breathing halo (online only).
    if (online) {
      canvas.drawCircle(
        ctr,
        orbR + 6 + breathe * 5,
        Paint()..color = color.withValues(alpha: 0.08 + 0.10 * breathe),
      );
    }
    // Nucleus gradient.
    canvas.drawCircle(
      ctr,
      orbR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.35),
          colors: [
            color.withValues(alpha: online ? 0.36 : 0.10),
            color.withValues(alpha: 0.03),
          ],
        ).createShader(Rect.fromCircle(center: ctr, radius: orbR)),
    );
    // Rim.
    canvas.drawCircle(
      ctr,
      orbR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: online ? (hover ? 1.0 : 0.85) : 0.4),
    );
    if (!online) return;

    // Rotating activity arc + leading satellite.
    final ringRect = Rect.fromCircle(center: ctr, radius: orbR + 4.5);
    final a0 = t * math.pi * 2;
    const span = math.pi * 0.72;
    canvas.drawArc(
      ringRect,
      a0,
      span,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: a0,
          endAngle: a0 + span,
          colors: [color.withValues(alpha: 0), color],
        ).createShader(ringRect),
    );
    final sat =
        ctr + Offset(math.cos(a0 + span), math.sin(a0 + span)) * (orbR + 4.5);
    canvas.drawCircle(sat, 5, Paint()..color = color.withValues(alpha: 0.3));
    canvas.drawCircle(sat, 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AgentOrbPainter old) =>
      old.t != t ||
      old.color != color ||
      old.online != online ||
      old.hover != hover;
}

/// A drifting, twinkling background star.
class _Star {
  final double x, y, r, phase, spd;
  const _Star(this.x, this.y, this.r, this.phase, this.spd);
}

class _ConstellationPainter extends CustomPainter {
  final ValueNotifier<double> tick;
  final Offset center;
  final double rx, ry;
  final List<Offset> points;
  final List<bool> online;
  final List<Color> colors;
  final bool isDark;

  _ConstellationPainter({
    required this.tick,
    required this.center,
    required this.rx,
    required this.ry,
    required this.points,
    required this.online,
    required this.colors,
    required this.isDark,
  }) : super(repaint: tick);

  double get t => tick.value;

  static final List<_Star> _stars = List.generate(64, (i) {
    final r = math.Random(i * 977 + 13);
    return _Star(
      r.nextDouble(),
      r.nextDouble(),
      0.4 + r.nextDouble() * 1.5,
      r.nextDouble() * math.pi * 2,
      0.4 + r.nextDouble() * 1.2,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cyan = Sa.cyan;
    final violet = Sa.violet;
    final dim = isDark ? 1.0 : 0.7;

    // ── twinkling starfield
    for (final s in _stars) {
      final tw = 0.45 + 0.55 * math.sin(t * math.pi * 2 * s.spd + s.phase);
      final col = s.x > 0.5 ? violet : cyan;
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.r,
        Paint()..color = col.withValues(alpha: (0.04 + 0.13 * tw) * dim),
      );
    }

    // ── elliptical orbit rings
    for (final f in const [1.0, 0.62]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: center, width: 2 * rx * f, height: 2 * ry * f),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = cyan.withValues(alpha: 0.10 * dim),
      );
    }
    // Rotating tick marks riding the outer ellipse.
    for (var i = 0; i < 72; i++) {
      final a = i / 72 * math.pi * 2 + t * math.pi * 2 * 0.12;
      final ca = math.cos(a), sa = math.sin(a);
      final p1 = center + Offset(ca * rx, sa * ry);
      final ext = i % 6 == 0 ? 0.06 : 0.03;
      final p2 = center + Offset(ca * rx * (1 + ext), sa * ry * (1 + ext));
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = cyan.withValues(alpha: (i % 6 == 0 ? 0.22 : 0.11) * dim)
          ..strokeWidth = 1,
      );
    }

    // ── slow radar sweep
    final sweepA = t * math.pi * 2;
    final sweepRect =
        Rect.fromCenter(center: center, width: 2 * rx, height: 2 * ry);
    final sweepPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(sweepRect, sweepA, 0.55, false)
      ..close();
    canvas.drawPath(
      sweepPath,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepA,
          endAngle: sweepA + 0.55,
          colors: [cyan.withValues(alpha: 0.16 * dim), cyan.withValues(alpha: 0)],
        ).createShader(sweepRect),
    );

    // ── constellation polygon between live nodes
    final onPts = [
      for (var i = 0; i < points.length; i++)
        if (online[i]) points[i]
    ];
    if (onPts.length >= 2) {
      final poly = Path()..moveTo(onPts.first.dx, onPts.first.dy);
      for (var i = 1; i < onPts.length; i++) {
        poly.lineTo(onPts[i].dx, onPts[i].dy);
      }
      poly.close();
      canvas.drawPath(
        poly,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = violet.withValues(alpha: 0.16 * dim),
      );
    }

    // ── links + travelling thought-pulses
    for (var i = 0; i < points.length; i++) {
      final on = online[i];
      final col = colors[i];
      canvas.drawLine(
        center,
        points[i],
        Paint()
          ..color = (on ? col : Sa.muted).withValues(alpha: (on ? 0.30 : 0.10) * dim)
          ..strokeWidth = on ? 1.5 : 0.8,
      );
      if (on) {
        for (var k = 0; k < 2; k++) {
          final pp = (t * 1.4 + i * 0.16 + k * 0.5) % 1.0;
          final pos = Offset.lerp(center, points[i], pp)!;
          canvas.drawCircle(pos, 6, Paint()..color = col.withValues(alpha: 0.26 * dim));
          canvas.drawCircle(pos, 2.4, Paint()..color = col.withValues(alpha: 0.95 * dim));
        }
      }
    }

    // ── central core
    final breathe = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    canvas.drawCircle(center, 44 + breathe * 8,
        Paint()..color = cyan.withValues(alpha: 0.06 * dim));
    canvas.drawCircle(
      center,
      38,
      Paint()
        ..color = (isDark ? const Color(0xFF071226) : const Color(0xFFEFF5FF))
            .withValues(alpha: 0.86),
    );
    final coreRect = Rect.fromCircle(center: center, radius: 38);
    canvas.drawCircle(
      center,
      38,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = SweepGradient(
          colors: [cyan, violet, cyan],
          transform: GradientRotation(t * math.pi * 2),
        ).createShader(coreRect),
    );
    canvas.drawCircle(center, 20 + breathe * 3,
        Paint()..color = cyan.withValues(alpha: 0.10 * dim));
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.online != online || old.points != points || old.isDark != isDark;
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

    // Database.
    final dbReach = controller.dbReachableCount;

    // Sessions.
    final online = controller.onlineSessions;
    final accounts = controller.sessions.length;

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
        icon: Icons.schema_outlined,
        label: context.tr('DATABASE'),
        value: dbReach / kDbNodes.length,
        center: '$dbReach/${kDbNodes.length}',
        verdict: context.tr('{count} roots reachable', {
          'count': '$dbReach',
        }),
        accent: Sa.amber,
      ),
      _InsightCard(
        icon: Icons.groups_2_outlined,
        label: context.tr('SESSIONS'),
        value: accounts == 0 ? 0 : online / accounts,
        center: '$online',
        verdict: context.tr('{count} accounts total', {
          'count': '$accounts',
        }),
        accent: Sa.green,
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
              'One-glance posture across fleet, hardware, data and people.',
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

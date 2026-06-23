import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../superadmin_theme.dart';
import 'monitor_data.dart';
import 'monitor_kit.dart';

/// Live holographic conception of the Realtime Database: every root node, the
/// relationships between them, and a per-node reachability + shallow count
/// probed straight from the REST API.
class DatabaseHologram extends StatefulWidget {
  final MonitorController controller;
  const DatabaseHologram({super.key, required this.controller});

  @override
  State<DatabaseHologram> createState() => _DatabaseHologramState();
}

class _DatabaseHologramState extends State<DatabaseHologram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final ValueNotifier<double> _tick = ValueNotifier(0);
  int _lastMs = 0;

  static Map<String, Color> get _domainColors => {
        'operations': Sa.cyan,
        'people': Sa.blue,
        'ai': Sa.violet,
        'coordination': Sa.green,
        'platform': Sa.amber,
      };

  static const _mapColors = {
    'operations': Color(0xFF22D3EE),
    'people': Color(0xFF3B82F6),
    'ai': Color(0xFFA78BFA),
    'coordination': Color(0xFF34D399),
    'platform': Color(0xFFFBBF24),
  };

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 26))
      ..addListener(() {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastMs < 40) return;
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
    final c = widget.controller;
    return HoloPanel(
      accent: Sa.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoloHeader(
            icon: Icons.schema_outlined,
            title: context.tr('DATABASE CONCEPTION'),
            subtitle: context.tr(
              'Live Realtime Database topology, relationships and per-node health.',
            ),
            accent: Sa.green,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.dbProbedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                        context.tr('probed {time}', {
                          'time': shortAgo(context, c.dbProbedAt),
                        }),
                        style: Sa.mono(size: 9, color: Sa.muted)),
                  ),
                SaButton(
                  label: context.tr('RESCAN'),
                  icon: Icons.radar,
                  outlined: true,
                  busy: c.dbProbing,
                  onPressed: c.dbProbing ? null : () => c.probeDatabase(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final d in _domainColors.entries)
                GlowChip(
                    label: context.tr(d.key.toUpperCase()), color: d.value),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, cns) {
            final height = math.max(400.0, cns.maxWidth * 0.46);
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
                    painter: _TopologyPainter(
                      tick: _tick,
                      counts: Map.of(c.dbCounts),
                      reachable: Map.of(c.dbReachable),
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
              for (final n in kDbNodes)
                SaStatTile(
                  label: n.label,
                  value: c.dbCounts[n.path] == null ? '—' : '${c.dbCounts[n.path]}',
                  icon: c.dbReachable[n.path] == true
                      ? Icons.check_circle_outline
                      : Icons.help_outline,
                  color: c.dbReachable[n.path] == true
                      ? (_domainColors[n.domain] ?? Sa.cyan)
                      : Sa.muted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopologyPainter extends CustomPainter {
  final ValueNotifier<double> tick;
  final Map<String, int?> counts;
  final Map<String, bool> reachable;
  final Map<String, Color> domainColors;

  _TopologyPainter({
    required this.tick,
    required this.counts,
    required this.reachable,
    required this.domainColors,
  }) : super(repaint: tick);

  final Map<String, TextPainter> _tp = {};
  double get t => tick.value;

  @override
  void paint(Canvas canvas, Size size) {
    final pos = <String, Offset>{};
    for (final n in kDbNodes) {
      final wob = math.sin(t * math.pi * 2 + n.x * 13 + n.y * 7) * 3;
      pos[n.path] = Offset(
        n.x * (size.width - 150) + 75,
        n.y * (size.height - 90) + 45 + wob,
      );
    }

    for (final (a, b) in kDbEdges) {
      final pa = pos[a], pb = pos[b];
      if (pa == null || pb == null) continue;
      canvas.drawLine(pa, pb, Paint()..color = const Color(0x2238BDF8)..strokeWidth = 1);
      final pulseT = (t * 2 + (a.hashCode % 17) / 17) % 1.0;
      final pp = Offset.lerp(pa, pb, pulseT)!;
      canvas.drawCircle(pp, 2, Paint()..color = const Color(0x8C22D3EE));
    }

    for (final n in kDbNodes) {
      final p = pos[n.path]!;
      final color = domainColors[n.domain] ?? const Color(0xFF22D3EE);
      final ok = reachable[n.path] == true;
      final count = counts[n.path];
      final glow = 0.5 + 0.5 * math.sin(t * math.pi * 4 + n.x * 20);

      canvas.drawCircle(p, 21 + glow * 2,
          Paint()..color = color.withValues(alpha: ok ? 0.12 : 0.04));
      canvas.drawCircle(p, 14, Paint()..color = const Color(0xFF081127));
      canvas.drawCircle(
        p,
        14,
        Paint()
          ..color = ok ? color : const Color(0x9964748B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(p + const Offset(10, -10), 3.2,
          Paint()..color = ok ? const Color(0xFF34D399) : const Color(0xFF64748B));

      _text(canvas, n.label, p + const Offset(0, 23), color, 10, FontWeight.w600);
      if (count != null) {
        _text(canvas, '$count', p, const Color(0xFFE2E8F0), 9, FontWeight.w700);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset center, Color color, double size,
      FontWeight weight) {
    final key = '$s|$color|$size';
    final tp = _tp.putIfAbsent(key, () {
      return TextPainter(
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
    });
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TopologyPainter old) =>
      old.counts != counts || old.reachable != reachable;
}

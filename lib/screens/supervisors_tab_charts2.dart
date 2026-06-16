part of 'supervisors_tab.dart';

class _SupervisorRailTile extends StatefulWidget {
  final UserModel supervisor;
  final bool selected;
  final int solved;
  final int claimed;
  final List<int> spark;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SupervisorRailTile({
    required this.supervisor,
    required this.selected,
    required this.solved,
    required this.claimed,
    required this.spark,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_SupervisorRailTile> createState() => _SupervisorRailTileState();
}

class _SupervisorRailTileState extends State<_SupervisorRailTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final status = widget.supervisor.isActive ? t.green : t.red;
    final borderColor = widget.selected ? t.navy : t.border;
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _hovering ? -3 : 0, 0),
      padding: const EdgeInsets.all(1.3),
      decoration: BoxDecoration(
        gradient: widget.selected
            ? LinearGradient(
                colors: [
                  t.navy.withValues(alpha: 0.72),
                  t.green.withValues(alpha: 0.48),
                  t.blue.withValues(alpha: 0.42),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: widget.selected ? 1.4 : 1,
        ),
        boxShadow: widget.selected || _hovering
            ? [
                BoxShadow(
                  color: t.navy.withValues(alpha: 0.14),
                  blurRadius: _hovering ? 18 : 14,
                  offset: Offset(0, _hovering ? 10 : 7),
                ),
              ]
            : null,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.selected
              ? t.navyLt.withValues(alpha: t.isDark ? 0.82 : 0.96)
              : t.card,
          borderRadius: BorderRadius.circular(13),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: widget.selected ? t.navy : t.scaffold,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: widget.selected ? t.navy : t.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _initials(widget.supervisor),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: widget.selected ? Colors.white : t.navy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.supervisor.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            _LivePulseDot(
                              color: status,
                              pulse: widget.supervisor.isActive,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                widget.supervisor.usine.isEmpty
                                    ? 'Unassigned'
                                    : widget.supervisor.usine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: t.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.drag_indicator, size: 18, color: t.muted),
                ],
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _AnimatedMiniChip(
                    icon: Icons.check_circle_outline,
                    value: widget.solved,
                    suffix: ' fixed',
                    color: t.green,
                  ),
                  _AnimatedMiniChip(
                    icon: Icons.timer_outlined,
                    value: widget.claimed,
                    suffix: ' live',
                    color: t.blue,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 30,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => CustomPaint(
                    painter: _MiniSparklinePainter(
                      data: widget.spark,
                      color: widget.selected ? t.navy : t.green,
                      gridColor: t.border,
                      progress: progress,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.supervisor.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: t.muted),
                    ),
                  ),
                  Tooltip(
                    message: 'Modify Supervisor',
                    child: InkWell(
                      onTap: widget.onEdit,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(Icons.edit, size: 16, color: t.navy),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Delete Supervisor',
                    child: InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: t.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Draggable<UserModel>(
        data: widget.supervisor,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.navy,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: t.navy.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.supervisor.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: tile,
        ),
      ),
    );
  }
}

class _AnimatedMiniChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final String suffix;
  final Color color;
  const _AnimatedMiniChip({
    required this.icon,
    required this.value,
    required this.suffix,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return _MiniChip(icon, '$animated$suffix', color);
      },
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _LivePulseDot({required this.color, this.pulse = true});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LivePulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = widget.pulse ? _controller.value : 0.0;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 12 + v * 3,
                height: 12 + v * 3,
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: widget.pulse ? 0.18 : 0.10,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(
                        alpha: widget.pulse ? 0.48 : 0.22,
                      ),
                      blurRadius: widget.pulse ? 5 + v * 5 : 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniSparklinePainter extends CustomPainter {
  final List<int> data;
  final Color color;
  final Color gridColor;
  final double progress;

  const _MiniSparklinePainter({
    required this.data,
    required this.color,
    required this.gridColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.isEmpty) return;
    final maxVal = math.max(1, data.reduce(math.max)).toDouble();
    final visibleCount = (data.length * progress).clamp(
      1.0,
      data.length.toDouble(),
    );
    final n = visibleCount.ceil();
    final stepX = data.length > 1 ? size.width / (data.length - 1) : size.width;

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.34)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 2),
      Offset(size.width, size.height - 2),
      grid,
    );

    double yFor(int i) {
      final pad = size.height * 0.18;
      final usable = size.height - pad * 2;
      return pad + usable - (data[i] / maxVal) * usable;
    }

    final path = Path();
    final fill = Path();
    for (var i = 0; i < n; i++) {
      final x = i * stepX;
      final y = yFor(i);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevY = yFor(i - 1);
        final cp1 = Offset(prevX + stepX / 2, prevY);
        final cp2 = Offset(x - stepX / 2, y);
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
        fill.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
      }
    }
    final lastX = (n - 1) * stepX;
    fill.lineTo(lastX, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.progress != progress;
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _GlassChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: icon == Icons.circle ? 8 : 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
    if (!pulse) return pill;
    return _PulsingRing(color: color, child: pill);
  }
}

class _AnimatedRankPill extends StatelessWidget {
  final int rank;
  final Color color;
  const _AnimatedRankPill({required this.rank, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, _) {
        return Transform.translate(
          offset: Offset((1 - value) * 14, 0),
          child: Transform.scale(
            scale: 0.92 + value * 0.08,
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: _StatusPill(
                color: color,
                label: 'Rank #$rank',
                icon: Icons.leaderboard_outlined,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final Widget child;
  final Color color;
  const _PulsingRing({required this.child, required this.color});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        return Container(
          padding: EdgeInsets.all(2 + v * 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.12 + v * 0.22),
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

class _FloatingHeroSignal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _FloatingHeroSignal({required this.child, required this.delay});

  @override
  State<_FloatingHeroSignal> createState() => _FloatingHeroSignalState();
}

class _FloatingHeroSignalState extends State<_FloatingHeroSignal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final wave = math.sin(_controller.value * math.pi);
        return Opacity(
          opacity: (0.88 + wave * 0.12).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -wave * 3.5),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _HeroSignal extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _HeroSignal({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: 142,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.card.withValues(alpha: t.isDark ? 0.62 : 0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: t.text,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: t.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandMetric extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  const _CommandMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  State<_CommandMetric> createState() => _CommandMetricState();
}

class _CommandMetricState extends State<_CommandMetric> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovering ? -3 : 0, 0),
        height: 84,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.tone.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: widget.tone.withValues(alpha: _hovering ? 0.16 : 0.06),
              blurRadius: _hovering ? 18 : 10,
              offset: Offset(0, _hovering ? 9 : 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 16, color: widget.tone),
                const Spacer(),
                Container(
                  width: 22,
                  height: 3,
                  decoration: BoxDecoration(
                    color: widget.tone.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              widget.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: t.text,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  const _SectionShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
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
                  color: t.navyLt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: t.navy),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 10, color: t.muted),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _RangeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      width: 142,
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / 2;
          final selectedIndex = value == '30days' ? 1 : 0;
          Widget item(String id, String label) {
            final selected = value == id;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(id),
                borderRadius: BorderRadius.circular(9),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : t.muted,
                    ),
                    child: Text(label),
                  ),
                ),
              ),
            );
          }

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: itemW * selectedIndex,
                top: 0,
                bottom: 0,
                width: itemW,
                child: Container(
                  decoration: BoxDecoration(
                    color: t.navy,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: t.navy.withValues(alpha: 0.24),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(children: [item('7days', '7D'), item('30days', '30D')]),
            ],
          );
        },
      ),
    );
  }
}

class _CommandGridPainter extends CustomPainter {
  final Color color;
  const _CommandGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * 0.35, size.height),
        paint,
      );
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CommandGridPainter oldDelegate) =>
      oldDelegate.color != color;
}


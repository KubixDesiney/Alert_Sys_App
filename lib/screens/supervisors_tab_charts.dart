part of 'supervisors_tab.dart';

class _LeaderboardEntry {
  final UserModel supervisor;
  final int score;
  const _LeaderboardEntry({required this.supervisor, required this.score});
}

class _FactoryWorkloadSegment {
  final UserModel supervisor;
  final int count;
  const _FactoryWorkloadSegment({
    required this.supervisor,
    required this.count,
  });
}

class _DashboardShimmerSkeleton extends StatelessWidget {
  const _DashboardShimmerSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Shimmer.fromColors(
      baseColor: t.border.withValues(alpha: 0.38),
      highlightColor: t.card.withValues(alpha: 0.92),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(
          5,
          (index) => Container(
            width: 320,
            height: 210,
            decoration: BoxDecoration(
              color: t.border,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _StaggeredEntrance({required this.child, required this.delay});

  @override
  State<_StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<_StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _offset = Tween(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
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
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _WeeklyResolutionHeatmap extends StatelessWidget {
  final List<int> values;
  const _WeeklyResolutionHeatmap({required this.values});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final maxY = math.max(1, values.fold<int>(0, math.max)).toDouble();
    final now = DateTime.now();
    final days = List.generate(
      values.length,
      (i) => now.subtract(Duration(days: values.length - 1 - i)),
    );

    return SizedBox(
      height: 198,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY + 1,
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: t.border.withValues(alpha: 0.52), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: math.max(1, maxY / 3),
                getTitlesWidget: (value, _) => Text(
                  value.toInt().toString(),
                  style: TextStyle(fontSize: 9, color: t.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _weekdayShort(days[index].weekday),
                      style: TextStyle(
                        fontSize: 10,
                        color: t.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => t.text,
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${rod.toY.toInt()} resolved',
                TextStyle(
                  color: t.card,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          barGroups: List.generate(values.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  width: 18,
                  borderRadius: BorderRadius.circular(7),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [t.green.withValues(alpha: 0.55), t.green],
                  ),
                ),
              ],
            );
          }),
        ),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class _AlertTypeDonut extends StatelessWidget {
  final Map<String, int> distribution;
  const _AlertTypeDonut({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final entries = distribution.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) {
      return _EmptyChartState(label: 'No alert type activity');
    }
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return Row(
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 42,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                  sections: List.generate(entries.length, (i) {
                    final visible = ((progress * entries.length) - i).clamp(
                      0.0,
                      1.0,
                    );
                    final entry = entries[i];
                    final color = typeMeta(entry.key, t).color;
                    return PieChartSectionData(
                      value: entry.value * visible,
                      title: visible > 0.85
                          ? '${(entry.value / total * 100).round()}%'
                          : '',
                      color: color,
                      radius: 34 + visible * 12,
                      titleStyle: TextStyle(
                        color: t.card,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.map((entry) {
                  final color = typeMeta(entry.key, t).color;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.28),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            typeMeta(entry.key, t).label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          entry.value.toString(),
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SupervisorLeaderboardChart extends StatelessWidget {
  final List<_LeaderboardEntry> entries;
  const _SupervisorLeaderboardChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (entries.isEmpty) {
      return _EmptyChartState(label: 'No supervisor scores yet');
    }
    final maxScore = math.max(1, entries.map((e) => e.score).reduce(math.max));
    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final color = _rankTone(t, index);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 520 + index * 90),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      entry.supervisor.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Stack(
                        children: [
                          Container(height: 12, color: t.scaffold),
                          FractionallySizedBox(
                            widthFactor: (entry.score / maxScore) * progress,
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color.withValues(alpha: 0.55),
                                    color,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(entry.score * progress).round()}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}

class _LiveActivityPulseChart extends StatelessWidget {
  final List<double> samples;
  final double progress;
  const _LiveActivityPulseChart({
    required this.samples,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return SizedBox(
      height: 156,
      child: CustomPaint(
        painter: _HeartbeatPainter(
          samples: samples,
          progress: progress,
          color: t.green,
          gridColor: t.border,
          labelColor: t.muted,
          backgroundColor: t.scaffold,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _FactoryWorkloadChart extends StatelessWidget {
  final Map<String, List<_FactoryWorkloadSegment>> workload;
  const _FactoryWorkloadChart({required this.workload});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final entries = workload.entries
        .where((entry) => entry.value.isNotEmpty)
        .take(5)
        .toList();
    if (entries.isEmpty) {
      return _EmptyChartState(label: 'No factory workload yet');
    }
    final maxTotal = entries
        .map((e) => e.value.fold<int>(0, (sum, segment) => sum + segment.count))
        .fold<int>(1, math.max);
    final palette = [t.green, t.blue, t.orange, t.purple, t.yellow];

    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final total = entry.value.fold<int>(
          0,
          (sum, segment) => sum + segment.count,
        );
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 620 + index * 80),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 86,
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: t.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 16,
                        child: Row(
                          children: [
                            for (var i = 0; i < entry.value.length; i++)
                              Flexible(
                                flex: math.max(
                                  1,
                                  (entry.value[i].count * progress).round(),
                                ),
                                child: Container(
                                  color: palette[i % palette.length],
                                ),
                              ),
                            if (total < maxTotal)
                              Flexible(
                                flex: math.max(1, maxTotal - total),
                                child: Container(color: t.scaffold),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    total.toString(),
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}

class _SupervisorTypeDonutChart extends StatefulWidget {
  final Map<String, _TypeStats> stats;
  const _SupervisorTypeDonutChart({required this.stats});

  @override
  State<_SupervisorTypeDonutChart> createState() =>
      _SupervisorTypeDonutChartState();
}

class _SupervisorTypeDonutChartState extends State<_SupervisorTypeDonutChart> {
  int _activeIndex = -1;

  List<_TypeDonutDatum> get _data {
    final items =
        widget.stats.entries
            .where(
              (entry) =>
                  entry.value.validated > 0 || entry.value.notValidated > 0,
            )
            .map(
              (entry) => _TypeDonutDatum(
                type: entry.key,
                validated: entry.value.validated,
                notValidated: entry.value.notValidated,
                color: _typeColor(entry.key),
              ),
            )
            .toList()
          ..sort((a, b) {
            final byValidated = b.validated.compareTo(a.validated);
            if (byValidated != 0) {
              return byValidated;
            }
            return _typeLabel(a.type).compareTo(_typeLabel(b.type));
          });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final data = _data;
    final totalValidated = data.fold<int>(
      0,
      (sum, item) => sum + item.validated,
    );
    if (data.isEmpty || totalValidated == 0) {
      return const _EmptyChartState(label: 'No validated alerts yet');
    }

    final selected = (_activeIndex >= 0 && _activeIndex < data.length)
        ? data[_activeIndex]
        : data.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final chart = TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: compact ? 220 : 250,
                  height: compact ? 220 : 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        selected.color.withValues(alpha: 0.22),
                        selected.color.withValues(alpha: 0.02),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: compact ? 220 : 250,
                  height: compact ? 220 : 250,
                  child: PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: 4,
                      centerSpaceRadius: compact ? 54 : 62,
                      pieTouchData: PieTouchData(
                        enabled: true,
                        touchCallback: (event, response) {
                          final touched =
                              response?.touchedSection?.touchedSectionIndex ??
                              -1;
                          if (!event.isInterestedForInteractions ||
                              touched < 0) {
                            if (_activeIndex != -1) {
                              setState(() => _activeIndex = -1);
                            }
                            return;
                          }
                          if (_activeIndex != touched) {
                            setState(() => _activeIndex = touched);
                          }
                        },
                      ),
                      sections: List.generate(data.length, (index) {
                        final item = data[index];
                        final selectedSlice = index == _activeIndex;
                        return PieChartSectionData(
                          color: item.color,
                          value: math.max(
                            (item.validated * progress).toDouble(),
                            0.001,
                          ),
                          title: '',
                          radius: selectedSlice ? 78 : 68,
                          borderSide: BorderSide(
                            color: t.card.withValues(
                              alpha: selectedSlice ? 0.96 : 0.74,
                            ),
                            width: selectedSlice ? 4 : 2,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Container(
                    width: compact ? 108 : 122,
                    height: compact ? 108 : 122,
                    decoration: BoxDecoration(
                      color: t.card.withValues(alpha: t.isDark ? 0.92 : 0.96),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected.color.withValues(alpha: 0.24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: t.isDark ? 0.18 : 0.05,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Column(
                        key: ValueKey(selected.type),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${selected.validated}',
                            style: TextStyle(
                              fontSize: compact ? 28 : 32,
                              fontWeight: FontWeight.w900,
                              color: selected.color,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              _typeLabel(selected.type),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: t.text,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'validated',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: t.muted,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected.color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected.color.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: selected.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: selected.color.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeLabel(selected.type),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${selected.validated} validated • ${selected.share(totalValidated)}% of validated alerts',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected.color,
                          ),
                        ),
                        if (selected.notValidated > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${selected.notValidated} open / returned in this class',
                            style: TextStyle(fontSize: 11, color: t.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(data.length, (index) {
              final item = data[index];
              final highlighted =
                  index == _activeIndex || (_activeIndex < 0 && index == 0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _activeIndex = index),
                  onExit: (_) => setState(() => _activeIndex = -1),
                  child: GestureDetector(
                    onTap: () => setState(() => _activeIndex = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: highlighted
                            ? item.color.withValues(alpha: 0.08)
                            : t.scaffold.withValues(alpha: t.isDark ? 0.45 : 1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: highlighted
                              ? item.color.withValues(alpha: 0.36)
                              : t.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: item.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _typeLabel(item.type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: t.text,
                              ),
                            ),
                          ),
                          Text(
                            '${item.validated}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: item.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );

        if (compact) {
          return Column(children: [chart, const SizedBox(height: 16), details]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Center(child: chart)),
            const SizedBox(width: 20),
            SizedBox(width: 280, child: details),
          ],
        );
      },
    );
  }
}

class _TypeDonutDatum {
  final String type;
  final int validated;
  final int notValidated;
  final Color color;

  const _TypeDonutDatum({
    required this.type,
    required this.validated,
    required this.notValidated,
    required this.color,
  });

  int share(int totalValidated) {
    if (totalValidated == 0) {
      return 0;
    }
    return ((validated / totalValidated) * 100).round();
  }
}

class _EmptyChartState extends StatelessWidget {
  final String label;
  const _EmptyChartState({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      height: 136,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: t.muted)),
    );
  }
}

Color _rankTone(AppTheme t, int index) {
  if (index == 0) return t.yellow;
  if (index == 1) return t.blue;
  if (index == 2) return t.orange;
  return t.green;
}

String _weekdayShort(int weekday) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return labels[(weekday - 1).clamp(0, 6)];
}

class _HeartbeatPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color backgroundColor;

  const _HeartbeatPainter({
    required this.samples,
    required this.progress,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final rect = Offset.zero & size;
    final bg = Paint()..color = backgroundColor.withValues(alpha: 0.42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      bg,
    );

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = math.max(1.0, samples.reduce(math.max));
    final step = size.width / math.max(1, samples.length - 1);
    final shift = progress * step;
    Offset point(int i) {
      final x = i * step - shift;
      final y =
          size.height -
          14 -
          (samples[i] / maxVal) * math.max(1, size.height - 28);
      return Offset(x, y);
    }

    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final p = point(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final prev = point(i - 1);
        final cx = (prev.dx + p.dx) / 2;
        path.cubicTo(cx, prev.dy, cx, p.dy, p.dx, p.dy);
      }
    }

    final glow = Paint()
      ..color = color.withValues(alpha: 0.42)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glow);

    final line = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);

    final current = point(samples.length - 1);
    final dotGlow = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawCircle(current, 9, dotGlow);
    canvas.drawCircle(current, 3.5, Paint()..color = color);

    final label = TextPainter(
      text: TextSpan(
        text: 'LIVE',
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(10, 10));
  }

  @override
  bool shouldRepaint(covariant _HeartbeatPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.backgroundColor != backgroundColor;
}


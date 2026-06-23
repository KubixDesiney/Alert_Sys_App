part of 'supervisors_tab.dart';

class _PerformanceSubTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final List<AlertModel> alerts;
  const _PerformanceSubTab({required this.supervisors, required this.alerts});
  @override
  State<_PerformanceSubTab> createState() => _PerformanceSubTabState();
}

class _PerformanceSubTabState extends State<_PerformanceSubTab> {
  UserModel? _selected;
  String _chartRange = '7days';

  List<AlertModel> get _supAlerts => _selected == null
      ? []
      : widget.alerts
            .where(
              (a) =>
                  a.superviseurId == _selected!.id ||
                  a.assistantId == _selected!.id,
            )
            .toList();

  List<AlertModel> get _solved =>
      _supAlerts.where((a) => a.status == 'validee').toList();

  int? get _avgMin {
    final w = _solved.where((a) => a.elapsedTime != null).toList();
    if (w.isEmpty) return null;
    return w.fold(0, (s, a) => s + (a.elapsedTime ?? 0)) ~/ w.length;
  }

  List<_ChartPoint> _buildChartPoints() {
    final days = _chartRange == '7days' ? 7 : 30;
    final now = DateTime.now();
    return List.generate(days, (i) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: days - 1 - i));
      final next = day.add(const Duration(days: 1));
      final count = _solved
          .where((a) => a.timestamp.isAfter(day) && a.timestamp.isBefore(next))
          .length;
      return _ChartPoint(day: day, value: count.toDouble());
    });
  }

  Map<String, int> _factoryDist() {
    final m = <String, int>{};
    for (var a in _solved) {
      m[a.usine] = (m[a.usine] ?? 0) + 1;
    }
    return m;
  }

  Map<String, _TypeStats> _typeStats() {
    final types = [
      'qualite',
      'maintenance',
      'defaut_produit',
      'manque_ressource',
    ];
    return {
      for (var t in types)
        t: _TypeStats(
          validated: _supAlerts
              .where((a) => a.type == t && a.status == 'validee')
              .length,
          notValidated: _supAlerts
              .where((a) => a.type == t && a.status != 'validee')
              .length,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supervisor Performance',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: t.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Analyse alert validations per supervisor',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.card,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select a supervisor',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: t.scaffold,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<UserModel>(
                      isExpanded: true,
                      value: _selected,
                      hint: Text(
                        'Choose a supervisor…',
                        style: TextStyle(color: t.muted, fontSize: 14),
                      ),
                      dropdownColor: t.card,
                      items: widget.supervisors
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 16,
                                    color: t.navy,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    s.fullName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: t.text,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: t.navyLt,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      s.usine,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: t.navy,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selected = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_selected == null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 60),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: t.scaffold,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person_search, size: 32, color: t.muted),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Choose a supervisor',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a supervisor above to see their statistics',
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                ],
              ),
            ),
          if (_selected != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: t.card,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fixed Alerts',
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '${_solved.length}',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: t.navy,
                                height: 1,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: t.blueLt,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_circle_outline,
                                color: t.blue,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                        Divider(height: 20, color: t.border),
                        Text(
                          'Distribution by Factory:',
                          style: TextStyle(fontSize: 11, color: t.muted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _factoryDist().entries
                              .map(
                                (e) => Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    7,
                                    14,
                                    7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.navyLt,
                                    border: Border.all(
                                      color: t.navy.withOpacity(0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bar_chart,
                                        size: 14,
                                        color: t.navy,
                                      ),
                                      const SizedBox(width: 6),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.key,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: t.navy,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${e.value}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: t.navy,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: t.card,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Average Time',
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _avgMin == null ? '—' : _fmtMin(_avgMin!),
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: t.green,
                                  height: 1,
                                ),
                              ),
                            ),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: t.greenLt,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.timer,
                                color: t.green,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children:
                  [
                    'qualite',
                    'maintenance',
                    'defaut_produit',
                    'manque_ressource',
                  ].map((tp) {
                    final ts = _typeStats()[tp]!;
                    final clr = _typeColor(tp);
                    final tot = ts.validated + ts.notValidated;
                    final pct = tot == 0
                        ? 0
                        : (ts.validated / tot * 100).round();
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: t.card,
                            border: Border.all(
                              color: clr.withValues(alpha: .25),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x06000000),
                                blurRadius: 3,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _typeLabel(tp),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: clr,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: clr.withOpacity(.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_circle_outline,
                                      color: clr,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$tot',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: clr,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _PerfStatRow(
                                label: context.tr('Validated'),
                                value: ts.validated,
                                color: _green,
                              ),
                              const SizedBox(height: 3),
                              _PerfStatRow(
                                label: context.tr('Not validated'),
                                value: ts.notValidated,
                                color: _orange,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$pct% validated',
                                style: TextStyle(fontSize: 10, color: t.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.card,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 15, color: t.navy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Evolution of Validations',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.text,
                              ),
                            ),
                            Text(
                              'Number of alerts validated per day',
                              style: TextStyle(fontSize: 11, color: t.muted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: t.scaffold,
                          border: Border.all(color: t.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _chartRange,
                            style: TextStyle(fontSize: 12, color: t.text),
                            dropdownColor: t.card,
                            items: [
                              DropdownMenuItem(
                                value: '7days',
                                child: Text(
                                  'Last 7 days',
                                  style: TextStyle(color: t.text),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '30days',
                                child: Text(
                                  'Last 30 days',
                                  style: TextStyle(color: t.text),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() => _chartRange = v!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 200,
                    child: _LineChart(points: _buildChartPoints()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 28, height: 2, color: t.navy),
                      const SizedBox(width: 6),
                      Icon(Icons.circle, size: 7, color: t.navy),
                      const SizedBox(width: 6),
                      Text(
                        'Validations',
                        style: TextStyle(fontSize: 11, color: t.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: t.green),
                const SizedBox(width: 6),
                Text(
                  'Validated Alerts (${_solved.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Detailed list of alerts validated by ${_selected!.fullName}',
              style: TextStyle(fontSize: 12, color: t.muted),
            ),
            const SizedBox(height: 12),
            if (_solved.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 30),
                alignment: Alignment.center,
                child: Text(
                  'No validated alerts yet',
                  style: TextStyle(fontSize: 14, color: t.muted),
                ),
              )
            else
              ..._solved.map((a) => _ValidatedAlertRow(alert: a)),
          ],
        ],
      ),
    );
  }
}

class _PerfStatRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _PerfStatRow({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
      ),
      Text(
        '$value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ],
  );
}

class _TypeStats {
  final int validated, notValidated;
  const _TypeStats({required this.validated, required this.notValidated});
}

class _ValidatedAlertRow extends StatelessWidget {
  final AlertModel alert;
  const _ValidatedAlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final clr = _typeColor(alert.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: clr.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _typeLabel(alert.type),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: clr,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${alert.usine} — C${alert.convoyeur} — P${alert.poste}',
              style: TextStyle(fontSize: 12, color: t.text),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: t.greenLt,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'Validated',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: t.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPoint {
  final DateTime day;
  final double value;
  const _ChartPoint({required this.day, required this.value});
}

class _LineChart extends StatefulWidget {
  final List<_ChartPoint> points;
  final double progress;
  final Color? color;
  final Color? fillColor;
  final Color? gridColor;
  final Color? labelColor;
  const _LineChart({
    required this.points,
    this.progress = 1,
    this.color,
    this.fillColor,
    this.gridColor,
    this.labelColor,
  });

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? _selectedIndex;

  int? _nearestPoint(Size size, Offset localPosition) {
    if (widget.points.isEmpty) return null;
    const leftPad = 36.0;
    const rightPad = 16.0;
    final chartW = size.width - leftPad - rightPad;
    final n = widget.points.length;
    if (chartW <= 0) return null;
    final ratio = ((localPosition.dx - leftPad) / chartW).clamp(0.0, 1.0);
    return (ratio * (n - 1)).round().clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            setState(() {
              _selectedIndex = _nearestPoint(
                Size(width, constraints.maxHeight),
                details.localPosition,
              );
            });
          },
          child: Stack(
            children: [
              CustomPaint(
                painter: _LineChartPainter(
                  points: widget.points,
                  progress: widget.progress,
                  color: widget.color ?? t.navy,
                  fillColor: widget.fillColor ?? t.navy,
                  gridColor: widget.gridColor ?? t.border,
                  labelColor: widget.labelColor ?? t.muted,
                  dotBorderColor: t.card,
                  selectedIndex: _selectedIndex,
                ),
                size: const Size(double.infinity, 200),
              ),
              if (_selectedIndex != null && widget.points.isNotEmpty)
                _LineChartTooltip(
                  point: widget.points[_selectedIndex!],
                  left: _tooltipLeft(
                    width,
                    _selectedIndex!,
                    widget.points.length,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _tooltipLeft(double width, int index, int count) {
    const leftPad = 36.0;
    const rightPad = 16.0;
    final chartW = width - leftPad - rightPad;
    final x =
        leftPad + (count == 1 ? chartW / 2 : index / (count - 1) * chartW);
    return (x - 58).clamp(6.0, math.max(6.0, width - 116));
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final double progress;
  final Color color;
  final Color fillColor;
  final Color gridColor;
  final Color labelColor;
  final Color dotBorderColor;
  final int? selectedIndex;
  _LineChartPainter({
    required this.points,
    required this.progress,
    required this.color,
    required this.fillColor,
    required this.gridColor,
    required this.labelColor,
    required this.dotBorderColor,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 36.0;
    const rightPad = 16.0;
    const topPad = 10.0;
    const bottomPad = 28.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    final maxVal = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final yMax = maxVal < 1 ? 1.0 : maxVal;
    final n = points.length;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: (yMax * i / 4).toStringAsFixed(0),
          style: TextStyle(fontSize: 9, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(0, y - textPainter.height / 2));
    }

    Offset pos(int i) {
      final x = leftPad + (n == 1 ? chartW / 2 : i / (n - 1) * chartW);
      final y = topPad + chartH * (1 - ((points[i].value * progress) / yMax));
      return Offset(x, y);
    }

    final fillPath = Path();
    fillPath.moveTo(leftPad, topPad + chartH);
    for (int i = 0; i < n; i++) {
      fillPath.lineTo(pos(i).dx, pos(i).dy);
    }
    fillPath.lineTo(pos(n - 1).dx, topPad + chartH);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            fillColor.withValues(alpha: .18),
            color.withValues(alpha: .015),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH)),
    );

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final linePath = Path()..moveTo(pos(0).dx, pos(0).dy);
    for (int i = 1; i < n; i++) {
      final p0 = pos(i - 1);
      final p1 = pos(i);
      final cx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = color;
    final dotBorder = Paint()
      ..color = dotBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final dateSteps = n <= 10 ? 1 : (n / 7).ceil();

    for (int i = 0; i < n; i++) {
      final p = pos(i);
      final isSelected = i == selectedIndex;
      final glowPaint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.42 : 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 9 : 5);
      canvas.drawCircle(p, isSelected ? 9 : 6, glowPaint);
      canvas.drawCircle(p, isSelected ? 5 : 4, dotPaint);
      canvas.drawCircle(p, 4, dotBorder);

      if (i % dateSteps == 0 || i == n - 1) {
        final d = points[i].day;
        final label = '${d.day} ${_monthAbbr(d.month)}';
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(fontSize: 9, color: labelColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p.dx - tp.width / 2, topPad + chartH + 6));
      }
    }
  }

  String _monthAbbr(int m) {
    const abbr = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return abbr[m];
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.points != points ||
      old.progress != progress ||
      old.color != color ||
      old.fillColor != fillColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor ||
      old.dotBorderColor != dotBorderColor ||
      old.selectedIndex != selectedIndex;
}

class _LineChartTooltip extends StatelessWidget {
  final _ChartPoint point;
  final double left;
  const _LineChartTooltip({required this.point, required this.left});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Positioned(
      top: 8,
      left: left,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: 0.86 + value * 0.14,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: Container(
          width: 116,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.text,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: t.text.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${point.value.toInt()} resolved',
                style: TextStyle(
                  color: t.card,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${point.day.day}/${point.day.month}/${point.day.year}',
                style: TextStyle(
                  color: t.card.withValues(alpha: 0.74),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


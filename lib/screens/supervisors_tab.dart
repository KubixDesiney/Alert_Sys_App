part of 'admin_dashboard_screen.dart';

// SUPERVISORS TAB (unchanged from original – keep as is)
// ═══════════════════════════════════════════════════════════════════════════
class _SupervisorsTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final List<AlertModel> alerts;
  final VoidCallback onAdd;
  final void Function(UserModel) onDelete;
  final Future<void> Function() onRefresh;
  const _SupervisorsTab({
    required this.supervisors,
    required this.alerts,
    required this.onAdd,
    required this.onDelete,
    required this.onRefresh,
  });
  @override
  State<_SupervisorsTab> createState() => _SupervisorsTabState();
}

class _SupervisorsTabState extends State<_SupervisorsTab>
    with SingleTickerProviderStateMixin {
  late TabController _sub;
  final TextEditingController _searchCtrl = TextEditingController();
  final HierarchyService _hierarchyService = HierarchyService();
  StreamSubscription<List<Factory>>? _factoriesSubscription;
  List<Factory> _factories = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 3, vsync: this);
    _loadFactories();
  }

  void _loadFactories() {
    _factoriesSubscription?.cancel();
    _factoriesSubscription =
        _hierarchyService.getFactories().listen((factories) {
      if (!mounted) return;
      setState(() {
        _factories = factories;
      });
    });
  }

  @override
  void dispose() {
    _factoriesSubscription?.cancel();
    _searchCtrl.dispose();
    _sub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final filteredSupervisors = q.isEmpty
        ? widget.supervisors
        : widget.supervisors
            .where((s) => s.fullName.toLowerCase().contains(q))
            .toList();

    return Column(children: [
      Container(
        color: _white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              _SubPill(
                  label: 'Management',
                  icon: Icons.people,
                  index: 0,
                  ctrl: _sub),
              _SubPill(
                  label: 'Performance',
                  icon: Icons.show_chart,
                  index: 1,
                  ctrl: _sub),
              _SubPill(
                  label: 'Assignments',
                  icon: Icons.bar_chart,
                  index: 2,
                  ctrl: _sub),
            ],
          ),
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _sub,
          children: [
            _ManagementSubTab(
              supervisors: filteredSupervisors,
              totalSupervisors: widget.supervisors.length,
              alerts: widget.alerts,
              factories: _factories,
              onAdd: widget.onAdd,
              onDelete: widget.onDelete,
              onRefresh: widget.onRefresh,
              searchCtrl: _searchCtrl,
              searchQuery: _searchQuery,
              onSearchChanged: (v) => setState(() => _searchQuery = v),
            ),
            _PerformanceSubTab(
              supervisors: widget.supervisors,
              alerts: widget.alerts,
            ),
            _AssignmentsSubTab(
              supervisors: widget.supervisors,
            ),
          ],
        ),
      ),
    ]);
  }
}

class _SubPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final int index;
  final TabController ctrl;
  const _SubPill(
      {required this.label,
      required this.icon,
      required this.index,
      required this.ctrl});
  @override
  State<_SubPill> createState() => _SubPillState();
}

class _SubPillState extends State<_SubPill> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.ctrl.index == widget.index;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.ctrl.animateTo(widget.index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              color: sel ? _white : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
              boxShadow: sel
                  ? [
                      const BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 4,
                          offset: Offset(0, 1))
                    ]
                  : []),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icon, size: 14, color: sel ? _navy : _muted),
            const SizedBox(width: 5),
            Text(widget.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? _navy : _muted)),
          ]),
        ),
      ),
    );
  }
}

class _ManagementSubTab extends StatelessWidget {
  final List<UserModel> supervisors;
  final int totalSupervisors;
  final List<AlertModel> alerts;
  final List<Factory> factories;
  final VoidCallback onAdd;
  final void Function(UserModel) onDelete;
  final Future<void> Function() onRefresh;
  final TextEditingController searchCtrl;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  const _ManagementSubTab(
      {required this.supervisors,
      required this.alerts,
      required this.factories,
      required this.onAdd,
      required this.onDelete,
      required this.onRefresh,
      required this.totalSupervisors,
      required this.searchCtrl,
      required this.searchQuery,
      required this.onSearchChanged});

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            _Chip('${supervisors.where((s) => s.isActive).length} Active',
                _green),
            const SizedBox(width: 8),
            _Chip(
                '${supervisors.where((s) => !s.isActive).length} Absent', _red),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Add Supervisor',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: _white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9))),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search supervisor by name...',
              prefixIcon: const Icon(Icons.search, color: _muted),
              suffixIcon: searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18, color: _muted),
                      onPressed: () {
                        searchCtrl.clear();
                        onSearchChanged('');
                      },
                    ),
              filled: true,
              fillColor: _white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _navy, width: 1.4),
              ),
            ),
          ),
        ),
        Expanded(
          child: supervisors.isEmpty
              ? (totalSupervisors == 0
                  ? _emptySups()
                  : Center(
                      child: Text(
                        'No supervisors match "$searchQuery"',
                        style: const TextStyle(fontSize: 13, color: _muted),
                      ),
                    ))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: supervisors.length,
                  itemBuilder: (_, i) => _SupervisorCard(
                      supervisor: supervisors[i],
                      alerts: alerts,
                      factories: factories,
                      onRefresh: onRefresh,
                      onDelete: () => onDelete(supervisors[i]))),
        ),
      ]);
}

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
      : widget.alerts.where((a) => a.superviseurId == _selected!.id).toList();

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
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
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
      'manque_ressource'
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
        )
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Supervisor Performance',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: _text)),
        const SizedBox(height: 2),
        const Text('Analyse alert validations per supervisor',
            style: TextStyle(fontSize: 13, color: _muted)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select a supervisor',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _text)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: _bg,
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(9)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<UserModel>(
                  isExpanded: true,
                  value: _selected,
                  hint: const Text('Choose a supervisor…',
                      style: TextStyle(color: _muted, fontSize: 14)),
                  dropdownColor: _white,
                  items: widget.supervisors
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Row(children: [
                              const Icon(Icons.person_outline,
                                  size: 16, color: _navy),
                              const SizedBox(width: 8),
                              Text(s.fullName,
                                  style: const TextStyle(
                                      fontSize: 14, color: _text)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: _navyLt,
                                    borderRadius: BorderRadius.circular(99)),
                                child: Text(s.usine,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: _navy,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selected = v),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (_selected == null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            alignment: Alignment.center,
            child: Column(children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                child: const Icon(Icons.person_search,
                    size: 32, color: _muted),
              ),
              const SizedBox(height: 14),
              const Text('Choose a supervisor',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _muted)),
              const SizedBox(height: 4),
              const Text('Select a supervisor above to see their statistics',
                  style: TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
        if (_selected != null) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: _white,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 4,
                          offset: Offset(0, 2))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fixed Alerts',
                          style: TextStyle(fontSize: 12, color: _muted)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('${_solved.length}',
                            style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                                height: 1)),
                        const Spacer(),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                              color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                          child: const Icon(Icons.check_circle_outline,
                              color: _blue, size: 24),
                        ),
                      ]),
                      const Divider(height: 20, color: _border),
                      const Text('Distribution by Factory:',
                          style: TextStyle(fontSize: 11, color: _muted)),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _factoryDist()
                              .entries
                              .map((e) => Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 7, 14, 7),
                                    decoration: BoxDecoration(
                                        color: _navyLt,
                                        border: Border.all(
                                            color: const Color(0xFFBFDBFE)),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.bar_chart,
                                              size: 14, color: _navy),
                                          const SizedBox(width: 6),
                                          Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(e.key,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: _navy,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                Text('${e.value}',
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: _navy)),
                                              ]),
                                        ]),
                                  ))
                              .toList()),
                    ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: _white,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 4,
                          offset: Offset(0, 2))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Average Time',
                          style: TextStyle(fontSize: 12, color: _muted)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: Text(_avgMin == null ? '—' : _fmtMin(_avgMin!),
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: _green,
                                  height: 1)),
                        ),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                              color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                          child: const Icon(Icons.timer,
                              color: _green, size: 24),
                        ),
                      ]),
                    ]),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(
              children: [
            'qualite',
            'maintenance',
            'defaut_produit',
            'manque_ressource'
          ].map((t) {
            final ts = _typeStats()[t]!;
            final clr = _typeColor(t);
            final tot = ts.validated + ts.notValidated;
            final pct = tot == 0 ? 0 : (ts.validated / tot * 100).round();
            return Expanded(
                child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _white,
                    border: Border.all(color: clr.withOpacity(.25)),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 3,
                          offset: Offset(0, 2))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(_typeLabel(t),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: clr))),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: clr.withOpacity(.1),
                              shape: BoxShape.circle),
                          child: Icon(Icons.check_circle_outline,
                              color: clr, size: 16),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text('$tot',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: clr,
                              height: 1)),
                      const SizedBox(height: 10),
                      _PerfStatRow(
                          label: 'Validated',
                          value: ts.validated,
                          color: _green),
                      const SizedBox(height: 3),
                      _PerfStatRow(
                          label: 'Not validated',
                          value: ts.notValidated,
                          color: _orange),
                      const SizedBox(height: 6),
                      Text('$pct% validated',
                          style: const TextStyle(fontSize: 10, color: _muted)),
                    ]),
              ),
            ));
          }).toList()),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: _white,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 4,
                      offset: Offset(0, 2))
                ]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.calendar_today,
                    size: 15, color: _navy),
                const SizedBox(width: 8),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Evolution of Validations',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _text)),
                      Text('Number of alerts validated per day',
                          style: TextStyle(fontSize: 11, color: _muted)),
                    ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                      color: _bg,
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _chartRange,
                      style: const TextStyle(fontSize: 12, color: _text),
                      dropdownColor: _white,
                      items: const [
                        DropdownMenuItem(
                            value: '7days', child: Text('Last 7 days')),
                        DropdownMenuItem(
                            value: '30days', child: Text('Last 30 days')),
                      ],
                      onChanged: (v) => setState(() => _chartRange = v!),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: _LineChart(points: _buildChartPoints()),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 28, height: 2, color: _navy),
                const SizedBox(width: 6),
                const Icon(Icons.circle, size: 7, color: _navy),
                const SizedBox(width: 6),
                const Text('Validations',
                    style: TextStyle(fontSize: 11, color: _muted)),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Icon(Icons.check_circle_outline, size: 16, color: _green),
            const SizedBox(width: 6),
            Text('Validated Alerts (${_solved.length})',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _text)),
          ]),
          const SizedBox(height: 2),
          Text('Detailed list of alerts validated by ${_selected!.fullName}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 12),
          if (_solved.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              alignment: Alignment.center,
              child: const Text('No validated alerts yet',
                  style: TextStyle(fontSize: 14, color: _muted)),
            )
          else
            ..._solved.map((a) => _ValidatedAlertRow(alert: a)),
        ],
      ]),
    );
  }
}

class _PerfStatRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _PerfStatRow(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 10, color: _muted))),
        Text('$value',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]);
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
    final clr = _typeColor(alert.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: _white,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: clr.withOpacity(.1),
              borderRadius: BorderRadius.circular(6)),
          child: Text(_typeLabel(alert.type),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: clr)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
                '${alert.usine} — C${alert.convoyeur} — P${alert.poste}',
                style: const TextStyle(fontSize: 12, color: _text))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: _greenLt, borderRadius: BorderRadius.circular(99)),
          child: Text('Validated',
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: _green)),
        ),
      ]),
    );
  }
}

class _ChartPoint {
  final DateTime day;
  final double value;
  const _ChartPoint({required this.day, required this.value});
}

class _LineChart extends StatelessWidget {
  final List<_ChartPoint> points;
  const _LineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(points: points),
      size: const Size(double.infinity, 200),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  _LineChartPainter({required this.points});

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
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(
          Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);
      final textPainter = TextPainter(
        text: TextSpan(
            text: (yMax * i / 4).toStringAsFixed(0),
            style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(0, y - textPainter.height / 2));
    }

    Offset pos(int i) {
      final x = leftPad + (n == 1 ? chartW / 2 : i / (n - 1) * chartW);
      final y = topPad + chartH * (1 - (points[i].value / yMax));
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
            colors: [_navy.withOpacity(.15), _navy.withOpacity(.01)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH)));

    final linePaint = Paint()
      ..color = _navy
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

    final dotPaint = Paint()..color = _navy;
    final dotBorder = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final dateSteps = n <= 10 ? 1 : (n / 7).ceil();

    for (int i = 0; i < n; i++) {
      final p = pos(i);
      canvas.drawCircle(p, 4, dotPaint);
      canvas.drawCircle(p, 4, dotBorder);

      if (i % dateSteps == 0 || i == n - 1) {
        final d = points[i].day;
        final label = '${d.day} ${_monthAbbr(d.month)}';
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
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
      'Dec'
    ];
    return abbr[m];
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.points != points;
}

class _AssignmentsSubTab extends StatefulWidget {
  final List<UserModel> supervisors;
  const _AssignmentsSubTab({required this.supervisors});

  @override
  State<_AssignmentsSubTab> createState() => _AssignmentsSubTabState();
}

class _AssignmentsSubTabState extends State<_AssignmentsSubTab> {
  List<Factory> _factories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFactories();
  }

  Future<void> _loadFactories() async {
    final hierarchyService = HierarchyService();
    hierarchyService.getFactories().listen((factories) {
      if (mounted) {
        setState(() {
          _factories = factories;
          _loading = false;
        });
      }
    });
  }

  Map<String, List<UserModel>> _groupByFactory() {
    final map = <String, List<UserModel>>{};
    for (var factory in _factories) {
      map[factory.name] =
          widget.supervisors.where((s) => s.usine == factory.name).toList();
    }
    return map;
  }

  String? _getLocationForFactory(String factoryName) {
    for (var factory in _factories) {
      if (factory.name == factoryName) return factory.location;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = _groupByFactory();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Supervisor Assignments',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: _text)),
        const SizedBox(height: 2),
        const Text('Assign supervisors to plants for alert monitoring',
            style: TextStyle(fontSize: 13, color: _muted)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: _white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 4,
                    offset: Offset(0, 2))
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.bar_chart, size: 16, color: _navy),
              const SizedBox(width: 8),
              const Text('Assignments by Plant',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: _text)),
            ]),
            const SizedBox(height: 4),
            const Text('See supervisors assigned to each plant',
                style: TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 16),
            ...grouped.entries.map((e) {
              final factoryName = e.key;
              final sups = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _bg,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(factoryName,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _text)),
                              const SizedBox(height: 2),
                              Text(_getLocationForFactory(factoryName) ?? '',
                                  style: const TextStyle(
                                      fontSize: 12, color: _muted)),
                            ])),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                              color: sups.isEmpty
                                  ? const Color(0xFFF1F5F9)
                                  : _navyLt,
                              borderRadius: BorderRadius.circular(99)),
                          child: Text(
                              sups.isEmpty
                                  ? '0 supervisors'
                                  : '${sups.length} supervisor${sups.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: sups.isEmpty ? _muted : _navy)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      if (sups.isEmpty)
                        const Text('No supervisor assigned',
                            style: TextStyle(
                                fontSize: 12,
                                color: _muted,
                                fontStyle: FontStyle.italic))
                      else
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                sups.map((s) => _SupChip(sup: s)).toList()),
                    ]),
              );
            }),
          ]),
        ),
      ]),
    );
  }
}

class _SupChip extends StatelessWidget {
  final UserModel sup;
  const _SupChip({required this.sup});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: _navy, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.person_outline, size: 13, color: _white),
          const SizedBox(width: 6),
          Text(sup.fullName,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _white)),
        ]),
      );
}

Widget _emptySups() => Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
          Icon(Icons.people_outline, size: 52, color: _muted),
          SizedBox(height: 12),
          Text('No supervisors yet',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: _muted)),
          SizedBox(height: 6),
          Text('Tap "Add Supervisor" to create an account',
              style: TextStyle(fontSize: 12, color: _muted)),
        ]));

class _SupervisorCard extends StatefulWidget {
  final UserModel supervisor;
  final List<AlertModel> alerts;
  final List<Factory> factories;
  final Future<void> Function() onRefresh;
  final VoidCallback onDelete;
  const _SupervisorCard(
      {required this.supervisor,
      required this.alerts,
      required this.factories,
      required this.onDelete,
      required this.onRefresh});
  @override
  State<_SupervisorCard> createState() => _SupervisorCardState();
}

class _SupervisorCardState extends State<_SupervisorCard> {
  bool _expanded = false;
  Future<void> _showModifyDialog(BuildContext context) async {
    final sup = widget.supervisor;
    final firstCtrl = TextEditingController(text: sup.firstName);
    final lastCtrl = TextEditingController(text: sup.lastName);
    final phoneCtrl = TextEditingController(text: sup.phone);
    final usineChoices = <String>{
      sup.usine,
      ...widget.factories.map((f) => f.name),
    }.toList()
      ..sort();
    var selectedUsine = sup.usine;
    var saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Modify Supervisor'),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetLabel('First Name'),
                      TextField(
                        controller: firstCtrl,
                        decoration: const InputDecoration(
                          hintText: 'First name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SheetLabel('Last Name'),
                      TextField(
                        controller: lastCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Last name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SheetLabel('Phone'),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'Phone number',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SheetLabel('Assigned Plant'),
                      DropdownButtonFormField<String>(
                        value: selectedUsine,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: usineChoices
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                setDialogState(() => selectedUsine = v);
                              },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final first = firstCtrl.text.trim();
                          final last = lastCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          if (first.isEmpty || last.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('First and last name are required')),
                            );
                            return;
                          }
                          setDialogState(() => saving = true);
                          try {
                            await AuthService().updateSupervisorProfile(
                              userId: sup.id,
                              firstName: first,
                              lastName: last,
                              phone: phone,
                              usine: selectedUsine,
                            );
                            await widget.onRefresh();
                            if (!mounted) return;
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Supervisor updated successfully'),
                                backgroundColor: _green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Update failed: $e')),
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    firstCtrl.dispose();
    lastCtrl.dispose();
    phoneCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sup = widget.supervisor;
    final solved = widget.alerts
        .where((a) => a.status == 'validee' && a.superviseurId == sup.id)
        .toList();
    final inProg = widget.alerts
        .where((a) => a.status == 'en_cours' && a.superviseurId == sup.id)
        .length;
    final withTime = solved.where((a) => a.elapsedTime != null).toList();
    final avgMin = withTime.isEmpty
        ? null
        : withTime.fold(0, (s, a) => s + (a.elapsedTime ?? 0)) ~/
            withTime.length;
    final sc = sup.isActive ? _green : _red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))
          ]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: _navyLt, borderRadius: BorderRadius.circular(12)),
                  child: const Center(
                      child: Icon(Icons.engineering, size: 24))),
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: sc,
                          shape: BoxShape.circle,
                          border: Border.all(color: _white, width: 2)))),
            ]),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(sup.fullName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _navy))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: sc.withOpacity(.1),
                          border: Border.all(color: sc),
                          borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: sc, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text(sup.isActive ? 'Active' : 'Absent',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: sc)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(sup.email,
                      style: const TextStyle(fontSize: 11, color: _muted)),
                  Row(children: [
                    const Icon(Icons.phone, size: 12, color: _muted),
                    const SizedBox(width: 3),
                    Text(sup.phone.isEmpty ? 'No phone' : sup.phone,
                        style: const TextStyle(fontSize: 11, color: _muted)),
                    const SizedBox(width: 10),
                    const Icon(Icons.factory, size: 12, color: _muted),
                    const SizedBox(width: 3),
                    Text(sup.usine,
                        style: const TextStyle(fontSize: 11, color: _muted)),
                  ]),
                  if (sup.hiredDate != null)
                    Row(children: [
                      const Icon(Icons.calendar_today,
                          size: 12, color: _muted),
                      const SizedBox(width: 3),
                      Text('Hired: ${_fmtDate(sup.hiredDate!)}',
                          style: const TextStyle(fontSize: 11, color: _muted)),
                    ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _MiniChip(Icons.check_circle_outline,
                        '${solved.length} fixed', _green),
                    _MiniChip(
                        Icons.timer, '$inProg in progress', _blue),
                    if (avgMin != null)
                      _MiniChip(Icons.av_timer,
                          'Avg ${_fmtMin(avgMin)}', _orange),
                  ]),
                ])),
            Column(children: [
              if (solved.isNotEmpty)
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: _navy),
                ),
              IconButton(
                onPressed: () => _showModifyDialog(context),
                icon: const Icon(Icons.edit, color: _navy, size: 20),
                tooltip: 'Modify Supervisor',
              ),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline, color: _red, size: 20),
              ),
            ]),
          ]),
        ),
        if (_expanded && solved.isNotEmpty) ...[
          Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FIXED CASES HISTORY',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                ...solved.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: _typeColor(a.type),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('${_typeLabel(a.type)} — ${a.description}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _navy),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                  '${a.usine} · Line ${a.convoyeur} · Post ${a.poste}',
                                  style: const TextStyle(
                                      fontSize: 10, color: _muted)),
                            ])),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(
                              a.elapsedTime != null
                                  ? _fmtMin(a.elapsedTime!)
                                  : '-',
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _green)),
                        ),
                      ]),
                    )),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withOpacity(.1),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniChip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(.08),
            border: Border.all(color: color.withOpacity(.4)),
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class _SheetField extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final TextInputType keyboard;
  const _SheetField(this.label, this.ctrl, this.hint,
      {this.obscure = false, this.keyboard = TextInputType.text});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetLabel(label),
          TextField(
            controller: ctrl,
            obscureText: obscure,
            keyboardType: keyboard,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _muted),
              filled: true,
              fillColor: _bg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _navy, width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),
        ],
      );
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _muted,
                letterSpacing: 1.3)),
      );
}

part of 'shifts_tab.dart';

class _LiveShiftPanel extends StatefulWidget {
  final ShiftModel shift;
  final VoidCallback onConfettiNeeded;
  final VoidCallback onViewLogs;
  const _LiveShiftPanel({
    required this.shift,
    required this.onConfettiNeeded,
    required this.onViewLogs,
  });

  @override
  State<_LiveShiftPanel> createState() => _LiveShiftPanelState();
}

class _LiveShiftPanelState extends State<_LiveShiftPanel> {
  bool _requestingHandover = false;
  bool _exportingPdf = false;
  String? _handoverSummary;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final now = DateTime.now();
    final activeNow = widget.shift.containsTime(now);
    final remaining = activeNow
        ? widget.shift.minutesRemaining(now) ?? 0
        : _minutesUntilStart(now);
    final progress = activeNow ? widget.shift.progress(now) : 0.0;
    final timeLabel = activeNow ? 'Time remaining' : 'Starts in';

    if (activeNow && remaining <= 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onConfettiNeeded(),
      );
    }

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer, color: t.navy, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                timeLabel,
                style: TextStyle(
                  color: t.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _CountdownText(minutes: remaining, color: t.navy),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: t.scaffold,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress > 0.85 ? t.orange : t.navy,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ShiftPresenceGrid(shift: widget.shift, isActiveNow: activeNow),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _ViewLogsButton(onTap: widget.onViewLogs)),
            const SizedBox(width: 8),
            Expanded(
              child: _ShiftPdfExportButton(
                busy: _exportingPdf,
                onTap: _generatePdfReport,
              ),
            ),
          ],
        ),
        if (activeNow && remaining <= 30 && remaining > 0) ...[
          const SizedBox(height: 10),
          _HandoverBanner(
            minutes: remaining,
            requesting: _requestingHandover,
            summary: _handoverSummary,
            onGenerate: _generateHandover,
          ),
        ],
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 680;
            final card = SizedBox(
              width: stacked ? double.infinity : 220,
              height: stacked ? 170 : 140,
              child: ShiftCard(shift: widget.shift, isActiveNow: activeNow),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [card, const SizedBox(height: 14), details],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                card,
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _generateHandover() async {
    setState(() => _requestingHandover = true);
    final result = await ServiceLocator.instance.shiftService
        .requestHandoverSummary(widget.shift);
    if (!mounted) return;
    setState(() {
      _requestingHandover = false;
      _handoverSummary =
          result ??
          'Could not reach the AI handover service. Please try again later.';
    });
  }

  int _minutesUntilStart(DateTime now) {
    final current = now.hour * 60 + now.minute;
    var delta = widget.shift.startMinutes - current;
    if (delta < 0) delta += 1440;
    return delta;
  }

  Future<void> _generatePdfReport() async {
    final factories =
        widget.shift.supervisors
            .map((s) => s.factory.trim())
            .where((f) => f.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final settings = await showDialog<_ShiftExportSettings>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ShiftExportDialog(shift: widget.shift, factories: factories),
    );
    if (settings == null) return;
    if (settings.actionKinds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Select at least one action type'),
          backgroundColor: context.appTheme.orange,
        ),
      );
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      const allKinds = _ShiftExportDialogState.actionKinds;
      await ShiftPdfService.exportAndShare(
        shift: widget.shift,
        day: settings.day,
        options: ShiftReportExportOptions(
          reportName: settings.reportName,
          factory: settings.factory,
          actionKinds: settings.actionKinds.length == allKinds.length
              ? const <String>{}
              : settings.actionKinds,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to generate report: ${UserFriendlyError.message(e)}',
          ),
          backgroundColor: context.appTheme.red,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _exportingPdf = false);
  }
}

// ────────────────────────── PDF EXPORT BUTTON ───────────────────────────────
class _ShiftPdfExportButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ShiftPdfExportButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: busy
          ? SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.navy),
            )
          : const _PdfIcon(),
      label: Text(
        busy ? 'Generating PDF…' : 'Export PDF report',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: t.navy,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: t.scaffold,
        side: BorderSide(color: t.navy.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 32),
      ),
    );
  }
}

class _ShiftExportDialog extends StatefulWidget {
  final ShiftModel shift;
  final List<String> factories;

  const _ShiftExportDialog({required this.shift, required this.factories});

  @override
  State<_ShiftExportDialog> createState() => _ShiftExportDialogState();
}

class _ShiftExportDialogState extends State<_ShiftExportDialog> {
  static const actionKinds = <String>{
    'created',
    'claimed',
    'resolved',
    'ai_assigned',
    'escalated',
    'handover',
  };

  late final TextEditingController _nameController;
  late DateTime _day;
  late String _factory;
  late Set<String> _selectedKinds;
  bool _nameTouched = false;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now();
    _factory = 'all';
    _selectedKinds = Set<String>.from(actionKinds);
    _nameController = TextEditingController(text: _autoName());
    _nameController.addListener(() {
      if (!_nameTouched && _nameController.text != _autoName()) {
        _nameTouched = true;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _autoName() {
    final factory = _factory == 'all' ? 'All factories' : _factory;
    return 'SIA Shift Commander Report - ${widget.shift.name} - $factory - ${_date(_day)}';
  }

  void _refreshName() {
    if (_nameTouched) return;
    _nameController.text = _autoName();
    _nameController.selection = TextSelection.collapsed(
      offset: _nameController.text.length,
    );
  }

  String _label(String kind) {
    switch (kind) {
      case 'created':
        return 'Created';
      case 'claimed':
        return 'Claimed';
      case 'resolved':
        return 'Resolved';
      case 'ai_assigned':
        return 'AI Assignments';
      case 'escalated':
        return 'Escalations';
      case 'handover':
        return 'Handovers';
      default:
        return kind;
    }
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'ai_assigned':
        return Icons.auto_awesome_rounded;
      case 'handover':
        return Icons.swap_horiz_rounded;
      case 'resolved':
        return Icons.check_circle_outline_rounded;
      case 'escalated':
        return Icons.priority_high_rounded;
      case 'claimed':
        return Icons.person_search_rounded;
      default:
        return Icons.add_alert_outlined;
    }
  }

  Future<void> _pickDay() async {
    final t = context.appTheme;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: t.navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      _refreshName();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final canExport = _selectedKinds.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                  color: t.navy,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export Shift Report',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Choose date, factory, and action types',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dialogLabel(t, 'Report name', Icons.edit_note_rounded),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          maxLines: 2,
                          minLines: 1,
                          style: TextStyle(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Report name',
                            suffixIcon: _nameTouched
                                ? IconButton(
                                    tooltip: 'Reset name',
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () => setState(() {
                                      _nameTouched = false;
                                      _refreshName();
                                    }),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _dialogLabel(t, 'Report date', Icons.event_rounded),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _pickDay,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: t.scaffold,
                              border: Border.all(color: t.border),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  color: t.muted,
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _date(_day),
                                  style: TextStyle(
                                    color: t.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _dialogLabel(t, 'Factory', Icons.factory_rounded),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _factory,
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All factories'),
                            ),
                            for (final f in widget.factories)
                              DropdownMenuItem(value: f, child: Text(f)),
                          ],
                          onChanged: (v) => setState(() {
                            _factory = v ?? 'all';
                            _refreshName();
                          }),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.business_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _dialogLabel(
                              t,
                              'Action types',
                              Icons.checklist_rounded,
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(() {
                                _selectedKinds =
                                    _selectedKinds.length == actionKinds.length
                                    ? <String>{}
                                    : Set<String>.from(actionKinds);
                              }),
                              child: Text(
                                _selectedKinds.length == actionKinds.length
                                    ? 'Clear all'
                                    : 'Select all',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _selectedKinds = {'ai_assigned', 'handover'};
                              }),
                              child: const Text(
                                'AI only',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final kind in actionKinds)
                              FilterChip(
                                avatar: Icon(_icon(kind), size: 15),
                                label: Text(_label(kind)),
                                selected: _selectedKinds.contains(kind),
                                selectedColor: t.navy.withValues(alpha: 0.14),
                                checkmarkColor: t.navy,
                                backgroundColor: t.scaffold,
                                side: BorderSide(
                                  color: _selectedKinds.contains(kind)
                                      ? t.navy
                                      : t.border,
                                ),
                                labelStyle: TextStyle(
                                  color: t.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _selectedKinds.add(kind);
                                  } else {
                                    _selectedKinds.remove(kind);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: t.scaffold,
                    border: Border(top: BorderSide(color: t.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          canExport
                              ? '${_selectedKinds.length} action type${_selectedKinds.length == 1 ? '' : 's'} selected'
                              : 'No action types selected',
                          style: TextStyle(
                            color: canExport ? t.muted : t.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: canExport
                            ? () => Navigator.pop(
                                context,
                                _ShiftExportSettings(
                                  reportName: _nameController.text.trim(),
                                  day: _day,
                                  factory: _factory,
                                  actionKinds: Set<String>.from(_selectedKinds),
                                ),
                              )
                            : null,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Generate PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogLabel(AppTheme t, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: t.navy),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: t.text,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}

class _PdfIcon extends StatelessWidget {
  const _PdfIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.picture_as_pdf_rounded,
      color: Color(0xFFEC1C24),
      size: 18,
    );
  }
}

class _CountdownText extends StatelessWidget {
  final int minutes;
  final Color color;
  const _CountdownText({required this.minutes, required this.color});

  @override
  Widget build(BuildContext context) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return Text(
      '${h}h ${m}m',
      style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _HandoverBanner extends StatelessWidget {
  final int minutes;
  final bool requesting;
  final String? summary;
  final VoidCallback onGenerate;
  const _HandoverBanner({
    required this.minutes,
    required this.requesting,
    required this.summary,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x3360A5FA), Color(0x33C084FC)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF60A5FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz, color: Color(0xFF60A5FA)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Shift ends in $minutes min — generate AI handover?',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: requesting ? null : onGenerate,
                icon: requesting
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: Colors.white,
                      ),
                label: Text(requesting ? 'Generating…' : 'Generate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF60A5FA),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          if (summary != null) ...[
            const SizedBox(height: 10),
            Text(
              summary!,
              style: TextStyle(color: t.text, fontSize: 12, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────── TIMELINE VIEW ────────────────────────────────────

part of 'supervisors_tab.dart';

class _AssignmentsSubTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final Future<void> Function()? onRefresh;
  const _AssignmentsSubTab({
    super.key,
    required this.supervisors,
    this.onRefresh,
  });

  @override
  State<_AssignmentsSubTab> createState() => _AssignmentsSubTabState();
}

class _AssignmentsSubTabState extends State<_AssignmentsSubTab> {
  List<Factory> _factories = [];
  bool _loading = true;
  StreamSubscription<List<Factory>>? _factoriesSub;

  @override
  void initState() {
    super.initState();
    _factoriesSub = ServiceLocator.instance.hierarchyService
        .getFactories()
        .listen((factories) {
          if (mounted) {
            setState(() {
              _factories = factories;
              _loading = false;
            });
          }
        });
  }

  @override
  void dispose() {
    _factoriesSub?.cancel();
    super.dispose();
  }

  Map<String, List<UserModel>> _groupByFactory() {
    final map = <String, List<UserModel>>{};
    for (var factory in _factories) {
      map[factory.name] = widget.supervisors
          .where((s) => s.usine == factory.name)
          .toList();
    }
    return map;
  }

  List<UserModel> _unassigned() {
    final names = _factories.map((f) => f.name).toSet();
    return widget.supervisors
        .where((s) => s.usine.isEmpty || !names.contains(s.usine))
        .toList();
  }

  String? _locationFor(String factoryName) {
    for (var f in _factories) {
      if (f.name == factoryName) return f.location;
    }
    return null;
  }

  Future<void> _reassign(UserModel sup, String newFactory) async {
    if (sup.usine == newFactory) return;
    try {
      await AuthService().updateSupervisorProfile(
        userId: sup.id,
        firstName: sup.firstName,
        lastName: sup.lastName,
        email: sup.email,
        phone: sup.phone,
        usine: newFactory,
      );
      if (!mounted) return;
      final t = context.appTheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newFactory.isEmpty
                ? '${sup.fullName} unassigned'
                : '${sup.fullName} moved to $newFactory',
          ),
          backgroundColor: t.green,
        ),
      );
      widget.onRefresh?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.tr('Failed: {error}',
                {'error': UserFriendlyError.message(e)}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppLoadingIndicator();

    final t = context.appTheme;
    final grouped = _groupByFactory();
    final unassigned = _unassigned();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supervisor Assignments',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: t.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Drag supervisors between plants · tap × to unassign',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.card,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(14),
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
                    Icon(Icons.bar_chart, size: 16, color: t.navy),
                    const SizedBox(width: 8),
                    Text(
                      'Assignments by Plant',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Drag a supervisor to a different plant to reassign',
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
                const SizedBox(height: 16),
                ...grouped.entries.map(
                  (e) => _buildFactoryCard(t, e.key, e.value),
                ),
                if (unassigned.isNotEmpty) _buildUnassignedCard(t, unassigned),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFactoryCard(
    AppTheme t,
    String factoryName,
    List<UserModel> sups,
  ) {
    final location = _locationFor(factoryName);
    return DragTarget<UserModel>(
      onWillAcceptWithDetails: (d) => d.data.usine != factoryName,
      onAcceptWithDetails: (d) => _reassign(d.data, factoryName),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hovering ? t.navy.withValues(alpha: .08) : t.scaffold,
            border: Border.all(
              color: hovering ? t.navy : t.border,
              width: hovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          factoryName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                        if (location != null && location.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            location,
                            style: TextStyle(fontSize: 12, color: t.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: sups.isEmpty ? t.scaffold : t.navyLt,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      sups.isEmpty
                          ? '0 supervisors'
                          : '${sups.length} supervisor${sups.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sups.isEmpty ? t.muted : t.navy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (sups.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: hovering ? t.navy.withValues(alpha: .4) : t.border,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      hovering
                          ? 'Drop here to assign'
                          : 'No supervisor assigned',
                      style: TextStyle(
                        fontSize: 12,
                        color: hovering ? t.navy : t.muted,
                        fontStyle: hovering
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sups
                      .map(
                        (s) =>
                            _SupChip(sup: s, onRemove: () => _reassign(s, '')),
                      )
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnassignedCard(AppTheme t, List<UserModel> sups) {
    return DragTarget<UserModel>(
      onWillAcceptWithDetails: (d) => d.data.usine.isNotEmpty,
      onAcceptWithDetails: (d) => _reassign(d.data, ''),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hovering
                ? t.orange.withValues(alpha: .08)
                : t.orangeLt.withValues(alpha: .5),
            border: Border.all(
              color: hovering ? t.orange : t.orange.withValues(alpha: .35),
              width: hovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unassigned',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.orange,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Not assigned to any plant',
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: t.orangeLt,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${sups.length} supervisor${sups.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sups.map((s) => _SupChip(sup: s)).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SupChip extends StatelessWidget {
  final UserModel sup;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final bool selected;
  const _SupChip({
    required this.sup,
    this.onRemove,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.only(
            left: 10,
            right: onRemove != null ? 6 : 12,
            top: 6,
            bottom: 6,
          ),
          decoration: BoxDecoration(
            color: selected ? t.navy : t.navyLt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? t.navy : t.navy.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline,
                size: 13,
                color: selected ? Colors.white : t.navy,
              ),
              const SizedBox(width: 6),
              Text(
                sup.fullName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : t.navy,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: (selected ? Colors.white : t.navy).withValues(
                        alpha: .15,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: selected ? Colors.white : t.navy,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Draggable<UserModel>(
      data: sup,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: t.navy,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: t.navy.withValues(alpha: .35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 13, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                sup.fullName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }
}

Widget _emptySups() => Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: const [
      Icon(Icons.people_outline, size: 52, color: _muted),
      SizedBox(height: 12),
      Text(
        'No supervisors yet',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _muted,
        ),
      ),
      SizedBox(height: 6),
      Text(
        'Tap "Add Supervisor" to create an account',
        style: TextStyle(fontSize: 12, color: _muted),
      ),
    ],
  ),
);

class _SupervisorCard extends StatefulWidget {
  final UserModel supervisor;
  final List<AlertModel> alerts;
  final List<Factory> factories;
  final Future<void> Function() onRefresh;
  final VoidCallback onDelete;
  const _SupervisorCard({
    required this.supervisor,
    required this.alerts,
    required this.factories,
    required this.onDelete,
    required this.onRefresh,
  });
  @override
  State<_SupervisorCard> createState() => _SupervisorCardState();
}

class _SupervisorCardState extends State<_SupervisorCard> {
  bool _expanded = false;

  Future<void> _showDeleteConfirmDialog(BuildContext context) async {
    final sup = widget.supervisor;
    return showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.appTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_outlined,
                  color: _red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete Supervisor',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sup.fullName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: _red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: _red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. All associated data will be permanently removed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _red.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: _text, height: 1.6),
                children: [
                  const TextSpan(
                    text: 'You are about to delete: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: sup.fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const TextSpan(text: ' from '),
                  TextSpan(
                    text: sup.usine,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              widget.onDelete();
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text(
              'Delete Permanently',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: _white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModifyDialog(BuildContext context) async {
    final sup = widget.supervisor;
    final firstCtrl = TextEditingController(text: sup.firstName);
    final lastCtrl = TextEditingController(text: sup.lastName);
    final emailCtrl = TextEditingController(text: sup.email);
    final phoneCtrl = TextEditingController(text: sup.phone);
    final usineChoices = <String>{
      sup.usine,
      ...widget.factories.map((f) => f.name),
    }.toList()..sort();
    var selectedUsine = sup.usine;
    var saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(context.tr('Modify Supervisor')),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SheetLabel(context.tr('First Name')),
                      TextField(
                        controller: firstCtrl,
                        decoration: InputDecoration(
                          hintText: context.tr('First name'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel(context.tr('Last Name')),
                      TextField(
                        controller: lastCtrl,
                        decoration: InputDecoration(
                          hintText: context.tr('Last name'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel(context.tr('Email')),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: context.tr('Email address'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel(context.tr('Phone')),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: context.tr('Phone number'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SheetLabel(context.tr('Assigned Plant')),
                      DropdownButtonFormField<String>(
                        value: selectedUsine,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: usineChoices
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
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
                  child: Text(context.tr('Cancel')),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final first = firstCtrl.text.trim();
                          final last = lastCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          if (first.isEmpty || last.isEmpty || email.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.tr(
                                      'First name, last name, and email are required'),
                                ),
                              ),
                            );
                            return;
                          }
                          if (!email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    context.tr('Please enter a valid email')),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => saving = true);
                          try {
                            await AuthService().updateSupervisorProfile(
                              userId: sup.id,
                              firstName: first,
                              lastName: last,
                              email: email,
                              phone: phone,
                              usine: selectedUsine,
                            );
                            await widget.onRefresh();
                            if (!mounted) return;
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.tr('Supervisor updated successfully'),
                                ),
                                backgroundColor: _green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.tr('Update failed: {error}', {
                                    'error': UserFriendlyError.message(e)
                                  }),
                                ),
                              ),
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('Save Changes')),
                ),
              ],
            );
          },
        );
      },
    );

    firstCtrl.dispose();
    lastCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sup = widget.supervisor;
    final solved = widget.alerts
        .where(
          (a) =>
              a.status == 'validee' &&
              (a.superviseurId == sup.id || a.assistantId == sup.id),
        )
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
        color: context.appTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _navyLt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.engineering, size: 24),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: sc,
                          shape: BoxShape.circle,
                          border: Border.all(color: _white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sup.fullName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _navy,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sc.withOpacity(.1),
                              border: Border.all(color: sc),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: sc,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  sup.isActive ? 'Active' : 'Absent',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: sc,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sup.email,
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 12, color: _muted),
                          const SizedBox(width: 3),
                          Text(
                            sup.phone.isEmpty ? 'No phone' : sup.phone,
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.factory, size: 12, color: _muted),
                          const SizedBox(width: 3),
                          Text(
                            sup.usine,
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                      if (sup.hiredDate != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: _muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Hired: ${_fmtDate(sup.hiredDate!)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MiniChip(
                            Icons.check_circle_outline,
                            '${solved.length} fixed',
                            _green,
                          ),
                          _MiniChip(Icons.timer, '$inProg claimed', _blue),
                          if (avgMin != null)
                            _MiniChip(
                              Icons.av_timer,
                              'Avg ${_fmtMin(avgMin)}',
                              _orange,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    if (solved.isNotEmpty)
                      IconButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: _navy,
                        ),
                      ),
                    IconButton(
                      onPressed: () => _showModifyDialog(context),
                      icon: Icon(Icons.edit, color: _navy, size: 20),
                      tooltip: context.tr('Modify Supervisor'),
                    ),
                    IconButton(
                      onPressed: () => _showDeleteConfirmDialog(context),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: _red,
                        size: 20,
                      ),
                      tooltip: context.tr('Delete Supervisor'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_expanded && solved.isNotEmpty) ...[
            Divider(height: 1, color: _border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FIXED CASES HISTORY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...solved.map(
                    (a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _typeColor(a.type),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_typeLabel(a.type)} — ${a.description}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _navy,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${a.usine} · Line ${a.convoyeur} · Post ${a.poste}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              a.elapsedTime != null
                                  ? _fmtMin(a.elapsedTime!)
                                  : '-',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
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
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class SheetField extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final TextInputType keyboard;
  const SheetField(
    this.label,
    this.ctrl,
    this.hint, {
    this.obscure = false,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SheetLabel(label),
      TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _muted),
          filled: true,
          fillColor: context.appTheme.scaffold,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: _navy, width: 1.5),
          ),
        ),
      ),
      const SizedBox(height: 14),
    ],
  );
}

class SheetLabel extends StatelessWidget {
  final String text;
  const SheetLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: _muted,
        letterSpacing: 1.3,
      ),
    ),
  );
}

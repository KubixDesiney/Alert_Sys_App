import 'package:flutter/material.dart';

import '../../models/shift_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/service_locator.dart';
import '../../services/shift_service.dart';
import '../../theme.dart';
import '../../widgets/common/app_loading_indicator.dart';

/// Bottom-sheet style modal for creating or editing a shift.
class ShiftCreationDialog extends StatefulWidget {
  final ShiftModel? existing;

  const ShiftCreationDialog({super.key, this.existing});

  static Future<bool?> show(BuildContext context, {ShiftModel? existing}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => ShiftCreationDialog(existing: existing),
    );
  }

  @override
  State<ShiftCreationDialog> createState() => _ShiftCreationDialogState();
}

class _ShiftCreationDialogState extends State<ShiftCreationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryCtrl;

  final _nameCtrl = TextEditingController(text: 'Morning Shift');
  TimeOfDay _start = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 14, minute: 0);
  int _maxSupervisors = 3;
  bool _aiCommander = false;
  bool _randomize = false;
  String _aiModel = 'llama-3.2-3b';
  bool _handleAssignments = true;
  bool _handleCollaborations = false;
  bool _handleCrossFactoryTransfer = false;
  bool _fullControl = false;

  String _searchQuery = '';
  final Set<String> _selectedIds = <String>{};

  List<UserModel> _all = [];
  List<ShiftModel> _otherShifts = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final ShiftService _shifts = ServiceLocator.instance.shiftService;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();

    if (widget.existing != null) {
      final s = widget.existing!;
      _nameCtrl.text = s.name;
      _start =
          TimeOfDay(hour: s.startMinutes ~/ 60, minute: s.startMinutes % 60);
      _end = TimeOfDay(hour: s.endMinutes ~/ 60, minute: s.endMinutes % 60);
      _maxSupervisors = s.maxSupervisors;
      _aiCommander = s.aiCommander;
      _randomize = s.randomize;
      _aiModel = s.aiModel;
      _handleAssignments = s.handleAssignments;
      _handleCollaborations = s.handleCollaborations;
      _handleCrossFactoryTransfer = s.handleCrossFactoryTransfer;
      _fullControl = s.fullControl;
      _selectedIds.addAll(s.supervisors.map((e) => e.id));
    }

    _loadSupervisors();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSupervisors() async {
    try {
      final list = await AuthService().fetchSupervisors();
      List<ShiftModel> shifts = const [];
      try {
        shifts = await _shifts.fetchShiftsOnce();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _all = list;
        _otherShifts =
            shifts.where((s) => s.id != widget.existing?.id).toList();
        _loading = false;
      });
      if (_randomize && _selectedIds.isEmpty) _doRandomize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load supervisors';
      });
    }
  }

  /// Returns the first shift (other than this one) that already contains
  /// [supervisorId], or null if the supervisor is free.
  ShiftModel? _conflictingShiftFor(String supervisorId) {
    for (final s in _otherShifts) {
      if (s.supervisors.any((sup) => sup.id == supervisorId)) return s;
    }
    return null;
  }

  Future<void> _showDoubleAssignmentRejection({
    required UserModel user,
    required ShiftModel conflict,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => _DoubleAssignmentDialog(
        user: user,
        existingShift: conflict,
        attemptedShiftName: _nameCtrl.text.trim().isEmpty
            ? 'this shift'
            : _nameCtrl.text.trim(),
      ),
    );
  }

  void _doRandomize() {
    final eligible =
        _all.where((u) => u.role == 'supervisor').toList(growable: false);
    final picks = ShiftService.randomizePool(
      eligible,
      _maxSupervisors,
      excludeAlreadyAssigned: _otherShifts,
    );
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(picks.map((p) => p.id));
    });
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: _start,
        builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ));
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: _end,
        builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ));
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a shift name');
      return;
    }
    final picked = _all
        .where((u) => _selectedIds.contains(u.id))
        .map((u) => AssignedSupervisor(
              id: u.id,
              name: u.fullName,
              factory: u.usine,
            ))
        .toList();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final draft = ShiftModel(
        id: widget.existing?.id ?? '',
        name: _nameCtrl.text.trim(),
        startMinutes: _start.hour * 60 + _start.minute,
        endMinutes: _end.hour * 60 + _end.minute,
        supervisors: picked,
        maxSupervisors: _maxSupervisors,
        aiCommander: _aiCommander,
        aiModel: _aiModel,
        aiConfidence: 0.65,
        handleAssignments: _handleAssignments,
        handleCollaborations: _handleCollaborations,
        handleCrossFactoryTransfer: _handleCrossFactoryTransfer,
        fullControl: _fullControl,
        randomize: _randomize,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );
      if (widget.existing == null) {
        await _shifts.createShift(draft);
      } else {
        await _shifts.updateShift(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to save: $e';
      });
    }
  }

  void _setFullControl(bool value) {
    setState(() {
      _fullControl = value;
      if (value) {
        _handleAssignments = true;
        _handleCollaborations = true;
        _handleCrossFactoryTransfer = true;
      }
    });
  }

  void _setHandleAssignments(bool value) {
    setState(() {
      _handleAssignments = value;
      if (!value) {
        _handleCollaborations = false;
        _handleCrossFactoryTransfer = false;
      }
    });
  }

  void _setHandleCollaborations(bool value) {
    setState(() {
      _handleCollaborations = value;
      if (value) _handleAssignments = true;
    });
  }

  void _setHandleCrossFactoryTransfer(bool value) {
    setState(() {
      _handleCrossFactoryTransfer = value;
      if (value) _handleAssignments = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.92;

    return AnimatedBuilder(
      animation: _entryCtrl,
      builder: (ctx, child) {
        final anim =
            CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(
            scale: 0.96 + 0.04 * anim.value,
            child: child,
          ),
        );
      },
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            margin:
                const EdgeInsets.symmetric(horizontal: 12).copyWith(bottom: 12),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: t.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 36,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(
                  isEdit: widget.existing != null,
                  onClose: () => Navigator.of(context).pop(false),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Shift name'),
                        TextField(
                          controller: _nameCtrl,
                          style: TextStyle(color: t.text),
                          decoration: const InputDecoration(
                            hintText: 'e.g. Morning Shift',
                            prefixIcon: Icon(Icons.badge),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _TimeChip(
                                label: 'Starts',
                                time: _start,
                                onTap: _pickStart,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TimeChip(
                                label: 'Ends',
                                time: _end,
                                onTap: _pickEnd,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _NumericStepper(
                          label: 'Maximum supervisors per shift',
                          value: _maxSupervisors,
                          min: 1,
                          max: 12,
                          onChanged: (v) => setState(() => _maxSupervisors = v),
                        ),
                        const SizedBox(height: 18),
                        _AiToggleCard(
                          enabled: _aiCommander,
                          onChanged: (v) => setState(() => _aiCommander = v),
                          model: _aiModel,
                          onModelChanged: (v) =>
                              setState(() => _aiModel = v ?? _aiModel),
                          handleAssignments: _handleAssignments,
                          onHandleAssignmentsChanged: _setHandleAssignments,
                          handleCollaborations: _handleCollaborations,
                          onHandleCollaborationsChanged:
                              _setHandleCollaborations,
                          handleCrossFactoryTransfer:
                              _handleCrossFactoryTransfer,
                          onHandleCrossFactoryTransferChanged:
                              _setHandleCrossFactoryTransfer,
                          fullControl: _fullControl,
                          onFullControlChanged: _setFullControl,
                        ),
                        const SizedBox(height: 14),
                        _RandomizeToggleCard(
                          enabled: _randomize,
                          onChanged: (v) {
                            setState(() => _randomize = v);
                            if (v) _doRandomize();
                          },
                          onReroll: _randomize ? _doRandomize : null,
                        ),
                        const SizedBox(height: 18),
                        _label('Search supervisors'),
                        TextField(
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.toLowerCase()),
                          decoration: const InputDecoration(
                            hintText: 'Filter by name, factory, or email…',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SupervisorList(
                          loading: _loading,
                          all: _all,
                          query: _searchQuery,
                          selected: _selectedIds,
                          onToggle: (uid) {
                            if (_selectedIds.contains(uid)) {
                              setState(() => _selectedIds.remove(uid));
                              return;
                            }
                            if (_selectedIds.length >= _maxSupervisors) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Max $_maxSupervisors supervisors per shift'),
                                  backgroundColor: t.orange,
                                ),
                              );
                              return;
                            }
                            final conflict = _conflictingShiftFor(uid);
                            if (conflict != null) {
                              final user = _all.firstWhere((u) => u.id == uid);
                              _showDoubleAssignmentRejection(
                                user: user,
                                conflict: conflict,
                              );
                              return;
                            }
                            setState(() => _selectedIds.add(uid));
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.redLt,
                              border: Border.all(color: t.red),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(color: t.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _Footer(
                  saving: _saving,
                  count: _selectedIds.length,
                  max: _maxSupervisors,
                  onCancel: () => Navigator.of(context).pop(false),
                  onSave: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 6),
        child: Text(
          text,
          style: TextStyle(
            color: context.appTheme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  final bool isEdit;
  final VoidCallback onClose;
  const _Header({required this.isEdit, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF60A5FA), Color(0xFFC084FC)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.schedule, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Edit Shift' : 'New Shift',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Configure schedule, supervisors, and AI commander',
                  style: TextStyle(color: t.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: t.muted),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  const _TimeChip(
      {required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: t.scaffold,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: t.navy),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: t.muted, fontSize: 11)),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: t.text, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.edit, size: 16, color: t.muted),
          ],
        ),
      ),
    );
  }
}

class _NumericStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _NumericStepper(
      {required this.label,
      required this.value,
      required this.min,
      required this.max,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.scaffold,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: t.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Text(
                  'Hard cap on supervisors assigned at once',
                  style: TextStyle(color: t.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          Container(
            width: 36,
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: TextStyle(
                color: t.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _AiToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String model;
  final ValueChanged<String?> onModelChanged;
  final bool handleAssignments;
  final ValueChanged<bool> onHandleAssignmentsChanged;
  final bool handleCollaborations;
  final ValueChanged<bool> onHandleCollaborationsChanged;
  final bool handleCrossFactoryTransfer;
  final ValueChanged<bool> onHandleCrossFactoryTransferChanged;
  final bool fullControl;
  final ValueChanged<bool> onFullControlChanged;

  const _AiToggleCard({
    required this.enabled,
    required this.onChanged,
    required this.model,
    required this.onModelChanged,
    required this.handleAssignments,
    required this.onHandleAssignmentsChanged,
    required this.handleCollaborations,
    required this.onHandleCollaborationsChanged,
    required this.handleCrossFactoryTransfer,
    required this.onHandleCrossFactoryTransferChanged,
    required this.fullControl,
    required this.onFullControlChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x3360A5FA),
                  Color(0x33C084FC),
                ],
              )
            : null,
        color: enabled ? null : t.scaffold,
        border: Border.all(
            color: enabled ? const Color(0xFF60A5FA) : t.border,
            width: enabled ? 1.5 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF60A5FA), Color(0xFFC084FC)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Shift Commander',
                      style: TextStyle(
                          color: t.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Let AI manage this shift: accept collaborations, '
                      'assign supervisors to alerts, handle cross-factory '
                      'transfers automatically.',
                      style:
                          TextStyle(color: t.muted, fontSize: 11, height: 1.35),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                onChanged: onChanged,
                activeColor: const Color(0xFF60A5FA),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Commander Settings',
                      style: TextStyle(
                          color: t.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: model,
                    items: const [
                      DropdownMenuItem(
                        value: 'llama-3.2-3b',
                        child: Text('Llama 3.2 3B (Workers AI)'),
                      ),
                    ],
                    onChanged: onModelChanged,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.smart_toy),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose exactly what the commander is allowed to handle '
                    'during this shift.',
                    style:
                        TextStyle(color: t.muted, fontSize: 11, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  _CommanderTaskTile(
                    label: 'Handle Assignments',
                    subtitle: 'Auto-assign supervisors to alerts.',
                    value: handleAssignments || fullControl,
                    enabled: !fullControl,
                    onChanged: onHandleAssignmentsChanged,
                  ),
                  const SizedBox(height: 8),
                  _CommanderTaskTile(
                    label: 'Handle Collaborations',
                    subtitle:
                        'Approve collaboration requests after assistant approvals.',
                    value: handleCollaborations || fullControl,
                    enabled: !fullControl,
                    onChanged: onHandleCollaborationsChanged,
                  ),
                  const SizedBox(height: 8),
                  _CommanderTaskTile(
                    label: 'Handle Cross-factory Transfer',
                    subtitle:
                        'Allow rostered supervisors to cover alerts across factories.',
                    value: handleCrossFactoryTransfer || fullControl,
                    enabled: !fullControl,
                    onChanged: onHandleCrossFactoryTransferChanged,
                  ),
                  const SizedBox(height: 8),
                  _CommanderTaskTile(
                    label: 'Full control',
                    subtitle:
                        'Commander manages assignments, collaborations, and transfers.',
                    value: fullControl,
                    enabled: true,
                    forceActiveStyle: fullControl,
                    onChanged: onFullControlChanged,
                  ),
                ],
              ),
            ),
            crossFadeState:
                enabled ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 280),
          ),
        ],
      ),
    );
  }
}

class _CommanderTaskTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final bool enabled;
  final bool forceActiveStyle;
  final ValueChanged<bool> onChanged;

  const _CommanderTaskTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.forceActiveStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final active = value || forceActiveStyle;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.68,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0x1416A34A) : t.scaffold,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? const Color(0xFF16A34A) : t.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_circle : Icons.radio_button_unchecked,
              color: active ? const Color(0xFF16A34A) : t.muted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: t.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: const Color(0xFF16A34A),
            ),
          ],
        ),
      ),
    );
  }
}

class _RandomizeToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onReroll;

  const _RandomizeToggleCard({
    required this.enabled,
    required this.onChanged,
    required this.onReroll,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.scaffold,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.shuffle, color: t.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Randomize shift assignment',
                    style: TextStyle(
                        color: t.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Text(
                  'AI picks supervisors at random from the active pool, '
                  'spread across factories.',
                  style: TextStyle(color: t.muted, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
          if (enabled && onReroll != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Re-randomize',
              onPressed: onReroll,
            ),
          Switch.adaptive(
            value: enabled,
            onChanged: onChanged,
            activeColor: t.navy,
          ),
        ],
      ),
    );
  }
}

class _SupervisorList extends StatelessWidget {
  final bool loading;
  final List<UserModel> all;
  final String query;
  final Set<String> selected;
  final void Function(String uid) onToggle;

  const _SupervisorList({
    required this.loading,
    required this.all,
    required this.query,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: AppLoadingIndicator(),
      );
    }
    final filtered = all.where((u) {
      if (query.isEmpty) return true;
      return u.fullName.toLowerCase().contains(query) ||
          u.usine.toLowerCase().contains(query) ||
          u.email.toLowerCase().contains(query);
    }).toList();
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text('No supervisors match this search',
              style: TextStyle(color: t.muted)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: t.scaffold,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (int i = 0; i < filtered.length; i++) ...[
            if (i > 0) Divider(height: 1, color: t.border.withOpacity(0.6)),
            _SupervisorTile(
              user: filtered[i],
              selected: selected.contains(filtered[i].id),
              onTap: () => onToggle(filtered[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupervisorTile extends StatelessWidget {
  final UserModel user;
  final bool selected;
  final VoidCallback onTap;
  const _SupervisorTile(
      {required this.user, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final colors = [
      const Color(0xFF60A5FA),
      const Color(0xFFC084FC),
      const Color(0xFF34D399),
      const Color(0xFFFBBF24),
      const Color(0xFFF87171),
    ];
    final color = colors[user.id.hashCode.abs() % colors.length];
    final initials = (user.firstName.isEmpty ? '?' : user.firstName[0]) +
        (user.lastName.isEmpty ? '' : user.lastName[0]);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: t.card, width: 2),
              ),
              child: Center(
                child: Text(initials.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName,
                      style: TextStyle(
                          color: t.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text('${user.usine} • ${user.email}',
                      style: TextStyle(color: t.muted, fontSize: 11)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? t.green : t.scaffold,
                shape: BoxShape.circle,
                border:
                    Border.all(color: selected ? t.green : t.border, width: 2),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool saving;
  final int count;
  final int max;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  const _Footer(
      {required this.saving,
      required this.count,
      required this.max,
      required this.onCancel,
      required this.onSave});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.navyLt,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text('$count / $max selected',
                style: TextStyle(
                    color: t.navy, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save, size: 16),
            label: Text(saving ? 'Saving…' : 'Save Shift'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubleAssignmentDialog extends StatelessWidget {
  final UserModel user;
  final ShiftModel existingShift;
  final String attemptedShiftName;
  const _DoubleAssignmentDialog({
    required this.user,
    required this.existingShift,
    required this.attemptedShiftName,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: t.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.block_flipped, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Double Assignment Blocked',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.fullName} is already assigned',
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A supervisor cannot work two shifts at the same time. ${user.fullName} is already assigned to:',
              style: TextStyle(
                color: t.text,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.scaffold,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        switch (existingShift.kind) {
                          ShiftKind.morning => Icons.wb_sunny,
                          ShiftKind.afternoon => Icons.wb_twilight,
                          ShiftKind.night => Icons.nights_stay,
                        },
                        size: 16,
                        color: t.navy,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          existingShift.name,
                          style: TextStyle(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    existingShift.timeRangeLabel,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'If you need to move ${user.firstName} to "$attemptedShiftName", first remove them from "${existingShift.name}".',
              style: TextStyle(
                color: t.muted,
                fontSize: 12,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Understood',
            style: TextStyle(
              color: t.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

part of 'hw_factory_binding.dart';

class _BindingEditor extends StatefulWidget {
  final HwDeviceBinding? existing;
  final HwFactoryCatalog catalog;
  final List<HwCircuit> circuits;
  final HwMachineStore store;
  const _BindingEditor({
    required this.existing,
    required this.catalog,
    required this.circuits,
    required this.store,
  });

  @override
  State<_BindingEditor> createState() => _BindingEditorState();
}

class _BindingEditorState extends State<_BindingEditor> {
  late final TextEditingController _custom;
  late List<HwMachine> _machines;

  String? _factoryId; // hierarchy id used for filtering
  String _factoryName = '';
  String? _conveyorId;
  String _conveyorLabel = '';
  String? _machineId;
  late String _controller;
  late String _circuitId;
  late String _status;
  late Set<String> _peripherals;

  @override
  void initState() {
    super.initState();
    _machines = [...widget.catalog.machines];
    final b = widget.existing;
    _custom = TextEditingController();
    _controller = b?.controllerType ?? 'esp32';
    _circuitId = b?.circuitId ?? '';
    _status = b?.status ?? 'designed';
    _peripherals = {...?b?.peripherals};

    if (b != null) {
      _machineId = b.machineLabel.isEmpty ? null : b.machineLabel;
      _factoryName = b.factoryId;
      _conveyorLabel = b.conveyor;
      // Backfill from the catalog where we can.
      final m = _machineId == null
          ? null
          : widget.catalog.machineById(_machineId!);
      if (m != null) {
        final fac = widget.catalog.factoryForMachine(m);
        _factoryId =
            fac?.id ?? (m.factoryId.isEmpty ? _factoryId : m.factoryId);
        if (fac != null) {
          _factoryName = fac.name;
        } else if (_factoryName.isEmpty) {
          _factoryName = m.factoryName;
        }
        if (m.conveyorId.isNotEmpty) {
          final c = widget.catalog.conveyorById(_factoryId, m.conveyorId);
          _conveyorId = c?.id ?? m.conveyorId;
          if (_conveyorLabel.isEmpty) {
            _conveyorLabel = c?.label ?? m.conveyorLabel;
          }
        }
      }
      // Match factory by display name when no id resolved.
      _factoryId ??= _factoryByName(_factoryName)?.id;
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  HwFactoryRef? _factoryByName(String name) {
    for (final f in widget.catalog.factories) {
      if (f.name.trim().toLowerCase() == name.trim().toLowerCase()) return f;
    }
    return null;
  }

  List<HwMachine> get _filteredMachines {
    return _machines.where((m) {
      if (!widget.catalog.machineMatchesFactory(m, _factoryId)) return false;
      if (!widget.catalog.machineMatchesConveyor(m, _factoryId, _conveyorId)) {
        return false;
      }
      return true;
    }).toList();
  }

  void _onPickMachine(String? id) {
    setState(() {
      _machineId = id;
      final m = id == null ? null : _machineById(id);
      if (m != null) {
        final fac = widget.catalog.factoryForMachine(m);
        if (fac != null) {
          _factoryId = fac.id;
          _factoryName = fac.name;
        } else {
          if (m.factoryId.isNotEmpty) _factoryId = m.factoryId;
          if (m.factoryName.isNotEmpty) _factoryName = m.factoryName;
        }
        if (m.conveyorId.isNotEmpty) {
          final c = widget.catalog.conveyorById(_factoryId, m.conveyorId);
          _conveyorId = c?.id ?? m.conveyorId;
          _conveyorLabel = c?.label ?? m.conveyorLabel;
        }
      }
    });
  }

  HwMachine? _machineById(String id) {
    for (final m in _machines) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _addMachineInline() async {
    final m = await showDialog<HwMachine>(
      context: context,
      builder: (_) =>
          _MachineEditor(catalog: widget.catalog, presetFactoryId: _factoryId),
    );
    if (m == null) return;
    await widget.store.saveMachine(m);
    if (!mounted) return;
    setState(() {
      _machines = [..._machines.where((x) => x.id != m.id), m]
        ..sort((a, b) => a.id.compareTo(b.id));
    });
    _onPickMachine(m.id);
  }

  void _save() {
    final b = widget.existing ?? HwDeviceBinding(id: hwNewId('bind'));
    b
      ..machineLabel = _machineId ?? ''
      ..conveyor = _conveyorLabel
      ..factoryId = _factoryName
      ..controllerType = _controller
      ..circuitId = _circuitId
      ..status = _status
      ..peripherals = _peripherals.toList()
      ..updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    Navigator.pop(context, b);
  }

  @override
  Widget build(BuildContext context) {
    final conveyors = _factoryId == null
        ? <HwConveyorRef>[]
        : widget.catalog.conveyorsFor(_factoryId!);
    final machines = _filteredMachines;

    return Dialog(
      backgroundColor: Sa.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Sa.cyan.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.add_link, color: Sa.cyan, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      widget.existing == null
                          ? 'Bind Device to Machine'
                          : 'Edit Device Binding',
                      style: Sa.heading(size: 17),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pick the factory, line and machine from live plant inventory '
                  '— MACH-001 (LEDs · buttons · sensors) ← its controller.',
                  style: Sa.body(size: 11.5, color: Sa.textDim),
                ),
                const SizedBox(height: 16),

                _hwFieldLabel('FACTORY'),
                DropdownButtonFormField<String>(
                  initialValue:
                      widget.catalog.factories.any((f) => f.id == _factoryId)
                      ? _factoryId
                      : null,
                  isExpanded: true,
                  dropdownColor: Sa.panelSolid,
                  style: Sa.body(size: 12.5),
                  decoration: _hwDec('Select a factory'),
                  items: [
                    for (final f in widget.catalog.factories)
                      DropdownMenuItem(value: f.id, child: Text(f.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _factoryId = v;
                    _factoryName = v == null
                        ? ''
                        : (widget.catalog.factories
                              .firstWhere(
                                (f) => f.id == v,
                                orElse: () =>
                                    const HwFactoryRef(id: '', name: ''),
                              )
                              .name);
                    _conveyorId = null;
                    _conveyorLabel = '';
                    if (_machineId != null) {
                      final picked = _machineById(_machineId!);
                      if (picked != null &&
                          !widget.catalog.machineMatchesFactory(picked, v)) {
                        _machineId = null;
                      }
                    }
                  }),
                ),
                if (widget.catalog.factories.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'No factories in the hierarchy yet — bind without one or '
                      'create factories in Production Manager.',
                      style: Sa.body(size: 10.5, color: Sa.muted),
                    ),
                  ),
                const SizedBox(height: 14),

                _hwFieldLabel('CONVEYOR LINE'),
                DropdownButtonFormField<String>(
                  initialValue: conveyors.any((c) => c.id == _conveyorId)
                      ? _conveyorId
                      : null,
                  isExpanded: true,
                  dropdownColor: Sa.panelSolid,
                  style: Sa.body(size: 12.5),
                  decoration: _hwDec(
                    _factoryId == null
                        ? 'Pick a factory first'
                        : 'Select a conveyor line',
                  ),
                  items: [
                    for (final c in conveyors)
                      DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Expanded(child: Text(c.label)),
                            _MachineStatusPill(status: c.status),
                          ],
                        ),
                      ),
                  ],
                  onChanged: conveyors.isEmpty
                      ? null
                      : (v) => setState(() {
                          _conveyorId = v;
                          final c = conveyors.firstWhere(
                            (x) => x.id == v,
                            orElse: () =>
                                HwConveyorRef(id: '', number: 0, factoryId: ''),
                          );
                          _conveyorLabel = c.id.isEmpty ? '' : c.label;
                          if (_machineId != null) {
                            final picked = _machineById(_machineId!);
                            if (picked != null &&
                                !widget.catalog.machineMatchesConveyor(
                                  picked,
                                  _factoryId,
                                  v,
                                )) {
                              _machineId = null;
                            }
                          }
                        }),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    _hwFieldLabel('MACHINE (MACH-XXX)'),
                    const Spacer(),
                    InkWell(
                      onTap: _addMachineInline,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 13, color: Sa.violet),
                            const SizedBox(width: 3),
                            Text(
                              'NEW MACHINE',
                              style: Sa.mono(size: 8.5, color: Sa.violet),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  initialValue: machines.any((m) => m.id == _machineId)
                      ? _machineId
                      : null,
                  isExpanded: true,
                  dropdownColor: Sa.panelSolid,
                  style: Sa.body(size: 12.5),
                  decoration: _hwDec('Select a machine'),
                  items: [
                    for (final m in machines)
                      DropdownMenuItem(
                        value: m.id,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                m.displayName == m.id
                                    ? m.id
                                    : '${m.id} · ${m.displayName}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _MachineStatusPill(status: m.status),
                          ],
                        ),
                      ),
                  ],
                  onChanged: _onPickMachine,
                ),
                if (machines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'No machines match — tap NEW MACHINE to add one.',
                      style: Sa.body(size: 10.5, color: Sa.muted),
                    ),
                  ),
                const SizedBox(height: 16),

                _hwFieldLabel('CONTROLLER'),
                DropdownButtonFormField<String>(
                  initialValue: _controller,
                  isExpanded: true,
                  dropdownColor: Sa.panelSolid,
                  style: Sa.body(size: 12.5),
                  decoration: _hwDec('Controller board'),
                  items: [
                    for (final def in hwControllers())
                      DropdownMenuItem(value: def.type, child: Text(def.name)),
                  ],
                  onChanged: (v) => setState(() => _controller = v ?? 'esp32'),
                ),
                const SizedBox(height: 14),

                _hwFieldLabel('LINKED CIRCUIT'),
                DropdownButtonFormField<String>(
                  initialValue: _circuitId.isEmpty ? null : _circuitId,
                  isExpanded: true,
                  dropdownColor: Sa.panelSolid,
                  style: Sa.body(size: 12.5),
                  decoration: _hwDec('No circuit'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('None')),
                    for (final c in widget.circuits)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _circuitId = v ?? ''),
                ),
                const SizedBox(height: 14),

                _hwFieldLabel('PERIPHERALS'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in {...kHwPeripheralPresets, ..._peripherals})
                      _toggleChip(p),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _custom,
                        style: Sa.body(size: 13),
                        cursorColor: Sa.cyan,
                        decoration: _hwDec(
                          'e.g. Flow meter',
                          label: 'Add custom peripheral',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SaButton(
                      label: 'ADD',
                      icon: Icons.add,
                      color: Sa.violet,
                      outlined: true,
                      onPressed: () {
                        final v = _custom.text.trim();
                        if (v.isNotEmpty) {
                          setState(() {
                            _peripherals.add(v);
                            _custom.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _hwFieldLabel('DEPLOY STATUS'),
                Wrap(
                  spacing: 8,
                  children: kHwBindingStatus.entries
                      .map((e) => _statusChip(e.key, e.value))
                      .toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: Sa.body(color: Sa.textDim)),
                    ),
                    const SizedBox(width: 8),
                    SaButton(
                      label: 'SAVE BINDING',
                      icon: Icons.check,
                      color: Sa.cyan,
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleChip(String p) {
    final on = _peripherals.contains(p);
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          _peripherals.remove(p);
        } else {
          _peripherals.add(p);
        }
      }),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: on
              ? Sa.violet.withValues(alpha: 0.16)
              : Sa.bgRaised.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: on ? Sa.violet : Sa.border,
            width: on ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.check_circle : Icons.add_circle_outline,
              size: 12,
              color: on ? Sa.violet : Sa.muted,
            ),
            const SizedBox(width: 5),
            Text(
              p,
              style: Sa.mono(size: 9.5, color: on ? Sa.violet : Sa.textDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(
    String key,
    ({Color color, IconData icon, String label}) st,
  ) {
    final active = _status == key;
    return InkWell(
      onTap: () => setState(() => _status = key),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? st.color.withValues(alpha: 0.16)
              : Sa.bgRaised.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? st.color : Sa.border,
            width: active ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(st.icon, size: 12, color: active ? st.color : Sa.muted),
            const SizedBox(width: 5),
            Text(
              st.label,
              style: Sa.mono(size: 9.5, color: active ? st.color : Sa.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Machine editor ─────────────────────────

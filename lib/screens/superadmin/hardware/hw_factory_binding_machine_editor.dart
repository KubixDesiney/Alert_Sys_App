part of 'hw_factory_binding.dart';

class _MachineEditor extends StatefulWidget {
  final HwFactoryCatalog catalog;
  final HwMachine? existing;
  final String? presetFactoryId;
  const _MachineEditor({
    required this.catalog,
    this.existing,
    this.presetFactoryId,
  });

  @override
  State<_MachineEditor> createState() => _MachineEditorState();
}

class _MachineEditorState extends State<_MachineEditor> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _desc;
  String? _factoryId;
  String? _conveyorId;
  late HwMachineStatus _status;

  bool get _editing => widget.existing != null;
  bool get _readonlyId => _editing || (widget.existing?.fromAsset ?? false);

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _id = TextEditingController(
      text: m?.id ?? widget.catalog.suggestNextMachineId(),
    );
    _name = TextEditingController(text: m?.name ?? '');
    _desc = TextEditingController(text: m?.description ?? '');
    final fac = m == null ? null : widget.catalog.factoryForMachine(m);
    _factoryId =
        fac?.id ??
        (m?.factoryId.isNotEmpty == true
            ? m!.factoryId
            : widget.presetFactoryId);
    final conv = m == null
        ? null
        : widget.catalog.conveyorById(_factoryId, m.conveyorId);
    _conveyorId =
        conv?.id ?? (m?.conveyorId.isNotEmpty == true ? m!.conveyorId : null);
    _status = m?.status ?? HwMachineStatus.active;
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _save() {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    final fac = widget.catalog.factories.firstWhere(
      (f) => f.id == _factoryId,
      orElse: () => const HwFactoryRef(id: '', name: ''),
    );
    final conveyors = _factoryId == null
        ? <HwConveyorRef>[]
        : widget.catalog.conveyorsFor(_factoryId!);
    final conv = conveyors.firstWhere(
      (c) => c.id == _conveyorId,
      orElse: () => HwConveyorRef(id: '', number: 0, factoryId: ''),
    );
    final m = HwMachine(
      id: id,
      name: _name.text.trim(),
      description: _desc.text.trim(),
      factoryId: fac.id,
      factoryName: fac.name,
      conveyorId: conv.id,
      conveyorNumber: conv.number,
      status: _status,
      fromAsset: widget.existing?.fromAsset ?? false,
    );
    Navigator.pop(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final conveyors = _factoryId == null
        ? <HwConveyorRef>[]
        : widget.catalog.conveyorsFor(_factoryId!);
    return Dialog(
      backgroundColor: Sa.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Sa.violet.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Sa.violet, Sa.cyan]),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.precision_manufacturing,
                        color: Sa.onAccent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editing
                                ? context.tr('Edit Machine')
                                : context.tr('Register Machine'),
                            style: Sa.heading(size: 17),
                          ),
                          Text(
                            context.tr('A MACH-XXX unit on a conveyor line'),
                            style: Sa.mono(size: 9, color: Sa.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.existing?.fromAsset == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Sa.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Sa.amber.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 15, color: Sa.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr(
                                'This is a live plant asset. Edits here are kept in the lab overlay and do not change /assets.',
                              ),
                              style: Sa.body(size: 10.5, color: Sa.textDim),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                _hwFieldLabel(context.tr('MACHINE ID')),
                TextField(
                  controller: _id,
                  enabled: !_readonlyId,
                  style: Sa.body(size: 13),
                  cursorColor: Sa.violet,
                  decoration: _hwDec(context.tr('e.g. MACH-001')),
                ),
                const SizedBox(height: 14),
                _hwFieldLabel(context.tr('NAME')),
                TextField(
                  controller: _name,
                  style: Sa.body(size: 13),
                  cursorColor: Sa.violet,
                  decoration: _hwDec(context.tr('e.g. Bottling head A')),
                ),
                const SizedBox(height: 14),
                _hwFieldLabel(context.tr('DESCRIPTION')),
                TextField(
                  controller: _desc,
                  maxLines: 3,
                  style: Sa.body(size: 13),
                  cursorColor: Sa.violet,
                  decoration: _hwDec(
                    context.tr(
                      'What this machine does, what hardware it carries…',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _hwFieldLabel(context.tr('FACTORY')),
                DropdownButtonFormField<String>(
                  initialValue:
                      widget.catalog.factories.any((f) => f.id == _factoryId)
                      ? _factoryId
                      : null,
                  isExpanded: true,
                  dropdownColor: Sa.panelSolid,
                  style: Sa.body(size: 12.5),
                  decoration: _hwDec(context.tr('Select a factory')),
                  items: [
                    for (final f in widget.catalog.factories)
                      DropdownMenuItem(value: f.id, child: Text(f.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _factoryId = v;
                    _conveyorId = null;
                  }),
                ),
                const SizedBox(height: 14),
                _hwFieldLabel(context.tr('CONVEYOR LINE')),
                DropdownButtonFormField<String>(
                  initialValue: conveyors.any((c) => c.id == _conveyorId)
                      ? _conveyorId
                      : null,
                  isExpanded: true,
                  dropdownColor: Sa.panelSolid,
                  style: Sa.body(size: 12.5),
                  decoration: _hwDec(
                    _factoryId == null
                        ? context.tr('Pick a factory first')
                        : context.tr('Select a conveyor line (optional)'),
                  ),
                  items: [
                    for (final c in conveyors)
                      DropdownMenuItem(value: c.id, child: Text(c.label)),
                  ],
                  onChanged: conveyors.isEmpty
                      ? null
                      : (v) => setState(() => _conveyorId = v),
                ),
                const SizedBox(height: 14),
                _hwFieldLabel(context.tr('STATUS')),
                Row(
                  children: [
                    _statusSeg(HwMachineStatus.active),
                    const SizedBox(width: 8),
                    _statusSeg(HwMachineStatus.outOfService),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.tr('Cancel'), style: Sa.body(color: Sa.textDim)),
                    ),
                    const SizedBox(width: 8),
                    SaButton(
                      label: _editing ? context.tr('SAVE') : context.tr('ADD MACHINE'),
                      icon: Icons.check,
                      color: Sa.violet,
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

  Widget _statusSeg(HwMachineStatus s) {
    final active = _status == s;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _status = s),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? s.color.withValues(alpha: 0.16)
                : Sa.bgRaised.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? s.color : Sa.border,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(s.icon, size: 13, color: active ? s.color : Sa.muted),
              const SizedBox(width: 6),
              Text(
                context.tr(s.label),
                style: Sa.mono(size: 9.5, color: active ? s.color : Sa.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

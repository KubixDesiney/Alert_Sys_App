import 'dart:async';

import 'package:alertsysapp/screens/superadmin/hardware/hw_machines.dart';
import 'package:alertsysapp/screens/superadmin/hardware/hw_models.dart';
import 'package:alertsysapp/screens/superadmin/superadmin_theme.dart';
import 'package:flutter/material.dart';

part 'hw_factory_binding_machine_dialog.dart';
part 'hw_factory_binding_machine_roster.dart';
part 'hw_factory_binding_cards.dart';
part 'hw_factory_binding_fields.dart';
part 'hw_factory_binding_binding_editor.dart';
part 'hw_factory_binding_machine_editor.dart';

/// Global factory machinery binding — the IT team's overall vision of which
/// boards, sensors and actuators are wired into which machine on which
/// conveyor. Each [HwDeviceBinding] ties a designed circuit to a real machine
/// (e.g. "MACH-001 ← ESP32 + heat sensor + 4 colored buttons + LED bank"),
/// where the machine + conveyor + factory are *picked from live plant
/// inventory* (the `MACH-XXX` assets) rather than typed by hand.

const List<String> kHwPeripheralPresets = [
  'Heat sensor',
  'Vibration sensor',
  'PIR motion',
  'LED indicators',
  '4 colored buttons',
  'LCD display',
  'Buzzer alarm',
  'Servo actuator',
  'Potentiometer',
];

const Map<String, ({Color color, IconData icon, String label})>
kHwBindingStatus = {
  'designed': (
    color: Color(0xFF94A3B8),
    icon: Icons.draw_outlined,
    label: 'Designed',
  ),
  'wired': (color: Color(0xFF3B82F6), icon: Icons.cable, label: 'Wired'),
  'verified': (
    color: Color(0xFFFBBF24),
    icon: Icons.verified_outlined,
    label: 'Verified',
  ),
  'live': (color: Color(0xFF34D399), icon: Icons.sensors, label: 'Live'),
};

class HwFactoryBindingView extends StatefulWidget {
  final List<HwDeviceBinding> bindings;
  final List<HwCircuit> circuits;
  final Future<void> Function(HwDeviceBinding binding) onSave;
  final Future<void> Function(String id) onDelete;

  /// Open the named circuit in the designer.
  final ValueChanged<String>? onOpenCircuit;

  const HwFactoryBindingView({
    super.key,
    required this.bindings,
    required this.circuits,
    required this.onSave,
    required this.onDelete,
    this.onOpenCircuit,
  });

  @override
  State<HwFactoryBindingView> createState() => _HwFactoryBindingViewState();
}

class _HwFactoryBindingViewState extends State<HwFactoryBindingView> {
  final HwMachineStore _store = HwMachineStore();
  HwFactoryCatalog _catalog = const HwFactoryCatalog();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final c = await _store.loadCatalog();
    if (!mounted) return;
    setState(() {
      _catalog = c;
      _loading = false;
    });
  }

  Future<void> _editBinding([HwDeviceBinding? existing]) async {
    final result = await showDialog<HwDeviceBinding>(
      context: context,
      builder: (_) => _BindingEditor(
        existing: existing,
        catalog: _catalog,
        circuits: widget.circuits,
        store: _store,
      ),
    );
    if (result != null) await widget.onSave(result);
    await _load(); // a machine may have been added inside the editor
  }

  Future<void> _addMachine() async {
    final m = await showDialog<HwMachine>(
      context: context,
      builder: (_) => _MachineEditor(catalog: _catalog),
    );
    if (m == null) return;
    await _store.saveMachine(m);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Machine ${m.id} saved'),
        backgroundColor: Sa.panelSolid,
      ),
    );
  }

  void _openMachineDetails(BuildContext anchorContext, HwMachine machine) {
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlayBox == null || anchorBox == null) return;

    final anchorRect = MatrixUtils.transformRect(
      anchorBox.getTransformTo(overlayBox),
      Offset.zero & anchorBox.size,
    );
    const width = 330.0;
    const gap = 12.0;
    const margin = 12.0;
    final overlaySize = overlayBox.size;
    final fitsRight =
        anchorRect.right + gap + width <= overlaySize.width - margin;
    final placement = fitsRight
        ? _MachinePopoverPlacement.right
        : _MachinePopoverPlacement.left;
    final maxLeft = overlaySize.width - width - margin;
    final left = fitsRight
        ? anchorRect.right + gap
        : (anchorRect.left - gap - width).clamp(
            margin,
            maxLeft < margin ? margin : maxLeft,
          );
    final maxTop = overlaySize.height - margin - 300;
    final top = (anchorRect.top - 10).clamp(
      margin,
      maxTop < margin ? margin : maxTop,
    );

    OverlayEntry? entry;
    void close() {
      entry?.remove();
      entry = null;
    }

    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: close,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left.toDouble(),
            top: top.toDouble(),
            width: width,
            child: _MachineDetailPopover(
              machine: machine,
              catalog: _catalog,
              bindings: _bindingsForMachine(machine),
              circuitNameFor: _circuitName,
              placement: placement,
              onClose: close,
              onEdit: () {
                close();
                unawaited(_editMachine(machine));
              },
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry!);
  }

  List<HwDeviceBinding> _bindingsForMachine(HwMachine machine) {
    final ids = {
      machine.id.trim().toLowerCase(),
      machine.displayName.trim().toLowerCase(),
    }..remove('');
    return widget.bindings.where((binding) {
      final label = binding.machineLabel.trim().toLowerCase();
      return ids.contains(label);
    }).toList();
  }

  Future<void> _editMachine(HwMachine machine) async {
    final m = await showDialog<HwMachine>(
      context: context,
      builder: (_) => _MachineEditor(catalog: _catalog, existing: machine),
    );
    if (m == null) return;
    await _store.saveMachine(m);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final byFactory = <String, List<HwDeviceBinding>>{};
    for (final b in widget.bindings) {
      final key = b.factoryId.trim().isEmpty ? 'Unassigned' : b.factoryId;
      byFactory.putIfAbsent(key, () => []).add(b);
    }
    final factories = byFactory.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassPanel(
            accent: Sa.cyan,
            child: Row(
              children: [
                Expanded(
                  child: SaSectionHeader(
                    icon: Icons.account_tree,
                    title: 'Factory Machinery Map',
                    subtitle:
                        '${widget.bindings.length} device${widget.bindings.length == 1 ? '' : 's'} bound · ${_catalog.machines.length} machine${_catalog.machines.length == 1 ? '' : 's'} in plant inventory',
                  ),
                ),
                SaButton(
                  label: 'ADD MACHINE',
                  icon: Icons.precision_manufacturing,
                  color: Sa.violet,
                  outlined: true,
                  onPressed: _addMachine,
                ),
                const SizedBox(width: 8),
                SaButton(
                  label: 'BIND DEVICE',
                  icon: Icons.add_link,
                  color: Sa.cyan,
                  onPressed: _editBinding,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _MachineRoster(
            loading: _loading,
            catalog: _catalog,
            onAdd: _addMachine,
            onOpen: _openMachineDetails,
          ),
          const SizedBox(height: 14),
          if (widget.bindings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: SaEmptyState(
                icon: Icons.precision_manufacturing,
                title: 'No machinery bound yet',
                message:
                    'Bind a controller + its sensors/actuators to a machine to '
                    'build the factory-wide hardware map. e.g. MACH-001 ← ESP32 '
                    'with heat sensor, LED bank and 4 colored buttons.',
              ),
            )
          else
            for (final f in factories) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                child: Row(
                  children: [
                    Icon(Icons.factory, size: 15, color: Sa.violet),
                    const SizedBox(width: 8),
                    Text(
                      f.toUpperCase(),
                      style: Sa.heading(size: 13, color: Sa.violet),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${byFactory[f]!.length}',
                      style: Sa.mono(size: 10, color: Sa.muted),
                    ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 1100
                      ? 3
                      : c.maxWidth >= 720
                      ? 2
                      : 1;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final b in byFactory[f]!)
                        SizedBox(
                          width: (c.maxWidth - (cols - 1) * 12) / cols,
                          child: _BindingCard(
                            binding: b,
                            machine: _catalog.machineById(b.machineLabel),
                            circuitName: _circuitName(b.circuitId),
                            onEdit: () => _editBinding(b),
                            onDelete: () => widget.onDelete(b.id),
                            onOpen: b.circuitId.isEmpty
                                ? null
                                : () => widget.onOpenCircuit?.call(b.circuitId),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
        ],
      ),
    );
  }

  String _circuitName(String id) {
    for (final c in widget.circuits) {
      if (c.id == id) return c.name;
    }
    return '';
  }
}

// ───────────────────────── Machine roster ─────────────────────────

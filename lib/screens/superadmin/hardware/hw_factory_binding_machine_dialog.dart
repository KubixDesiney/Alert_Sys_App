part of 'hw_factory_binding.dart';

enum _MachinePopoverPlacement { left, right }

class _MachineDetailPopover extends StatelessWidget {
  final HwMachine machine;
  final HwFactoryCatalog catalog;
  final List<HwDeviceBinding> bindings;
  final String Function(String id) circuitNameFor;
  final _MachinePopoverPlacement placement;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const _MachineDetailPopover({
    required this.machine,
    required this.catalog,
    required this.bindings,
    required this.circuitNameFor,
    required this.placement,
    required this.onClose,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final factory = catalog.factoryForMachine(machine);
    final conveyor = catalog.conveyorById(
      factory?.id ?? machine.factoryId,
      machine.conveyorId,
    );
    final location = _joinClean([
      machine.factoryName,
      factory?.name,
      conveyor?.label,
      machine.conveyorLabel,
    ]);
    final description = machine.description.trim().isEmpty
        ? 'No description recorded.'
        : machine.description.trim();
    final hardware = _hardwareSummary();

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: placement == _MachinePopoverPlacement.right ? -7 : null,
            right: placement == _MachinePopoverPlacement.left ? -7 : null,
            top: 28,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Sa.panelSolid,
                  border: Border(
                    left: placement == _MachinePopoverPlacement.right
                        ? BorderSide(color: Sa.cyan.withValues(alpha: 0.7))
                        : BorderSide.none,
                    bottom: placement == _MachinePopoverPlacement.left
                        ? BorderSide(color: Sa.cyan.withValues(alpha: 0.7))
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Sa.panelSolid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Sa.cyan.withValues(alpha: 0.58)),
              boxShadow: [
                BoxShadow(
                  color: Sa.shadow,
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Sa.cyan.withValues(alpha: 0.18),
                      Sa.blue.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      machine.status.icon,
                                      size: 15,
                                      color: machine.status.color,
                                    ),
                                    const SizedBox(width: 7),
                                    Flexible(
                                      child: Text(
                                        machine.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Sa.heading(size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                _MachineStatusPill(status: machine.status),
                              ],
                            ),
                          ),
                          _PopoverIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit machine',
                            color: Sa.amber,
                            onTap: onEdit,
                          ),
                          const SizedBox(width: 4),
                          _PopoverIconButton(
                            icon: Icons.close,
                            tooltip: 'Close',
                            color: Sa.textDim,
                            onTap: onClose,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _MachineInfoLine('ID', machine.id),
                      _MachineInfoLine('NAME', machine.displayName),
                      _MachineInfoLine('HARDWARE', hardware, maxLines: 3),
                      _MachineInfoLine(
                        'LOCATION',
                        location.isEmpty ? 'Unassigned' : location,
                      ),
                      _MachineInfoLine('STATUS', machine.status.label),
                      _MachineInfoLine('DESCRIPTION', description, maxLines: 3),
                      _MachineInfoLine(
                        'DATE',
                        _formatDateTime(machine.updatedAtMs),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hardwareSummary() {
    if (bindings.isEmpty) return 'No wired hardware.';
    return bindings
        .map((binding) {
          final parts = <String>[hwControllerLabel(binding.controllerType)];
          if (binding.peripherals.isNotEmpty) {
            parts.add(binding.peripherals.join(', '));
          }
          final circuitName = circuitNameFor(binding.circuitId);
          if (circuitName.isNotEmpty) parts.add(circuitName);
          return parts.join(' + ');
        })
        .join(' / ');
  }

  String _joinClean(List<String?> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in values) {
      final value = (raw ?? '').trim();
      final key = value.toLowerCase();
      if (value.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(value);
    }
    return out.join(' / ');
  }

  String _formatDateTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

class _MachineInfoLine extends StatelessWidget {
  final String label;
  final String value;
  final int maxLines;

  const _MachineInfoLine(this.label, this.value, {this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: Sa.mono(size: 8.5, color: Sa.muted)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: Sa.body(size: 11.5, color: Sa.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopoverIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _PopoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

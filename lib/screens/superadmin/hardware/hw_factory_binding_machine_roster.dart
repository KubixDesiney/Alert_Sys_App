part of 'hw_factory_binding.dart';

typedef _MachineOpenCallback =
    void Function(BuildContext context, HwMachine machine);

class _MachineRoster extends StatelessWidget {
  final bool loading;
  final HwFactoryCatalog catalog;
  final VoidCallback onAdd;
  final _MachineOpenCallback onOpen;
  const _MachineRoster({
    required this.loading,
    required this.catalog,
    required this.onAdd,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accent: Sa.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.view_in_ar, size: 16, color: Sa.violet),
              const SizedBox(width: 8),
              Text(
                context.tr('PLANT MACHINES'),
                style: Sa.mono(size: 10, color: Sa.violet),
              ),
              const Spacer(),
              Text(
                context.tr('MACH-XXX · read from /assets + lab'),
                style: Sa.mono(size: 8, color: Sa.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Sa.violet,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (catalog.machines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                context.tr(
                  'No machines found yet. Add one, or create stations in the factory hierarchy — their MACH-XXX assets appear here.',
                ),
                style: Sa.body(size: 11.5, color: Sa.muted),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in catalog.machines)
                  _MachineChip(machine: m, onTap: (ctx) => onOpen(ctx, m)),
              ],
            ),
        ],
      ),
    );
  }
}

class _MachineChip extends StatefulWidget {
  final HwMachine machine;
  final ValueChanged<BuildContext> onTap;
  const _MachineChip({required this.machine, required this.onTap});

  @override
  State<_MachineChip> createState() => _MachineChipState();
}

class _MachineChipState extends State<_MachineChip> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final machine = widget.machine;
    final st = machine.status;
    final dim = st == HwMachineStatus.deleted;
    return InkWell(
      onTap: () => widget.onTap(_anchorKey.currentContext ?? context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        key: _anchorKey,
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Sa.bgRaised.withValues(alpha: dim ? 0.35 : 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: st.color.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  machine.fromAsset
                      ? Icons.precision_manufacturing
                      : Icons.add_box,
                  size: 13,
                  color: Sa.cyan,
                ),
                const SizedBox(width: 6),
                Text(
                  machine.id,
                  style: Sa.mono(
                    size: 10.5,
                    color: Sa.text,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                _MachineStatusPill(status: st),
              ],
            ),
            if (machine.displayName != machine.id) ...[
              const SizedBox(height: 3),
              Text(
                machine.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Sa.body(size: 11, color: Sa.textDim),
              ),
            ],
            if (machine.factoryName.isNotEmpty ||
                machine.conveyorLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [
                    if (machine.factoryName.isNotEmpty) machine.factoryName,
                    if (machine.conveyorLabel.isNotEmpty) machine.conveyorLabel,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Sa.mono(size: 8.5, color: Sa.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MachineStatusPill extends StatelessWidget {
  final HwMachineStatus status;
  const _MachineStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: status.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 9, color: status.color),
          const SizedBox(width: 4),
          Text(
            context.tr(status.label),
            style: Sa.mono(
              size: 7.5,
              color: status.color,
              weight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Binding card ─────────────────────────

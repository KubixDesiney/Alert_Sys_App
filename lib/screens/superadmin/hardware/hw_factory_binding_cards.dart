part of 'hw_factory_binding.dart';

class _BindingCard extends StatelessWidget {
  final HwDeviceBinding binding;
  final HwMachine? machine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BindingCard({
    required this.binding,
    required this.machine,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final st =
        kHwBindingStatus[binding.status] ?? kHwBindingStatus['designed']!;
    return GlassPanel(
      accent: st.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Sa.cyan.withValues(alpha: 0.25),
                      Sa.violet.withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Sa.cyan.withValues(alpha: 0.4)),
                ),
                child: Icon(Icons.memory, size: 17, color: Sa.cyan),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            binding.machineLabel.isEmpty
                                ? context.tr('Unnamed machine')
                                : binding.machineLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Sa.heading(size: 14),
                          ),
                        ),
                        if (machine != null) ...[
                          const SizedBox(width: 8),
                          _MachineStatusPill(status: machine!.status),
                        ],
                      ],
                    ),
                    Text(
                      [
                        if (machine != null &&
                            machine!.displayName != machine!.id)
                          machine!.displayName,
                        if (binding.conveyor.isNotEmpty) binding.conveyor,
                        hwControllerLabel(binding.controllerType),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Sa.mono(size: 9.5, color: Sa.muted),
                    ),
                  ],
                ),
              ),
              _StatusPill(st: st),
            ],
          ),
          const SizedBox(height: 12),
          // Connection: controller → peripherals.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Sa.bgRaised.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Sa.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.developer_board, size: 13, color: Sa.cyan),
                    const SizedBox(width: 6),
                    Text(
                      hwControllerLabel(binding.controllerType),
                      style: Sa.mono(size: 10, color: Sa.text),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward, size: 12, color: Sa.muted),
                  ],
                ),
                if (binding.peripherals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: binding.peripherals
                        .map(
                          (p) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Sa.violet.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Sa.violet.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              p,
                              style: Sa.mono(size: 9, color: Sa.violet),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      context.tr('No peripherals listed'),
                      style: Sa.body(size: 10.5, color: Sa.muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              _MiniBtn(
                icon: Icons.edit_outlined,
                color: Sa.amber,
                onTap: onEdit,
              ),
              const SizedBox(width: 4),
              _MiniBtn(
                icon: Icons.delete_outline,
                color: Sa.red,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ({Color color, IconData icon, String label}) st;
  const _StatusPill({required this.st});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: st.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(st.icon, size: 11, color: st.color),
          const SizedBox(width: 5),
          Text(
            context.tr(st.label).toUpperCase(),
            style: Sa.mono(size: 8.5, color: st.color, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MiniBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}

// ───────────────────────── Shared input decoration ─────────────────────────

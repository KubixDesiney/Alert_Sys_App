import 'package:flutter/material.dart';

import '../../models/alert_model.dart';
import '../../theme.dart';

/// One station tile shown in the heatmap.
class HeatmapCell {
  final String factoryName;
  final int conveyor;
  final int station;
  final String label;
  final String? assetId;
  final int activeCount;
  final int inProgressCount;
  final int criticalCount;
  final AlertModel? topAlert;

  const HeatmapCell({
    required this.factoryName,
    required this.conveyor,
    required this.station,
    required this.label,
    this.assetId,
    required this.activeCount,
    this.inProgressCount = 0,
    required this.criticalCount,
    required this.topAlert,
  });

  /// Intensity used to colour the tile. critical alerts count double.
  double get intensity => activeCount + criticalCount * 2.0;
}

/// Grid of every station coloured by alert intensity. Tap a hot tile to open
/// the same alert sheet used in the tree view.
class TreeHeatmapView extends StatelessWidget {
  final List<HeatmapCell> cells;
  final void Function(HeatmapCell cell) onStationTap;
  final String? scopeLabel;

  const TreeHeatmapView({
    super.key,
    required this.cells,
    required this.onStationTap,
    this.scopeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    if (cells.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_off, size: 36, color: t.muted),
              const SizedBox(height: 8),
              Text(
                'No stations to display.',
                style: TextStyle(color: t.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final maxIntensity =
        cells.map((c) => c.intensity).fold<double>(0, (a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = (width / 96).floor().clamp(2, 8);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _legendRow(t),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemBuilder: (_, i) => _Tile(
                cell: cells[i],
                maxIntensity: maxIntensity,
                onTap: () => onStationTap(cells[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _legendRow(AppTheme t) {
    return Row(
      children: [
        Icon(Icons.grid_view_rounded, size: 16, color: t.navy),
        const SizedBox(width: 8),
        Text(
          scopeLabel == null
              ? 'Heatmap of all stations'
              : 'Heatmap — $scopeLabel',
          style: TextStyle(
            color: t.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        _legendStop(t.scaffold, 'Quiet', t),
        const SizedBox(width: 4),
        _legendStop(t.red, 'Unclaimed', t),
        const SizedBox(width: 4),
        _legendStop(t.yellow, 'Claimed', t),
      ],
    );
  }

  Widget _legendStop(Color c, String label, AppTheme t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: t.border, width: 0.6),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: t.muted)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final HeatmapCell cell;
  final double maxIntensity;
  final VoidCallback onTap;

  const _Tile({
    required this.cell,
    required this.maxIntensity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final ratio =
        maxIntensity > 0 ? (cell.intensity / maxIntensity).clamp(0, 1) : 0.0;

    final Color color;
    final unclaimedCount =
        (cell.activeCount - cell.inProgressCount).clamp(0, cell.activeCount);
    if (cell.intensity == 0) {
      color = t.scaffold;
    } else if (unclaimedCount > 0) {
      color = Color.lerp(t.redLt, t.red, ratio.toDouble()) ?? t.red;
    } else {
      color = Color.lerp(t.yellowLt, t.yellow, ratio.toDouble()) ?? t.yellow;
    }
    final fg = cell.intensity == 0 ? t.muted : Colors.white;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: cell.intensity == 0
                    ? t.border
                    : Colors.black.withValues(alpha: 0.05)),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cell.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'C${cell.conveyor} · P${cell.station}',
                style: TextStyle(
                  fontSize: 10,
                  color: cell.intensity == 0
                      ? t.muted
                      : Colors.white.withValues(alpha: 0.85),
                ),
              ),
              if (cell.assetId != null && cell.assetId!.trim().isNotEmpty)
                Text(
                  cell.assetId!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: cell.intensity == 0
                        ? t.muted
                        : Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const Spacer(),
              if (cell.activeCount > 0 || cell.criticalCount > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      unclaimedCount > 0
                          ? Icons.local_fire_department
                          : Icons.autorenew,
                      size: 12,
                      color: fg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unclaimedCount > 0
                          ? '$unclaimedCount open'
                          : '${cell.inProgressCount} fixing',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

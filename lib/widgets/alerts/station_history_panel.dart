import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/alert_model.dart';
import '../../screens/widgets/tree_alert_sheet.dart';
import '../../theme.dart';
import '../../utils/alert_meta.dart';

/// Asset-id chip rendered above the station history list.
class AssetChip extends StatelessWidget {
  final AppTheme t;
  final String assetId;

  const AssetChip({super.key, required this.t, required this.assetId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.navyLt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.navy.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.precision_manufacturing_outlined, size: 13, color: t.navy),
          const SizedBox(width: 5),
          SelectableText(
            assetId,
            style: TextStyle(
              color: t.navy,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty-state row shown when a workstation has no recorded alerts.
class StationEmptyHistory extends StatelessWidget {
  final AppTheme t;
  const StationEmptyHistory({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.scaffold,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, color: t.muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No alerts have been recorded at this workstation yet.',
              style: TextStyle(color: t.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single row in the workstation alert history list. Tapping opens the alert
/// detail bottom sheet.
class StationHistoryTile extends StatelessWidget {
  final AlertModel alert;
  const StationHistoryTile({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final type = typeMeta(alert.type, t);
    final status = statusMeta(alert.status, t);
    return Material(
      color: t.scaffold,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showTreeAlertSheet(context, alert),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: type.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(type.icon, color: type.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM d, h:mm a').format(alert.timestamp),
                      style: TextStyle(color: t.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: status.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated, glowing green dot used in the live status header.
class LivePulseDot extends StatefulWidget {
  final Color color;
  const LivePulseDot({super.key, required this.color});

  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.15 + v * 0.1),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5),
                      blurRadius: 6 + v * 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

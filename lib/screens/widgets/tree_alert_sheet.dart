import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/alert_model.dart';
import '../../theme.dart';
import '../../utils/alert_meta.dart';
import '../alert_detail_screen.dart';

/// Modal bottom sheet showing rich detail for a single alert. Replaces the
/// in-stack floating popup of the legacy tree.
Future<void> showTreeAlertSheet(BuildContext context, AlertModel alert) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => _TreeAlertSheet(
        alert: alert,
        scrollController: controller,
      ),
    ),
  );
}

class _TreeAlertSheet extends StatelessWidget {
  final AlertModel alert;
  final ScrollController scrollController;
  const _TreeAlertSheet({required this.alert, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final type = typeMeta(alert.type, t);
    final status = statusMeta(alert.status, t);

    return Material(
      color: t.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(height: 3, color: type.color),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  _header(t, type, status),
                  const SizedBox(height: 12),
                  if (alert.description.isNotEmpty) ...[
                    _section(t, 'Description'),
                    const SizedBox(height: 4),
                    Text(
                      alert.description,
                      style:
                          TextStyle(color: t.text, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _section(t, 'Location & Timing'),
                  const SizedBox(height: 6),
                  _wrap([
                    if (alert.assetId != null && alert.assetId!.isNotEmpty)
                      _chip(t, Icons.precision_manufacturing_outlined,
                          alert.assetId!,
                          tone: t.navy),
                    _chip(t, Icons.factory, alert.usine),
                    _chip(t, Icons.linear_scale, 'Conveyor ${alert.convoyeur}'),
                    _chip(t, Icons.settings, 'Post ${alert.poste}'),
                    _chip(t, Icons.event, _formatDateTime(alert.timestamp)),
                    _chip(t, Icons.schedule, _relativeTime(alert.timestamp)),
                    if (alert.takenAtTimestamp != null)
                      _chip(t, Icons.play_circle_outline,
                          'Taken ${DateFormat('h:mm a').format(alert.takenAtTimestamp!)}'),
                    if (alert.elapsedTime != null && alert.elapsedTime! > 0)
                      _chip(t, Icons.timer_outlined,
                          _formatElapsed(alert.elapsedTime!),
                          tone: t.green),
                    if (alert.isEscalated)
                      _chip(t, Icons.trending_up, 'Escalated', tone: t.orange),
                  ]),
                  const SizedBox(height: 14),
                  if (alert.superviseurName != null ||
                      alert.assistantName != null) ...[
                    _section(t, 'People'),
                    const SizedBox(height: 6),
                    if (alert.superviseurName != null)
                      _personRow(t, Icons.person, 'Supervisor',
                          alert.superviseurName!),
                    if (alert.assistantName != null)
                      _personRow(t, Icons.handshake, 'Assistant',
                          alert.assistantName!),
                    const SizedBox(height: 14),
                  ],
                  if (alert.aiAssigned) ...[
                    _section(t, 'AI Assignment'),
                    const SizedBox(height: 6),
                    _aiBlock(t),
                    const SizedBox(height: 14),
                  ],
                  if (alert.resolutionReason != null &&
                      alert.resolutionReason!.trim().isNotEmpty) ...[
                    _section(t, 'Resolution'),
                    const SizedBox(height: 6),
                    _resolutionBlock(t),
                    const SizedBox(height: 14),
                  ],
                  if (alert.comments.isNotEmpty) ...[
                    _section(t, 'Comments (${alert.comments.length})'),
                    const SizedBox(height: 6),
                    ...alert.comments.map((c) => _commentRow(t, c)),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AlertDetailScreen(alertId: alert.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open Full Details'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppTheme t, AlertMeta type, AlertMeta status) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: type.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(type.icon, color: type.color, size: 22),
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
                      type.label,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (alert.isCritical) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.local_fire_department, size: 16, color: t.red),
                  ],
                  if (alert.aiAssigned) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.auto_awesome, size: 14, color: t.purple),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${alert.alertLabel} · ${_shortId(alert.id)}',
                style: TextStyle(
                  color: t.muted,
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: status.bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: status.color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status.icon, size: 12, color: status.color),
              const SizedBox(width: 4),
              Text(
                status.label,
                style: TextStyle(
                  color: status.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(AppTheme t, String label) => Text(
        label.toUpperCase(),
        style: TextStyle(
          color: t.muted,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      );

  Widget _wrap(List<Widget> children) =>
      Wrap(spacing: 6, runSpacing: 6, children: children);

  Widget _chip(AppTheme t, IconData icon, String label, {Color? tone}) {
    final c = tone ?? t.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.scaffold,
        border: Border.all(color: t.border, width: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _personRow(AppTheme t, IconData icon, String role, String name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: t.navyLt,
            child: Icon(icon, size: 14, color: t.navy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                      color: t.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                Text(role, style: TextStyle(color: t.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiBlock(AppTheme t) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.purple.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: t.purple),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Auto-assigned',
                      style: TextStyle(
                        color: t.purple,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (alert.aiConfidence != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${(alert.aiConfidence! * 100).toStringAsFixed(0)}% confidence',
                        style: TextStyle(
                          color: t.purple,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (alert.aiAssignmentReason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    alert.aiAssignmentReason!,
                    style: TextStyle(color: t.text, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resolutionBlock(AppTheme t) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.greenLt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: t.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Resolved',
                      style: TextStyle(
                        color: t.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (alert.resolvedAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM d, h:mm a').format(alert.resolvedAt!),
                        style: TextStyle(
                          color: t.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  alert.resolutionReason!,
                  style: TextStyle(color: t.text, fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentRow(AppTheme t, String comment) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.chat_bubble_outline, size: 12, color: t.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              comment,
              style: TextStyle(color: t.text, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  String _shortId(String id) => id.length <= 8
      ? id
      : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    return DateFormat(
            dt.year == now.year ? 'MMM d, h:mm a' : 'MMM d yyyy, h:mm a')
        .format(dt);
  }

  String _relativeTime(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()}w ago';
    if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo ago';
    return '${(d.inDays / 365).floor()}y ago';
  }

  String _formatElapsed(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}min' : '${h}h';
  }
}

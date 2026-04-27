// lib/widgets/ai_logs_panel.dart
//
// Theme-aware movable popup that shows the live AI assignment activity feed.
// Each log entry has Details and Abort actions. Designed to feel like a small
// chat-style activity panel docked to the right of the Alerts tab.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';

import '../services/ai_assignment_service.dart';
import '../theme.dart';
import '../screens/alert_detail_screen.dart';

class AILogsPanel extends StatefulWidget {
  final VoidCallback onClose;
  final Size hostSize;

  const AILogsPanel({
    super.key,
    required this.onClose,
    required this.hostSize,
  });

  @override
  State<AILogsPanel> createState() => _AILogsPanelState();
}

class _AILogsPanelState extends State<AILogsPanel> {
  static const double _panelWidth = 340;
  static const double _panelHeight = 480;

  late Offset _position;

  @override
  void initState() {
    super.initState();
    // Default: docked top-right with a small inset.
    _position = Offset(
      (widget.hostSize.width - _panelWidth - 16).clamp(0, double.infinity),
      80,
    );
    AIAssignmentService.instance.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant AILogsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hostSize != widget.hostSize) {
      _position = Offset(
        _position.dx.clamp(0.0,
            (widget.hostSize.width - _panelWidth).clamp(0, double.infinity)),
        _position.dy.clamp(0.0,
            (widget.hostSize.height - _panelHeight).clamp(0, double.infinity)),
      );
    }
  }

  @override
  void dispose() {
    AIAssignmentService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _handleDrag(DragUpdateDetails d) {
    setState(() {
      final maxX =
          (widget.hostSize.width - _panelWidth).clamp(0.0, double.infinity);
      final maxY =
          (widget.hostSize.height - _panelHeight).clamp(0.0, double.infinity);
      _position = Offset(
        (_position.dx + d.delta.dx).clamp(0.0, maxX),
        (_position.dy + d.delta.dy).clamp(0.0, maxY),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final logs = AIAssignmentService.instance.logs;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Material(
        elevation: 12,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: _panelWidth,
          height: _panelHeight,
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(context.isDark ? 0.5 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(t),
              Expanded(child: _buildBody(t, logs)),
              _buildFooter(t, logs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppTheme t) {
    return GestureDetector(
      onPanUpdate: _handleDrag,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.navyLt,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: t.navy,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smart_toy_outlined,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Activity',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: t.navy),
                    ),
                    Text(
                      AIAssignmentService.instance.enabled
                          ? 'Live · auto-assigning'
                          : 'Idle · AI off',
                      style: TextStyle(fontSize: 10, color: t.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.drag_indicator, size: 16, color: t.muted),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'AI settings — enable/disable per factory',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _AISettingsDialog(),
                ),
                icon: Icon(Icons.settings_outlined, size: 18, color: t.muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                tooltip: 'Close panel',
                onPressed: widget.onClose,
                icon: Icon(Icons.close, size: 18, color: t.muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppTheme t, List<AILogEntry> logs) {
    if (logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 36, color: t.muted),
              const SizedBox(height: 8),
              Text(
                'No AI activity yet',
                style: TextStyle(
                    fontSize: 13, color: t.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Turn AI ON and new alerts will be auto-assigned here.',
                style: TextStyle(fontSize: 11, color: t.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _LogTile(entry: logs[i]),
    );
  }

  Widget _buildFooter(AppTheme t, List<AILogEntry> logs) {
    final success = logs.where((l) => l.status == AILogStatus.success).length;
    final skipped = logs.where((l) => l.status == AILogStatus.skipped).length;
    final recommended =
        logs.where((l) => l.status == AILogStatus.recommended).length;
    final aborted = logs.where((l) => l.status == AILogStatus.aborted).length;
    final rejected = logs.where((l) => l.status == AILogStatus.rejected).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.scaffold,
        border: Border(top: BorderSide(color: t.border)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          _statChip(t, Icons.check_circle, t.green, '$success', 'OK'),
          const SizedBox(width: 6),
          _statChip(t, Icons.skip_next, t.muted, '$skipped', 'Skip'),
          const SizedBox(width: 6),
          _statChip(t, Icons.recommend_outlined, t.blue, '$recommended', 'Rec'),
          const SizedBox(width: 6),
          _statChip(t, Icons.stop_circle, t.orange, '$aborted', 'Abort'),
          const SizedBox(width: 6),
          _statChip(t, Icons.thumb_down_outlined, t.red, '$rejected', 'Rej'),
          const Spacer(),
          IconButton(
            tooltip: 'Clear logs',
            onPressed: logs.isEmpty
                ? null
                : () => AIAssignmentService.instance.clearLogs(),
            icon: Icon(Icons.delete_outline, size: 18, color: t.muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _statChip(
      AppTheme t, IconData icon, Color color, String count, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(count,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final AILogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final accent = _statusColor(entry.status, t);
    final time = DateFormat('HH:mm:ss').format(entry.timestamp);

    return Container(
      decoration: BoxDecoration(
        color: t.scaffold,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Icon(_statusIcon(entry.status), size: 14, color: accent),
                const SizedBox(width: 6),
                Text(
                  _statusLabel(entry.status),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(time,
                    style: TextStyle(
                        fontSize: 10, color: t.muted, fontFamily: 'monospace')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.alertLabel,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: t.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (entry.assignedSupervisorName != null)
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: t.navy),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Assigned: ${entry.assignedSupervisorName}',
                          style: TextStyle(
                              fontSize: 11,
                              color: t.navy,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.confidence > 0)
                        _ConfidenceBadge(confidence: entry.confidence),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  entry.reason,
                  style: TextStyle(fontSize: 11, color: t.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.rejectionReason != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.redLt,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Rejected: ${entry.rejectionReason}',
                      style: TextStyle(
                          fontSize: 10,
                          color: t.red,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showDetails(context),
                        icon: Icon(Icons.info_outline, size: 14, color: t.navy),
                        label: Text('Details',
                            style: TextStyle(
                                fontSize: 11,
                                color: t.navy,
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 6),
                          side: BorderSide(color: t.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    if (entry.status == AILogStatus.success) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _confirmAbort(context),
                          icon: const Icon(Icons.stop_circle_outlined,
                              size: 14, color: Colors.white),
                          label: const Text('Abort',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.orange,
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AIDetailsDialog(entry: entry),
    );
  }

  Future<void> _confirmAbort(BuildContext context) async {
    final t = context.appTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Abort AI assignment?'),
        content: Text(
          'This will remove ${entry.assignedSupervisorName ?? "the supervisor"} '
          'from "${entry.alertLabel}" and return the alert to the queue. '
          'AI will keep running for future alerts.',
          style: TextStyle(color: t.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(backgroundColor: t.orange),
            child: const Text('Abort', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AIAssignmentService.instance.abort(entry.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('AI assignment aborted — alert returned to queue'),
            backgroundColor: t.orange,
          ),
        );
      }
    }
  }

  Color _statusColor(AILogStatus s, AppTheme t) {
    switch (s) {
      case AILogStatus.success:
        return t.green;
      case AILogStatus.skipped:
        return t.muted;
      case AILogStatus.recommended:
        return t.blue;
      case AILogStatus.aborted:
        return t.orange;
      case AILogStatus.rejected:
        return t.red;
    }
  }

  IconData _statusIcon(AILogStatus s) {
    switch (s) {
      case AILogStatus.success:
        return Icons.check_circle;
      case AILogStatus.skipped:
        return Icons.skip_next;
      case AILogStatus.recommended:
        return Icons.recommend_outlined;
      case AILogStatus.aborted:
        return Icons.stop_circle_outlined;
      case AILogStatus.rejected:
        return Icons.thumb_down_outlined;
    }
  }

  String _statusLabel(AILogStatus s) {
    switch (s) {
      case AILogStatus.success:
        return 'ASSIGNED';
      case AILogStatus.skipped:
        return 'SKIPPED';
      case AILogStatus.recommended:
        return 'RECOMMENDED';
      case AILogStatus.aborted:
        return 'ABORTED';
      case AILogStatus.rejected:
        return 'REJECTED';
    }
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final pct = (confidence * 100).round();
    final label = AIAssignmentService.confidenceLabel(confidence);
    final color = pct >= 85
        ? t.green
        : (pct >= 70 ? t.blue : (pct >= 50 ? t.orange : t.red));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$pct% • $label',
        style:
            TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _AIDetailsDialog extends StatelessWidget {
  final AILogEntry entry;
  const _AIDetailsDialog({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final whyOthers = entry.consideredCandidates
        .where((c) => c.supervisor.id != entry.assignedSupervisorId)
        .toList();

    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.smart_toy_outlined, size: 22, color: t.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI Decision Snapshot',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.text),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(t, 'Alert', entry.alertLabel),
                    const SizedBox(height: 6),
                    if (entry.assignedSupervisorName != null)
                      _section(t, 'Assigned to', entry.assignedSupervisorName!),
                    if (entry.confidence > 0)
                      _section(t, 'Confidence',
                          '${(entry.confidence * 100).round()}% • ${AIAssignmentService.confidenceLabel(entry.confidence)}'),
                    if (entry.confidence > 0)
                      _section(
                        t,
                        'Confidence scale',
                        AIAssignmentService.confidenceScaleDescription(
                            entry.confidence),
                      ),
                    _section(t, 'Status', entry.status.name.toUpperCase()),
                    if (entry.rejectionReason != null)
                      _section(t, 'Rejection reason', entry.rejectionReason!),
                    const SizedBox(height: 14),
                    if (entry.reasonBreakdown.isNotEmpty) ...[
                      _heading(t, 'Why this supervisor'),
                      const SizedBox(height: 6),
                      ...entry.reasonBreakdown.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check, size: 14, color: t.green),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(r,
                                      style: TextStyle(
                                          fontSize: 12, color: t.text)),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 14),
                    ],
                    if (whyOthers.isNotEmpty) ...[
                      _heading(t, 'Why not others'),
                      const SizedBox(height: 6),
                      ...whyOthers.map((c) {
                        final detail = c.skipReason ??
                            'Score ${c.score.toStringAsFixed(0)} (vs winner ${(entry.consideredCandidates.firstWhere((x) => x.supervisor.id == entry.assignedSupervisorId, orElse: () => c).score).toStringAsFixed(0)})';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: t.scaffold,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: t.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.supervisor.fullName,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: t.text)),
                                const SizedBox(height: 2),
                                Text(detail,
                                    style: TextStyle(
                                        fontSize: 11, color: t.muted)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: t.scaffold,
                border: Border(top: BorderSide(color: t.border)),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AlertDetailScreen(alertId: entry.alertId),
                        ),
                      );
                    },
                    icon: Icon(Icons.open_in_new, size: 16, color: t.navy),
                    label: Text('Open alert', style: TextStyle(color: t.navy)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(AppTheme t, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                  fontSize: 12, color: t.muted, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: 12, color: t.text, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      );

  Widget _heading(AppTheme t, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            color: t.muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6),
      );
}

// ---------------------------------------------------------------------------
// AI Settings dialog — per-factory AI enable/disable
// ---------------------------------------------------------------------------

class _FactoryConfig {
  final String id;
  final String name;
  bool enabled;
  bool saving = false;

  _FactoryConfig({
    required this.id,
    required this.name,
    required this.enabled,
  });
}

class _AISettingsDialog extends StatefulWidget {
  const _AISettingsDialog();

  @override
  State<_AISettingsDialog> createState() => _AISettingsDialogState();
}

class _AISettingsDialogState extends State<_AISettingsDialog> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  List<_FactoryConfig> _factories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFactories();
  }

  Future<void> _loadFactories() async {
    try {
      // Load factory definitions from hierarchy
      final hierarchySnap = await _db.child('hierarchy/factories').get();
      if (!hierarchySnap.exists || hierarchySnap.value == null) {
        setState(() {
          _loading = false;
          _error = 'No factories found in hierarchy.';
        });
        return;
      }

      final hierarchyMap =
          Map<String, dynamic>.from(hierarchySnap.value as Map);

      // Load AI enabled flag for each factory in parallel
      final configs = await Future.wait(
        hierarchyMap.entries.map((e) async {
          final factoryId = e.key;
          final factoryData = e.value is Map
              ? Map<String, dynamic>.from(e.value as Map)
              : <String, dynamic>{};
          final name = factoryData['name']?.toString() ?? factoryId;

          bool enabled = false;
          try {
            final enabledSnap =
                await _db.child('factories/$factoryId/aiConfig/enabled').get();
            if (enabledSnap.exists) {
              enabled = enabledSnap.value == true;
            }
          } catch (_) {}

          return _FactoryConfig(id: factoryId, name: name, enabled: enabled);
        }),
      );

      // Sort by name for consistent display
      configs.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _factories = configs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load factories: $e';
      });
    }
  }

  Future<void> _toggle(_FactoryConfig cfg, bool value) async {
    setState(() => cfg.saving = true);
    try {
      await _db.child('factories/${cfg.id}/aiConfig').update({
        'enabled': value,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      setState(() {
        cfg.enabled = value;
        cfg.saving = false;
      });
    } catch (e) {
      setState(() => cfg.saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: t.navy,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings_outlined,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI Assignment Settings',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: t.text)),
                        Text('Enable auto-assignment per factory',
                            style: TextStyle(fontSize: 11, color: t.muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 20, color: t.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: t.border),
            // Body
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_error!,
                              style:
                                  TextStyle(color: t.muted, fontSize: 13)),
                        )
                      : _factories.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text('No factories configured.',
                                  style: TextStyle(
                                      color: t.muted, fontSize: 13)),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _factories.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: t.border),
                              itemBuilder: (_, i) {
                                final cfg = _factories[i];
                                return SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 4),
                                  title: Text(cfg.name,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: t.text)),
                                  subtitle: Text(
                                    cfg.enabled
                                        ? 'AI auto-assignment ON'
                                        : 'AI auto-assignment OFF',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cfg.enabled
                                            ? t.green
                                            : t.muted),
                                  ),
                                  secondary: cfg.saving
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: t.navy),
                                        )
                                      : Icon(
                                          cfg.enabled
                                              ? Icons.smart_toy
                                              : Icons.smart_toy_outlined,
                                          color: cfg.enabled
                                              ? t.navy
                                              : t.muted,
                                          size: 22,
                                        ),
                                  value: cfg.enabled,
                                  onChanged: cfg.saving
                                      ? null
                                      : (v) => _toggle(cfg, v),
                                  activeThumbColor: t.navy,
                                );
                              },
                            ),
            ),
            // Footer note
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: t.scaffold,
                border: Border(top: BorderSide(color: t.border)),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: t.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Supervisors must have status "active" and no active alert to be eligible.',
                      style: TextStyle(fontSize: 10, color: t.muted),
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
}

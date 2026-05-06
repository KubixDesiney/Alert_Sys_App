// lib/widgets/shifts/shift_logs_panel.dart
//
// Movable popup showing live AI Commander action logs for a specific shift.
// Each entry carries an actionID, kind badge, timestamp, and context details.
// Follows the same drag-to-move pattern as AILogsPanel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../../models/shift_model.dart';
import '../../theme.dart';
import '../common/app_loading_indicator.dart';

class ShiftLogsPanel extends StatefulWidget {
  final ShiftModel shift;
  final VoidCallback onClose;
  final Size hostSize;

  const ShiftLogsPanel({
    super.key,
    required this.shift,
    required this.onClose,
    required this.hostSize,
  });

  @override
  State<ShiftLogsPanel> createState() => _ShiftLogsPanelState();
}

class _ShiftLogsPanelState extends State<ShiftLogsPanel> {
  static const double _w = 360;
  static const double _h = 500;

  late Offset _position;
  StreamSubscription? _sub;
  List<ShiftLogEntry> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _position = Offset(
      (widget.hostSize.width - _w - 16).clamp(0, double.infinity),
      80,
    );
    _subscribe(widget.shift.id);
  }

  void _subscribe(String shiftId) {
    _sub?.cancel();
    setState(() {
      _logs = [];
      _loading = true;
    });
    _sub = FirebaseDatabase.instance
        .ref('shift_ai_logs/$shiftId')
        .onValue
        .listen(
      (event) {
        final raw = event.snapshot.value;
        final list = <ShiftLogEntry>[];
        if (raw is Map) {
          for (final entry in raw.entries) {
            if (entry.value is Map) {
              list.add(ShiftLogEntry.fromMap(
                entry.key.toString(),
                Map<String, dynamic>.from(entry.value as Map),
              ));
            }
          }
        }
        list.sort((a, b) => b.at.compareTo(a.at));
        if (mounted) setState(() { _logs = list; _loading = false; });
      },
      onError: (_) { if (mounted) setState(() => _loading = false); },
    );
  }

  @override
  void didUpdateWidget(covariant ShiftLogsPanel old) {
    super.didUpdateWidget(old);
    if (old.shift.id != widget.shift.id) _subscribe(widget.shift.id);
    if (old.hostSize != widget.hostSize) {
      setState(() {
        _position = Offset(
          _position.dx.clamp(0.0, (widget.hostSize.width - _w).clamp(0, double.infinity)),
          _position.dy.clamp(0.0, (widget.hostSize.height - _h).clamp(0, double.infinity)),
        );
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _handleDrag(DragUpdateDetails d) {
    setState(() {
      _position = Offset(
        (_position.dx + d.delta.dx).clamp(0.0, (widget.hostSize.width - _w).clamp(0.0, double.infinity)),
        (_position.dy + d.delta.dy).clamp(0.0, (widget.hostSize.height - _h).clamp(0.0, double.infinity)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Material(
        elevation: 12,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: _w,
          height: _h,
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(t),
              Expanded(child: _buildBody(t)),
              _buildFooter(t),
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF60A5FA), Color(0xFFC084FC)],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Commander Logs',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      widget.shift.name,
                      style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.drag_indicator, size: 16, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: Icon(Icons.close, size: 18, color: Colors.white.withValues(alpha: 0.9)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppTheme t) {
    if (_loading) {
      return const AppLoadingIndicator();
    }
    if (_logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_toggle_off, size: 36, color: t.muted),
              const SizedBox(height: 8),
              Text(
                'No commander actions yet',
                style: TextStyle(
                  fontSize: 13,
                  color: t.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Actions appear here as the AI Commander runs during the shift.',
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
      itemCount: _logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ShiftLogTile(entry: _logs[i]),
    );
  }

  Widget _buildFooter(AppTheme t) {
    final assigned = _logs.where((l) => l.kind == 'assigned').length;
    final skipped  = _logs.where((l) => l.kind == 'skipped').length;
    final handover = _logs.where((l) => l.kind == 'handover').length;
    final other    = _logs.length - assigned - skipped - handover;

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
          _statChip(t, Icons.check_circle_outline, t.green, '$assigned', 'Assigned'),
          const SizedBox(width: 5),
          _statChip(t, Icons.skip_next, t.muted, '$skipped', 'Skipped'),
          const SizedBox(width: 5),
          _statChip(t, Icons.swap_horiz, const Color(0xFF60A5FA), '$handover', 'Handover'),
          if (other > 0) ...[
            const SizedBox(width: 5),
            _statChip(t, Icons.bolt, t.orange, '$other', 'Other'),
          ],
          const Spacer(),
          if (_logs.isNotEmpty)
            IconButton(
              tooltip: 'Clear all logs',
              onPressed: () => FirebaseDatabase.instance
                  .ref('shift_ai_logs/${widget.shift.id}')
                  .remove(),
              icon: Icon(Icons.delete_outline, size: 18, color: t.muted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _statChip(AppTheme t, IconData icon, Color color, String count, String label) {
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              count,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Log tile ────────────────────────────────────────────────────────────────

class _ShiftLogTile extends StatelessWidget {
  final ShiftLogEntry entry;
  const _ShiftLogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final accent = _kindColor(entry.kind, t);
    final time = DateFormat('HH:mm:ss').format(entry.at);
    final shortId = entry.id.length > 8 ? entry.id.substring(0, 8) : entry.id;

    return Container(
      decoration: BoxDecoration(
        color: t.scaffold,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Icon(_kindIcon(entry.kind), size: 13, color: accent),
                const SizedBox(width: 5),
                Text(
                  _kindLabel(entry.kind),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 6),
                // actionID chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.navyLt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#$shortId',
                    style: TextStyle(
                      fontSize: 9,
                      color: t.navy,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  time,
                  style: TextStyle(fontSize: 10, color: t.muted, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          // ── Body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.alertLabel != null)
                  Row(
                    children: [
                      Icon(Icons.warning_amber_outlined, size: 12, color: t.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.alertLabel!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                if (entry.supervisorName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: t.navy),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.supervisorName!,
                          style: TextStyle(
                            fontSize: 11,
                            color: t.navy,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.confidence > 0)
                        _ConfidenceChip(entry.confidence),
                    ],
                  ),
                ],
                if (entry.factory != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.factory_outlined, size: 11, color: t.muted),
                      const SizedBox(width: 4),
                      Text(entry.factory!, style: TextStyle(fontSize: 10, color: t.muted)),
                    ],
                  ),
                ],
                if (entry.reason.isNotEmpty) ...[
                  if (entry.alertLabel != null || entry.supervisorName != null)
                    const SizedBox(height: 5),
                  Text(
                    entry.reason,
                    style: TextStyle(fontSize: 11, color: t.muted),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _kindColor(String kind, AppTheme t) => switch (kind) {
        'assigned'  => t.green,
        'skipped'   => t.muted,
        'handover'  => const Color(0xFF60A5FA),
        'created'   => t.navy,
        'updated'   => t.blue,
        'evaluate'  => t.orange,
        _           => t.muted,
      };

  IconData _kindIcon(String kind) => switch (kind) {
        'assigned'  => Icons.check_circle,
        'skipped'   => Icons.skip_next,
        'handover'  => Icons.swap_horiz,
        'created'   => Icons.add_circle_outline,
        'updated'   => Icons.edit_outlined,
        'evaluate'  => Icons.psychology_outlined,
        _           => Icons.bolt,
      };

  String _kindLabel(String kind) => switch (kind) {
        'assigned'  => 'ASSIGNED',
        'skipped'   => 'SKIPPED',
        'handover'  => 'HANDOVER',
        'created'   => 'SHIFT CREATED',
        'updated'   => 'SHIFT UPDATED',
        'evaluate'  => 'EVALUATE',
        _           => kind.toUpperCase(),
      };
}

class _ConfidenceChip extends StatelessWidget {
  final double confidence;
  const _ConfidenceChip(this.confidence);

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final pct = (confidence * 100).round();
    final color = pct >= 85
        ? t.green
        : pct >= 70
            ? t.blue
            : pct >= 50
                ? t.orange
                : t.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

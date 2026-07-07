import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../providers/alert_provider.dart';
import '../../screens/alert_detail_screen.dart';
import '../../services/ai_assignment_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

/// Notification types that carry inline decisions and must not be swept away
/// by "dismiss all".
const Set<String> _kActionableTypes = {
  'ai_cross_factory_recommendation',
  'help_request',
  'assistance_request',
};

/// The Production Manager header bell: live unread badge + an anchored
/// notification-center popover that springs out of the bell (instead of a
/// bottom sheet). Owns the `notifications/{uid}` stream end to end.
class AdminNotificationBell extends StatefulWidget {
  final bool enabled;

  const AdminNotificationBell({super.key, this.enabled = true});

  @override
  State<AdminNotificationBell> createState() => _AdminNotificationBellState();
}

class _AdminNotificationBellState extends State<AdminNotificationBell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey _bellKey = GlobalKey();

  DatabaseReference? _db;
  StreamSubscription<DatabaseEvent>? _sub;
  List<Map<String, dynamic>> _notifications = [];
  int _unread = 0;

  bool _open = false;
  bool _unreadOnly = false;
  OverlayEntry? _entry;

  late final AnimationController _panelCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 150),
  );
  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.enabled) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _db = FirebaseDatabase.instance.ref();
    _sub = _db!.child('notifications/$uid').onValue.listen(
      (event) {
        final data = event.snapshot.value;
        List<Map<String, dynamic>> list = [];
        if (data is Map) {
          list = data.entries
              .where((e) => e.value is Map)
              .map((e) {
                final m = Map<String, dynamic>.from(e.value as Map);
                m['id'] = e.key.toString();
                return m;
              })
              .toList()
            ..sort((a, b) => _timeOf(b).compareTo(_timeOf(a)));
        }
        final unread = list.where((n) => n['status'] != 'read').length;
        final grew = unread > _unread;
        if (!mounted) return;
        setState(() {
          _notifications = list;
          _unread = unread;
        });
        _entry?.markNeedsBuild();
        if (grew && !_open) _shakeCtrl.forward(from: 0);
      },
      onError: (error) {
        debugPrint('Notification stream error: $error');
        if (!mounted) return;
        setState(() {
          _notifications = [];
          _unread = 0;
        });
        _entry?.markNeedsBuild();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _entry?.remove();
    _entry = null;
    _panelCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // The panel is positioned in global coordinates; a resize/rotation would
    // leave it floating detached from the bell, so just close it.
    if (_open) _closeImmediate();
  }

  static DateTime _timeOf(Map<String, dynamic> n) {
    final raw = (n['timestamp'] ?? n['createdAt'] ?? n['at'] ?? '').toString();
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _recount() {
    _unread = _notifications.where((n) => n['status'] != 'read').length;
  }

  /// Repaint both the bell (badge) and the open popover.
  void _refresh() {
    if (mounted) setState(() {});
    _entry?.markNeedsBuild();
  }

  // ── Popover lifecycle ─────────────────────────────────────────────

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openPanel();
    }
  }

  void _openPanel() {
    final box = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    if (box == null || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.of(context).size;

    final double width = math.min(392.0, screen.width - 16.0);
    final double right = (screen.width - rect.right)
        .clamp(8.0, math.max(8.0, screen.width - width - 8.0))
        .toDouble();
    final double top = rect.bottom + 6.0;
    final double maxHeight =
        math.min(560.0, math.max(240.0, screen.height - top - 16.0));
    final double panelLeft = screen.width - right - width;
    final double caretLeft =
        (rect.center.dx - panelLeft - 9.0).clamp(16.0, width - 34.0).toDouble();
    // Scale origin sits at the caret so the panel grows out of the bell.
    final double alignX =
        (((caretLeft + 9.0) / width) * 2.0 - 1.0).clamp(-1.0, 1.0).toDouble();

    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: top,
            right: right,
            width: width,
            child: AnimatedBuilder(
              animation: _panelCtrl,
              builder: (_, child) {
                final v = Curves.easeOutCubic.transform(_panelCtrl.value);
                return Opacity(
                  opacity: v,
                  child: Transform.translate(
                    offset: Offset(0, (1 - v) * -8),
                    child: Transform.scale(
                      scale: 0.94 + 0.06 * v,
                      alignment: Alignment(alignX, -1),
                      child: child,
                    ),
                  ),
                );
              },
              child: _NotificationPanel(
                caretLeft: caretLeft,
                maxHeight: maxHeight,
                notifications: () => _notifications,
                unreadOnly: () => _unreadOnly,
                onUnreadOnlyChanged: (v) {
                  _unreadOnly = v;
                  _refresh();
                },
                onDismiss: _removeNotification,
                onDismissAll: _dismissAllNonActionable,
                onOpenAlert: _openAlert,
                onDecideRecommendation: _decideRecommendation,
                onDecideHelp: _decideHelp,
                onAssignAssistant: _pickAssistant,
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    _panelCtrl.forward(from: 0);
    setState(() => _open = true);
  }

  Future<void> _close() async {
    if (_entry == null) return;
    if (mounted) setState(() => _open = false);
    try {
      await _panelCtrl.reverse();
    } finally {
      _entry?.remove();
      _entry = null;
    }
  }

  void _closeImmediate() {
    _entry?.remove();
    _entry = null;
    _panelCtrl.value = 0;
    if (mounted) setState(() => _open = false);
  }

  // ── Actions ───────────────────────────────────────────────────────

  Future<void> _removeNotification(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _notifications.removeWhere((n) => n['id'] == id);
    _recount();
    _refresh();
    if (uid == null || _db == null) return;
    try {
      await _db!.child('notifications/$uid/$id').remove();
    } catch (e) {
      debugPrint('Notification remove failed: $e');
    }
  }

  Future<void> _dismissAllNonActionable() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ids = _notifications
        .where((n) => !_kActionableTypes.contains(n['type']))
        .map((n) => n['id'].toString())
        .toList();
    if (ids.isEmpty) return;
    _notifications.removeWhere((n) => !_kActionableTypes.contains(n['type']));
    _recount();
    _refresh();
    if (uid == null || _db == null) return;
    try {
      await _db!
          .child('notifications/$uid')
          .update({for (final id in ids) id: null});
    } catch (e) {
      debugPrint('Notification dismiss-all failed: $e');
    }
  }

  Future<void> _openAlert(Map<String, dynamic> n) async {
    final alertId = (n['alertId'] ?? '').toString();
    final type = (n['type'] ?? '').toString();
    // Pending decisions keep their row (and inline actions) until the PM
    // actually decides; other notifications are consumed by opening them.
    final keepRow = type == 'help_request' || type == 'assistance_request';
    if (!keepRow) await _removeNotification(n['id'].toString());
    _closeImmediate();
    if (!mounted || alertId.isEmpty) return;
    unawaited(Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlertDetailScreen(alertId: alertId)),
    ));
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _decideRecommendation(
    Map<String, dynamic> n, {
    required bool approve,
  }) async {
    final alertId = (n['alertId'] ?? '').toString();
    if (alertId.isEmpty) return;
    final t = context.appTheme;
    final current = FirebaseAuth.instance.currentUser;
    final approverId = current?.uid;
    final approverName =
        current?.email?.split('@').first ?? 'Production Manager';

    final ok = approve
        ? await AIAssignmentService.instance.approveCrossFactoryRecommendation(
            alertId: alertId,
            approverId: approverId,
            approverName: approverName,
          )
        : await AIAssignmentService.instance.declineCrossFactoryRecommendation(
            alertId: alertId,
            approverId: approverId,
            approverName: approverName,
          );

    await _removeNotification(n['id'].toString());
    if (!mounted) return;
    _snack(
      ok
          ? (approve
              ? context.tr('Recommendation approved')
              : context.tr('Recommendation declined'))
          : context.tr('Recommendation was already processed'),
      ok ? (approve ? t.green : t.orange) : Colors.blueGrey,
    );
  }

  Future<void> _decideHelp(
    Map<String, dynamic> n, {
    required bool accept,
  }) async {
    final t = context.appTheme;
    final provider = Provider.of<AlertProvider>(context, listen: false);
    if (accept) {
      await provider.acceptHelp(n['alertId'], n['helpRequestId']);
    } else {
      await provider.refuseHelp(n['alertId'], n['helpRequestId']);
    }
    await _removeNotification(n['id'].toString());
    if (!mounted) return;
    _snack(
      accept
          ? context.tr('Help request accepted')
          : context.tr('Help request refused'),
      accept ? t.green : t.orange,
    );
  }

  Future<void> _pickAssistant(Map<String, dynamic> n) async {
    final t = context.appTheme;
    final supervisors = await AuthService().getActiveSupervisors();
    if (!mounted) return;
    if (supervisors.isEmpty) {
      _snack(context.tr('No active supervisors available'), Colors.blueGrey);
      return;
    }
    unawaited(showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Assign Assistant')),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: supervisors.length,
            itemBuilder: (_, i) => ListTile(
              leading: Icon(Icons.person, color: t.navy),
              title: Text(supervisors[i].fullName),
              subtitle: Text(supervisors[i].email),
              onTap: () async {
                Navigator.pop(dialogContext);
                await AuthService().assignAssistantToAlert(
                  n['alertId'],
                  supervisors[i].id,
                  supervisors[i].fullName,
                );
                await _removeNotification(n['id'].toString());
                if (!mounted) return;
                _snack(
                  context.tr(
                    'Assigned {name} as assistant',
                    {'name': supervisors[i].fullName},
                  ),
                  t.green,
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.tr('Cancel')),
          ),
        ],
      ),
    ));
  }

  // ── Bell ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _shakeCtrl,
          builder: (_, child) {
            final v = _shakeCtrl.value;
            final angle = math.sin(v * math.pi * 5) * (1 - v) * 0.18;
            return Transform.rotate(
              angle: angle,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          child: IconButton(
            key: _bellKey,
            icon: Icon(
              _open ? Icons.notifications : Icons.notifications_none,
              color: _open ? t.navy : t.muted,
              size: 24,
            ),
            tooltip: context.tr('Notifications'),
            style: IconButton.styleFrom(
              backgroundColor: _open ? t.navyLt : Colors.transparent,
              shape: const CircleBorder(),
            ),
            onPressed: widget.enabled ? _toggle : null,
          ),
        ),
        if (_unread > 0)
          Positioned(
            top: 4,
            right: 4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 17),
                height: 17,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: t.red,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: t.card, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    _unread > 99 ? '99+' : '$_unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Popover panel
// ═══════════════════════════════════════════════════════════════════════

class _NotificationPanel extends StatelessWidget {
  final double caretLeft;
  final double maxHeight;
  final List<Map<String, dynamic>> Function() notifications;
  final bool Function() unreadOnly;
  final ValueChanged<bool> onUnreadOnlyChanged;
  final Future<void> Function(String id) onDismiss;
  final Future<void> Function() onDismissAll;
  final Future<void> Function(Map<String, dynamic> n) onOpenAlert;
  final Future<void> Function(Map<String, dynamic> n, {required bool approve})
      onDecideRecommendation;
  final Future<void> Function(Map<String, dynamic> n, {required bool accept})
      onDecideHelp;
  final Future<void> Function(Map<String, dynamic> n) onAssignAssistant;

  const _NotificationPanel({
    required this.caretLeft,
    required this.maxHeight,
    required this.notifications,
    required this.unreadOnly,
    required this.onUnreadOnlyChanged,
    required this.onDismiss,
    required this.onDismissAll,
    required this.onOpenAlert,
    required this.onDecideRecommendation,
    required this.onDecideHelp,
    required this.onAssignAssistant,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;
    final all = notifications();
    final filterUnread = unreadOnly();
    final unreadCount = all.where((n) => n['status'] != 'read').length;
    final visible =
        filterUnread ? all.where((n) => n['status'] != 'read').toList() : all;
    final hasDismissible =
        all.any((n) => !_kActionableTypes.contains(n['type']));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight - 8),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context, t, unreadCount, hasDismissible),
                    _filterRow(context, t, all.length, unreadCount),
                    Divider(height: 1, thickness: 1, color: t.border),
                    Flexible(
                      child: visible.isEmpty
                          ? _emptyState(context, t)
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: visible.length,
                              itemBuilder: (ctx, i) => _NotificationTile(
                                notification: visible[i],
                                onDismiss: onDismiss,
                                onOpenAlert: onOpenAlert,
                                onDecideRecommendation: onDecideRecommendation,
                                onDecideHelp: onDecideHelp,
                                onAssignAssistant: onAssignAssistant,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: caretLeft,
          child: CustomPaint(
            size: const Size(18, 9),
            painter: _CaretPainter(fill: t.card, border: t.border),
          ),
        ),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    AppTheme t,
    int unreadCount,
    bool hasDismissible,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          Text(
            context.tr('Notifications'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: t.textDark,
              letterSpacing: .2,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.redLt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                context.tr('{n} new', {'n': '$unreadCount'}),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: t.red,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (hasDismissible)
            IconButton(
              icon: Icon(Icons.clear_all_rounded, size: 20, color: t.muted),
              tooltip: context.tr('Dismiss all'),
              visualDensity: VisualDensity.compact,
              onPressed: onDismissAll,
            ),
        ],
      ),
    );
  }

  Widget _filterRow(BuildContext context, AppTheme t, int total, int unread) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          _FilterPill(
            label: context.tr('All'),
            count: total,
            selected: !unreadOnly(),
            onTap: () => onUnreadOnlyChanged(false),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: context.tr('Unread'),
            count: unread,
            selected: unreadOnly(),
            onTap: () => onUnreadOnlyChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, AppTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: t.navyLt, shape: BoxShape.circle),
            child: Icon(Icons.notifications_off_outlined,
                size: 30, color: t.navy),
          ),
          const SizedBox(height: 14),
          Text(
            context.tr("You're all caught up"),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: t.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('New notifications will appear here'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: t.muted),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? t.navy : t.scaffold,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? t.navy : t.border),
        ),
        child: Text(
          count > 0 ? '$label · $count' : label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : t.muted,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tiles
// ═══════════════════════════════════════════════════════════════════════

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final Future<void> Function(String id) onDismiss;
  final Future<void> Function(Map<String, dynamic> n) onOpenAlert;
  final Future<void> Function(Map<String, dynamic> n, {required bool approve})
      onDecideRecommendation;
  final Future<void> Function(Map<String, dynamic> n, {required bool accept})
      onDecideHelp;
  final Future<void> Function(Map<String, dynamic> n) onAssignAssistant;

  const _NotificationTile({
    required this.notification,
    required this.onDismiss,
    required this.onOpenAlert,
    required this.onDecideRecommendation,
    required this.onDecideHelp,
    required this.onAssignAssistant,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final n = notification;
    final type = (n['type'] ?? '').toString();
    final unread = n['status'] != 'read';
    final actionable = _kActionableTypes.contains(type);
    final style = _styleFor(t, type);

    final title = (n['message'] ?? '').toString().trim().isNotEmpty
        ? n['message'].toString()
        : _fallbackTitle(context, type);
    final subtitle = _subtitleFor(context, n, type);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: () => onOpenAlert(n),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            color: unread
                ? t.navyLt.withValues(alpha: t.isDark ? 0.45 : 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: t.isDark ? 0.20 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, size: 21, color: style.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            unread ? FontWeight.w700 : FontWeight.w600,
                        color: t.text,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _relativeTime(context, _AdminNotificationBellState
                          ._timeOf(n)),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: unread ? t.navy : t.mutedDk,
                      ),
                    ),
                    if (actionable) ...[
                      const SizedBox(height: 8),
                      _actionsFor(context, t, n, type),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (unread)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: t.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (!actionable)
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 16, color: t.muted),
                      tooltip: context.tr('Dismiss notification'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => onDismiss(n['id'].toString()),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fallbackTitle(BuildContext context, String type) {
    switch (type) {
      case 'ai_cross_factory_recommendation':
        return context.tr('AI cross-factory recommendation');
      case 'help_request':
        return context.tr('Help request');
      case 'assistance_request':
        return context.tr('Assistance request');
      default:
        return context.tr('Notification');
    }
  }

  String _subtitleFor(
    BuildContext context,
    Map<String, dynamic> n,
    String type,
  ) {
    if (type == 'ai_cross_factory_recommendation') {
      final recName = (n['recommendedSupervisorName'] ?? '').toString();
      final reason = (n['reason'] ?? '').toString();
      final parts = <String>[
        if (recName.isNotEmpty)
          context.tr('Recommended: {name}', {'name': recName}),
        if (reason.isNotEmpty) reason,
      ];
      return parts.join(' — ');
    }
    if (type == 'help_request') {
      final desc = (n['alertDescription'] ?? '').toString();
      return desc.isNotEmpty ? desc : context.tr('Tap to accept or refuse');
    }
    return (n['alertDescription'] ?? '').toString();
  }

  Widget _actionsFor(
    BuildContext context,
    AppTheme t,
    Map<String, dynamic> n,
    String type,
  ) {
    switch (type) {
      case 'ai_cross_factory_recommendation':
        return Row(
          children: [
            _MiniButton(
              label: context.tr('Decline'),
              icon: Icons.close_rounded,
              color: t.red,
              outlined: true,
              onTap: () => onDecideRecommendation(n, approve: false),
            ),
            const SizedBox(width: 8),
            _MiniButton(
              label: context.tr('Approve'),
              icon: Icons.check_rounded,
              color: t.green,
              onTap: () => onDecideRecommendation(n, approve: true),
            ),
          ],
        );
      case 'help_request':
        return Row(
          children: [
            _MiniButton(
              label: context.tr('Refuse'),
              icon: Icons.close_rounded,
              color: t.red,
              outlined: true,
              onTap: () => onDecideHelp(n, accept: false),
            ),
            const SizedBox(width: 8),
            _MiniButton(
              label: context.tr('Accept'),
              icon: Icons.check_rounded,
              color: t.green,
              onTap: () => onDecideHelp(n, accept: true),
            ),
          ],
        );
      case 'assistance_request':
        return _MiniButton(
          label: context.tr('Assign Assistant'),
          icon: Icons.person_add_alt_1_rounded,
          color: t.navy,
          onTap: () => onAssignAssistant(n),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  static String _relativeTime(BuildContext context, DateTime time) {
    if (time.millisecondsSinceEpoch == 0) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) {
      return context.tr('{n}s ago', {'n': '${math.max(diff.inSeconds, 1)}'});
    }
    if (diff.inMinutes < 60) {
      return context.tr('{n}m ago', {'n': '${diff.inMinutes}'});
    }
    if (diff.inHours < 24) {
      return context.tr('{n}h ago', {'n': '${diff.inHours}'});
    }
    return context.tr('{n}d ago', {'n': '${diff.inDays}'});
  }

  static _NotifStyle _styleFor(AppTheme t, String type) {
    if (type.startsWith('collab')) {
      if (type.contains('approved') || type.contains('accepted')) {
        return _NotifStyle(Icons.groups_rounded, t.green);
      }
      if (type.contains('rejected') ||
          type.contains('refused') ||
          type.contains('removed')) {
        return _NotifStyle(Icons.group_off_rounded, t.red);
      }
      return _NotifStyle(Icons.groups_rounded, t.blue);
    }
    switch (type) {
      case 'new_alert':
        return _NotifStyle(Icons.notification_important_rounded, t.red);
      case 'alert_critical_update':
        return _NotifStyle(Icons.warning_amber_rounded, t.red);
      case 'help_request':
        return _NotifStyle(Icons.support_agent_rounded, t.orange);
      case 'help_accepted':
        return _NotifStyle(Icons.check_circle_rounded, t.green);
      case 'help_refused':
        return _NotifStyle(Icons.cancel_rounded, t.red);
      case 'assistance_request':
        return _NotifStyle(Icons.group_add_rounded, t.blue);
      case 'assistant_assigned':
      case 'alert_assigned':
        return _NotifStyle(Icons.assignment_ind_rounded, t.navy);
      case 'ai_assigned':
      case 'ai_recommendation':
      case 'ai_cross_factory_recommendation':
        return _NotifStyle(Icons.psychology_rounded, t.purple);
      case 'ai_rejection':
        return _NotifStyle(Icons.psychology_alt_rounded, t.orange);
      case 'alert_suspended':
        return _NotifStyle(Icons.pause_circle_rounded, t.orange);
      case 'shift_handover':
        return _NotifStyle(Icons.swap_horiz_rounded, t.navy);
      case 'confirm_presence':
        return _NotifStyle(Icons.how_to_reg_rounded, t.green);
      default:
        return _NotifStyle(Icons.notifications_rounded, t.muted);
    }
  }
}

class _NotifStyle {
  final IconData icon;
  final Color color;
  const _NotifStyle(this.icon, this.color);
}

class _MiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;

  const _MiniButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(9),
          border: outlined ? Border.all(color: color) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: outlined ? color : Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: outlined ? color : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The little arrow that points from the panel up to the bell.
class _CaretPainter extends CustomPainter {
  final Color fill;
  final Color border;

  const _CaretPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(
      Path.from(path)..close(),
      Paint()..color = fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) =>
      old.fill != fill || old.border != border;
}

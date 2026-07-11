import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/collaboration_model.dart';
import '../models/shift_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/collaboration_service.dart';
import '../services/alert_service.dart';
import '../services/service_locator.dart';
import '../services/shift_service.dart';
import '../models/alert_model.dart';
import '../l10n/app_strings.dart';
import '../theme.dart';
import '../utils/alert_meta.dart';
import '../utils/user_friendly_error.dart';
import '../widgets/common/app_loading_indicator.dart';

part 'admin_escalation_screen_collaborations.dart';
part 'admin_escalation_screen_settings.dart';

Color get _navy => themeBrandPrimary;
const _muted = AppColors.mutedDark;
const _green = AppColors.green;
const _greenLt = AppColors.greenLight;
const _red = AppColors.red;
const _redLt = Color(0xFFFEE2E2);
const _orange = AppColors.orange;
const _purple = Color(0xFF9333EA);

// Use centralized alert metadata from `utils/alert_meta.dart`.

class AdminEscalationScreen extends StatefulWidget {
  const AdminEscalationScreen({super.key});

  @override
  State<AdminEscalationScreen> createState() => _AdminEscalationScreenState();
}

class _AdminEscalationScreenState extends State<AdminEscalationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appTheme.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: context.appTheme.card,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: context.appTheme.orange,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('Escalations'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: context.appTheme.navy,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: context.tr('Escalation Settings'),
                        onPressed: _showSettingsDialog,
                        icon: Icon(
                          Icons.settings,
                          color: context.appTheme.navy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Expanded(child: _EscalatedAlertsTab()),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    final t = context.appTheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        return Dialog(
          backgroundColor: t.card,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 900,
                  maxHeight: size.height * 0.82,
                ),
                child: const _SettingsTab(),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: Icon(Icons.close, color: t.muted),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Replace the old _EscalatedAlertsTab with this
class _EscalatedAlertsTab extends StatelessWidget {
  const _EscalatedAlertsTab();

  @override
  Widget build(BuildContext context) {
    final database = FirebaseDatabase.instance.ref();
    final t = context.appTheme;

    return StreamBuilder<DatabaseEvent>(
      stream: database
          .child('alerts')
          .orderByChild('isEscalated')
          .equalTo(true)
          .onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(color: t.red),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: t.navy));
        }

        final alertsMap = snapshot.data!.snapshot.value;
        if (alertsMap == null) return _buildEmpty(t);

        final List<MapEntry<String, dynamic>> entries =
            Map<String, dynamic>.from(alertsMap as Map).entries.toList();

        final escalated =
            entries
                .where((entry) {
                  final v = entry.value as Map?;
                  if (v == null || v['isEscalated'] != true) return false;
                  final status = v['status'] as String? ?? '';
                  return status != 'validee' && status != 'cancelled';
                })
                .map(
                  (entry) => AlertModel.fromMap(
                    entry.key,
                    Map<String, dynamic>.from(entry.value),
                  ),
                )
                .toList()
              ..sort(
                (a, b) => (b.escalatedAt ?? b.timestamp).compareTo(
                  a.escalatedAt ?? a.timestamp,
                ),
              );

        if (escalated.isEmpty) return _buildEmpty(t);

        return _EscalatedAlertsPanel(alerts: escalated);
      },
    );
  }

  Widget _buildEmpty(AppTheme t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber, size: 48, color: t.orange),
          const SizedBox(height: 16),
          Text(
            'No Escalated Alerts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: t.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Alerts that exceed time thresholds will appear here',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ESCALATED ALERT CARD
// ============================================================================
class _EscalatedAlertsPanel extends StatefulWidget {
  final List<AlertModel> alerts;

  const _EscalatedAlertsPanel({required this.alerts});

  @override
  State<_EscalatedAlertsPanel> createState() => _EscalatedAlertsPanelState();
}

class _EscalatedAlertsPanelState extends State<_EscalatedAlertsPanel> {
  late final Stream<EscalationSettings> _settingsStream = CollaborationService()
      .escalationSettingsStream();

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final newCount = widget.alerts.where(_isNewEscalation).length;

    return StreamBuilder<EscalationSettings>(
      stream: _settingsStream,
      initialData: EscalationSettings.defaultSettings(),
      builder: (context, settingsSnapshot) {
        final settings =
            settingsSnapshot.data ?? EscalationSettings.defaultSettings();

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - value)),
                child: child,
              ),
            );
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.red.withValues(alpha: 0.24)),
                  boxShadow: t.isDark
                      ? null
                      : [
                          BoxShadow(
                            color: t.red.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 22,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            t.redLt.withValues(alpha: t.isDark ? 0.28 : 0.78),
                            t.orangeLt.withValues(
                              alpha: t.isDark ? 0.18 : 0.44,
                            ),
                          ],
                        ),
                        border: Border(
                          top: BorderSide(color: t.red.withValues(alpha: 0.45)),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BreathingWarningIcon(color: t.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Escalated Alerts',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: t.red,
                                      ),
                                    ),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 260,
                                      ),
                                      transitionBuilder: (child, animation) =>
                                          ScaleTransition(
                                            scale: animation,
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          ),
                                      child: newCount > 0
                                          ? _CountBadge(
                                              key: ValueKey(newCount),
                                              label: context.tr('{n} New',
                                                  {'n': '$newCount'}),
                                              color: t.red,
                                            )
                                          : _CountBadge(
                                              key: const ValueKey('read'),
                                              label: context.tr('All Read'),
                                              color: t.green,
                                            ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Alerts that exceeded time thresholds and require immediate attention',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: t.muted,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: List.generate(widget.alerts.length, (index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == widget.alerts.length - 1
                                  ? 0
                                  : 16,
                            ),
                            child: _EscalatedAlertCard(
                              alert: widget.alerts[index],
                              settings: settings,
                              index: index,
                            ),
                          );
                        }),
                      ),
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

class _EscalatedAlertCard extends StatefulWidget {
  final AlertModel alert;
  final EscalationSettings settings;
  final int index;

  const _EscalatedAlertCard({
    required this.alert,
    required this.settings,
    required this.index,
  });

  @override
  State<_EscalatedAlertCard> createState() => _EscalatedAlertCardState();
}

class _EscalatedAlertCardState extends State<_EscalatedAlertCard> {
  bool _markingRead = false;
  bool _resolving = false;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final alert = widget.alert;
    final type = typeMeta(alert.type, t, context);
    final claimed = _isClaimed(alert);
    final claimColor = claimed ? t.yellow : t.red;
    final claimBg = claimed ? t.yellowLt : t.redLt;
    final assistantNames = _assistantNames(alert);
    final hasAssistantRequest = (alert.collaborationRequestId ?? '')
        .trim()
        .isNotEmpty;
    final escalatedAt = alert.escalatedAt ?? alert.timestamp;
    final limitMinutes = _limitMinutes(alert, widget.settings);
    final elapsedMinutes = _elapsedMinutes(alert);
    final isNew = _isNewEscalation(alert);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + widget.index * 70),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0, 1).toDouble(),
          child: Transform.translate(
            offset: Offset(18 * (1 - value), 0),
            child: child,
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: type.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: type.color.withValues(alpha: 0.36)),
          boxShadow: t.isDark
              ? [
                  BoxShadow(
                    color: type.color.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: type.color.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  width: 6,
                  color: type.color,
                ),
              ),
            ),
            if (isNew)
              Positioned(top: 18, right: 18, child: _PulseDot(color: t.red)),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PulseDot(color: type.color, staticDot: true, size: 15),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              type.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: t.text,
                              ),
                            ),
                            _MiniTag(
                              label: alert.alertLabel,
                              color: type.color,
                            ),
                            if (!isNew)
                              _MiniTag(label: context.tr('read'), color: t.green),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    alert.description,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.28,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InlineMeta(
                        icon: Icons.place_outlined,
                        label:
                            '${alert.usine} - Line ${alert.convoyeur} - Post ${alert.poste}',
                        color: type.color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      _StatusPill(
                        icon: claimed
                            ? Icons.assignment_turned_in_outlined
                            : Icons.person_off_outlined,
                        label: claimed
                            ? context.tr('Claimed - Time Exceeded')
                            : context.tr('Unclaimed - Time Exceeded'),
                        color: claimColor,
                        background: claimBg,
                      ),
                      if (limitMinutes != null)
                        _StatusPill(
                          icon: Icons.timer_outlined,
                          label: context.tr('{elapsed} / {limit} min',
                              {'elapsed': '$elapsedMinutes', 'limit': '$limitMinutes'}),
                          color: t.text,
                          background: t.card,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _InlineMeta(
                        icon: Icons.history_outlined,
                        label: context.tr('Original alert: {time} ago',
                            {'time': _timeAgo(alert.timestamp)}),
                        color: t.muted,
                      ),
                      _InlineMeta(
                        icon: Icons.warning_amber_outlined,
                        label: context.tr('Escalated: {time} ago',
                            {'time': _timeAgo(escalatedAt)}),
                        color: t.red,
                      ),
                      if (alert.takenAtTimestamp != null)
                        _InlineMeta(
                          icon: Icons.timer_outlined,
                          label:
                              'Claimed ${_timeAgo(alert.takenAtTimestamp!)} ago',
                          color: claimColor,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: type.color.withValues(alpha: 0.18)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _OwnershipChip(
                        icon: claimed
                            ? Icons.person_pin_circle_outlined
                            : Icons.person_search_outlined,
                        title: claimed ? 'Claimed by' : 'Claim status',
                        value: claimed ? _claimedBy(alert) : 'Not claimed yet',
                        color: claimColor,
                        background: t.card,
                      ),
                      _OwnershipChip(
                        icon: assistantNames.isEmpty
                            ? (hasAssistantRequest
                                  ? Icons.group_add_outlined
                                  : Icons.group_off_outlined)
                            : Icons.groups_2_outlined,
                        title: assistantNames.isEmpty && hasAssistantRequest
                            ? 'Assistant request'
                            : assistantNames.length == 1
                            ? 'Assistant'
                            : 'Assistants',
                        value: assistantNames.isEmpty
                            ? (hasAssistantRequest
                                  ? 'Collaboration pending'
                                  : 'No assistants')
                            : assistantNames.join(', '),
                        color: assistantNames.isEmpty && !hasAssistantRequest
                            ? t.muted
                            : t.purple,
                        background: t.card,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _EscalationActionRow(
                    isRead: !isNew,
                    markingRead: _markingRead,
                    resolving: _resolving,
                    onMarkRead: _markAsRead,
                    onResolve: _resolve,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsRead() async {
    if (_markingRead || widget.alert.escalationAcknowledgedAt != null) return;
    setState(() => _markingRead = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final displayName =
          user?.displayName ?? user?.email?.split('@').first ?? 'Admin';
      await FirebaseDatabase.instance.ref('alerts/${widget.alert.id}').update({
        'escalationAcknowledgedAt': DateTime.now().toIso8601String(),
        'escalationAcknowledgedBy': user?.uid,
        'escalationAcknowledgedByName': displayName,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.alert.alertLabel} marked as read'),
          backgroundColor: context.appTheme.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFriendlyError.message(e)),
          backgroundColor: context.appTheme.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _markingRead = false);
    }
  }

  Future<void> _resolve() async {
    if (_resolving) return;

    final reasonController = TextEditingController(
      text: 'Resolved from escalation review',
    );
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.appTheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: t.green),
              const SizedBox(width: 8),
              Text(context.tr('Resolve Escalated Alert')),
            ],
          ),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.tr('Resolution reason'),
              hintText: context.tr('What fixed or closed this alert?'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel')),
            ),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, reasonController.text.trim()),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(context.tr('Resolve')),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
    reasonController.dispose();

    if (reason == null || reason.isEmpty) return;
    setState(() => _resolving = true);
    try {
      await AlertService().resolveAlert(
        widget.alert.id,
        reason,
        _elapsedMinutes(widget.alert),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('{label} resolved',
              {'label': widget.alert.alertLabel})),
          backgroundColor: context.appTheme.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFriendlyError.message(e)),
          backgroundColor: context.appTheme.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }
}

class _EscalationActionRow extends StatelessWidget {
  final bool isRead;
  final bool markingRead;
  final bool resolving;
  final VoidCallback onMarkRead;
  final VoidCallback onResolve;

  const _EscalationActionRow({
    required this.isRead,
    required this.markingRead,
    required this.resolving,
    required this.onMarkRead,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final busy = markingRead || resolving;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 620;
        final markButton = _ActionButton(
          icon: isRead
              ? Icons.check_circle_outline
              : Icons.mark_chat_read_outlined,
          label: isRead ? context.tr('Marked Read') : context.tr('Mark as Read'),
          loading: markingRead,
          onPressed: isRead || busy ? null : onMarkRead,
          foreground: isRead ? t.green : t.text,
          background: t.card,
          border: t.border,
        );
        final resolveButton = _ActionButton(
          icon: Icons.check_circle_outline,
          label: context.tr('Resolve'),
          loading: resolving,
          onPressed: busy ? null : onResolve,
          foreground: Colors.white,
          background: t.green,
          border: t.green,
        );

        if (stacked) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: markButton),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: resolveButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: markButton),
            const SizedBox(width: 10),
            Expanded(child: resolveButton),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;
  final Color foreground;
  final Color background;
  final Color border;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
    required this.foreground,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: onPressed == null ? 0.99 : 1,
      duration: const Duration(milliseconds: 160),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          foregroundColor: foreground,
          backgroundColor: background,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: loading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Row(
                  key: ValueKey(label),
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(label)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CountBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BreathingWarningIcon extends StatefulWidget {
  final Color color;

  const _BreathingWarningIcon({required this.color});

  @override
  State<_BreathingWarningIcon> createState() => _BreathingWarningIconState();
}

class _BreathingWarningIconState extends State<_BreathingWarningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(
          scale: 1 + value * 0.06,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.08 + value * 0.06),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: widget.color,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool staticDot;
  final double size;

  const _PulseDot({
    required this.color,
    this.staticDot = false,
    this.size = 12,
  });

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    if (!widget.staticDot) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.staticDot) {
      return _dot(0);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = Curves.easeOut.transform(_controller.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size + 12 * value,
              height: widget.size + 12 * value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.18 * (1 - value)),
              ),
            ),
            _dot(value),
          ],
        );
      },
    );
  }

  Widget _dot(double value) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InlineMeta({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: t.muted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _OwnershipChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final Color background;

  const _OwnershipChip({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44, maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _isClaimed(AlertModel alert) =>
    alert.status == 'en_cours' ||
    (alert.superviseurId != null && alert.superviseurId!.trim().isNotEmpty) ||
    (alert.superviseurName != null && alert.superviseurName!.trim().isNotEmpty);

bool _isNewEscalation(AlertModel alert) {
  final acknowledgedAt = alert.escalationAcknowledgedAt;
  if (acknowledgedAt == null) return true;
  final escalatedAt = alert.escalatedAt;
  return escalatedAt != null && acknowledgedAt.isBefore(escalatedAt);
}

int _elapsedMinutes(AlertModel alert) {
  final anchor = _isClaimed(alert)
      ? alert.takenAtTimestamp ?? alert.timestamp
      : alert.timestamp;
  final minutes = DateTime.now().difference(anchor).inMinutes;
  return minutes < 0 ? 0 : minutes;
}

int? _limitMinutes(AlertModel alert, EscalationSettings settings) {
  final threshold =
      settings.thresholds[alert.type] ??
      settings.thresholds[alert.type.toLowerCase()] ??
      settings.thresholds['default'];
  if (threshold == null) return null;
  return _isClaimed(alert)
      ? threshold.claimedMinutes
      : threshold.unclaimedMinutes;
}

String _timeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return '<1 min';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) {
    final minutes = diff.inMinutes % 60;
    return minutes == 0
        ? '${diff.inHours} h'
        : '${diff.inHours} h $minutes min';
  }
  return '${diff.inDays} d';
}

String _claimedBy(AlertModel alert) {
  final name = alert.superviseurName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final id = alert.superviseurId?.trim();
  if (id != null && id.isNotEmpty) return 'Supervisor ${_shortId(id)}';
  return 'Assigned supervisor';
}

List<String> _assistantNames(AlertModel alert) {
  final names = <String>[];

  void addName(String? raw) {
    final name = raw?.trim();
    if (name == null || name.isEmpty) return;
    final duplicate = names.any(
      (existing) => existing.toLowerCase() == name.toLowerCase(),
    );
    if (!duplicate) names.add(name);
  }

  if ((alert.assistantName ?? '').trim().isNotEmpty) {
    addName(alert.assistantName);
  } else {
    addName(_assistantIdLabel(alert.assistantId));
  }

  for (final collaborator
      in alert.collaborators ?? const <Map<String, String>>[]) {
    if ((collaborator['name'] ?? '').trim().isNotEmpty) {
      addName(collaborator['name']);
    } else {
      addName(_assistantIdLabel(collaborator['id']));
    }
  }

  return names;
}

String _shortId(String id) => id.length <= 6 ? id : id.substring(0, 6);

String? _assistantIdLabel(String? id) {
  final clean = id?.trim();
  if (clean == null || clean.isEmpty) return null;
  return 'Assistant ${_shortId(clean)}';
}

// ============================================================================
// COLLABORATIONS TAB — surfaced under the Supervisors section.
// ============================================================================

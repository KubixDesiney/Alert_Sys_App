import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';
import '../services/alert_service.dart';
import '../models/alert_model.dart';
import '../theme.dart';
import '../utils/alert_meta.dart';
import '../utils/user_friendly_error.dart';
import '../widgets/common/app_loading_indicator.dart';

const _navy = AppColors.navy;
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
                      Icon(Icons.warning_amber,
                          color: context.appTheme.orange, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Escalations',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: context.appTheme.navy,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Escalation Settings',
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
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  tooltip: 'Close',
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
            child: Text('Error: ${snapshot.error}',
                style: TextStyle(color: t.red)),
          );
        }

        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: t.navy));
        }

        final alertsMap = snapshot.data!.snapshot.value;
        if (alertsMap == null) return _buildEmpty(t);

        final List<MapEntry<String, dynamic>> entries =
            Map<String, dynamic>.from(alertsMap as Map).entries.toList();

        final escalated = entries
            .where((entry) {
              final v = entry.value as Map?;
              if (v == null || v['isEscalated'] != true) return false;
              final status = v['status'] as String? ?? '';
              return status != 'validee' && status != 'cancelled';
            })
            .map((entry) => AlertModel.fromMap(
                entry.key, Map<String, dynamic>.from(entry.value)))
            .toList()
          ..sort((a, b) => (b.escalatedAt ?? b.timestamp)
              .compareTo(a.escalatedAt ?? a.timestamp));

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
          Text('No Escalated Alerts',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: t.text)),
          const SizedBox(height: 4),
          Text('Alerts that exceed time thresholds will appear here',
              style: TextStyle(fontSize: 13, color: t.muted)),
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
  late final Stream<EscalationSettings> _settingsStream =
      CollaborationService().escalationSettingsStream();

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
                          )
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            t.redLt.withValues(alpha: t.isDark ? 0.28 : 0.78),
                            t.orangeLt
                                .withValues(alpha: t.isDark ? 0.18 : 0.44),
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
                                      duration:
                                          const Duration(milliseconds: 260),
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
                                              label: '$newCount New',
                                              color: t.red,
                                            )
                                          : _CountBadge(
                                              key: const ValueKey('read'),
                                              label: 'All Read',
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
                              bottom:
                                  index == widget.alerts.length - 1 ? 0 : 16,
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
    final type = typeMeta(alert.type, t);
    final claimed = _isClaimed(alert);
    final claimColor = claimed ? t.yellow : t.red;
    final claimBg = claimed ? t.yellowLt : t.redLt;
    final assistantNames = _assistantNames(alert);
    final hasAssistantRequest =
        (alert.collaborationRequestId ?? '').trim().isNotEmpty;
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
                  )
                ]
              : [
                  BoxShadow(
                    color: type.color.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  )
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
              Positioned(
                top: 18,
                right: 18,
                child: _PulseDot(color: t.red),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PulseDot(
                        color: type.color,
                        staticDot: true,
                        size: 15,
                      ),
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
                              _MiniTag(
                                label: 'read',
                                color: t.green,
                              ),
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
                            ? 'Claimed - Time Exceeded'
                            : 'Unclaimed - Time Exceeded',
                        color: claimColor,
                        background: claimBg,
                      ),
                      if (limitMinutes != null)
                        _StatusPill(
                          icon: Icons.timer_outlined,
                          label: '$elapsedMinutes / $limitMinutes min',
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
                        label:
                            'Original alert: ${_timeAgo(alert.timestamp)} ago',
                        color: t.muted,
                      ),
                      _InlineMeta(
                        icon: Icons.warning_amber_outlined,
                        label: 'Escalated: ${_timeAgo(escalatedAt)} ago',
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
              const Text('Resolve Escalated Alert'),
            ],
          ),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Resolution reason',
              hintText: 'What fixed or closed this alert?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, reasonController.text.trim()),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Resolve'),
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
          content: Text('${widget.alert.alertLabel} resolved'),
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
          label: isRead ? 'Marked Read' : 'Mark as Read',
          loading: markingRead,
          onPressed: isRead || busy ? null : onMarkRead,
          foreground: isRead ? t.green : t.text,
          background: t.card,
          border: t.border,
        );
        final resolveButton = _ActionButton(
          icon: Icons.check_circle_outline,
          label: 'Resolve',
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
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
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

  const _MiniTag({
    required this.label,
    required this.color,
  });

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

  const _CountBadge({
    super.key,
    required this.label,
    required this.color,
  });

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
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
      ),
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
  final threshold = settings.thresholds[alert.type] ??
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
class CollaborationsTab extends StatelessWidget {
  const CollaborationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CollaborationService();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pending section header
          Row(
            children: [
              Icon(Icons.pending_actions, color: _orange, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Pending Collaboration Requests',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Approve or reject collaboration requests from supervisors',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 16),

          // Pending requests stream
          StreamBuilder<List<CollaborationRequest>>(
            stream: service.getPendingCollaborationRequests(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingIndicator();
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: _green.withValues(alpha: 0.5)),
                      const SizedBox(height: 8),
                      Text(
                        'No pending collaboration requests',
                        style: TextStyle(fontSize: 13, color: _muted),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: snapshot.data!
                    .map((request) =>
                        _CollaborationRequestCard(request: request))
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 32),

          // History section header
          Row(
            children: [
              Icon(Icons.history, color: _navy, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Request History',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Recently processed collaboration requests',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 16),

          // History requests stream
          StreamBuilder<List<CollaborationRequest>>(
            stream: service.getAllCollaborationRequests(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingIndicator();
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Text(
                    'No request history',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                );
              }
              final history =
                  snapshot.data!.where((r) => r.status != 'pending').toList();
              if (history.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Text(
                    'No request history',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                );
              }
              return Column(
                children: history
                    .map((request) => _HistoryRequestCard(request: request))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CollaborationRequestCard extends StatefulWidget {
  final CollaborationRequest request;
  const _CollaborationRequestCard({required this.request});

  @override
  State<_CollaborationRequestCard> createState() =>
      _CollaborationRequestCardState();
}

class _CollaborationRequestCardState extends State<_CollaborationRequestCard> {
  final Set<String> _removing = {};
  bool _isApproving = false;

  Future<void> _removeAssistant(
      String assistantId, String assistantName) async {
    if (_removing.contains(assistantId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Assistant?'),
        content: Text('Remove @$assistantName from this collaboration?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing.add(assistantId));
    try {
      final pmName =
          FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'PM';
      await CollaborationService().removeAssistantFromRequest(
        requestId: widget.request.id,
        assistantId: assistantId,
        assistantName: assistantName,
        removedByName: pmName,
      );
    } finally {
      if (mounted) setState(() => _removing.remove(assistantId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final r = widget.request;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final hasMultipleAssistants = r.targetSupervisorIds.length > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(Icons.shield, color: _purple, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r.requesterName,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: t.navy)),
            ),
            Text('Alert #${r.alertId.substring(0, 8)}',
                style: TextStyle(
                    fontSize: 11, color: t.muted, fontFamily: 'monospace')),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _orange, borderRadius: BorderRadius.circular(12)),
              child: const Text('Pending PM',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.access_time, size: 12, color: t.muted),
            const SizedBox(width: 4),
            Text(_formatTime(r.timestamp),
                style: TextStyle(fontSize: 11, color: t.muted)),
          ]),
          const SizedBox(height: 12),

          // Assistants with optional remove buttons
          Text('Requesting collaboration with:',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: t.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(r.targetSupervisorIds.length, (i) {
              final id = r.targetSupervisorIds[i];
              final name = r.targetSupervisorNames[i];
              final decision = r.assistantDecisions[id] ?? 'pending';
              final isRemoving = _removing.contains(id);

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: decision == 'accepted'
                      ? _green.withValues(alpha: 0.12)
                      : decision == 'refused'
                          ? _red.withValues(alpha: 0.1)
                          : _purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: decision == 'accepted'
                        ? _green.withValues(alpha: 0.4)
                        : decision == 'refused'
                            ? _red.withValues(alpha: 0.4)
                            : _purple.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    decision == 'accepted'
                        ? Icons.check_circle
                        : decision == 'refused'
                            ? Icons.cancel
                            : Icons.pending,
                    size: 13,
                    color: decision == 'accepted'
                        ? _green
                        : decision == 'refused'
                            ? _red
                            : _purple,
                  ),
                  const SizedBox(width: 5),
                  Text('@$name',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: decision == 'accepted'
                            ? _green
                            : decision == 'refused'
                                ? _red
                                : _purple,
                      )),
                  // PM remove button — only if multiple assistants
                  if (hasMultipleAssistants && decision != 'refused') ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap:
                          isRemoving ? null : () => _removeAssistant(id, name),
                      child: isRemoving
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.red))
                          : const Icon(Icons.close,
                              size: 13, color: Colors.red),
                    ),
                  ],
                ]),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Message + description
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: t.scaffold,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.border)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.message, style: TextStyle(fontSize: 12, color: t.navy)),
              if (r.alertDescription?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text('Issue: ${r.alertDescription}',
                    style: TextStyle(
                        fontSize: 11,
                        color: t.muted,
                        fontStyle: FontStyle.italic)),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          // PM Approve / Reject buttons
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isApproving ? null : () => _handleApprove(context, r),
                icon: _isApproving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle, size: 16),
                label: Text(_isApproving ? 'Approving…' : 'Approve',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await CollaborationService()
                      .rejectCollaborationRequest(r.id, currentUserId, '');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Collaboration rejected'),
                        backgroundColor: _red));
                  }
                },
                icon: const Icon(Icons.cancel, size: 16),
                label: const Text('Reject',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: const BorderSide(color: _red),
                  backgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _handleApprove(
      BuildContext context, CollaborationRequest request) async {
    if (_isApproving) return;
    setState(() => _isApproving = true);
    try {
      await _doHandleApprove(context, request);
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  Future<void> _doHandleApprove(
      BuildContext context, CollaborationRequest request) async {
    final service = CollaborationService();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final pmName =
        FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'PM';

    // Build approval plan and delegate dialogs/decisions to the service.
    final plan = await service.buildApprovalPlanForRequest(request);

    final alertSnapshot =
        await FirebaseDatabase.instance.ref('alerts/${request.alertId}').get();
    final alertUsine = alertSnapshot.exists
        ? (alertSnapshot.child('usine').value as String? ?? '')
        : '';

    final decision = await service.requestApprovalDecision(
      context: context,
      plan: plan,
      targetUsine: alertUsine,
    );
    if (decision == null) return;

    try {
      await service.approveCollaborationRequestWithDetails(
        requestId: request.id,
        approverId: currentUserId,
        approverName: pmName,
        isPMApproval: true,
        confirmTransfer: decision.confirmTransfer,
        confirmCancelOriginal: decision.confirmCancelOriginal,
        cancelExistingAlertIds: decision.cancelExistingAlertIds.isNotEmpty
            ? decision.cancelExistingAlertIds
            : null,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Collaboration approved successfully'),
            backgroundColor: _green));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFriendlyError.message(e)),
            backgroundColor: _red));
      }
    }
  }

  // Dialog methods moved to CollaborationService

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }
}

class _HistoryRequestCard extends StatelessWidget {
  final CollaborationRequest request;

  const _HistoryRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appTheme.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1))
        ],
      ),
      child: Row(
        children: [
          // Avatar / icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: request.status == 'approved' ? _greenLt : _redLt,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              request.status == 'approved' ? Icons.check_circle : Icons.cancel,
              color: request.status == 'approved' ? _green : _red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.requesterName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Requested: ${request.targetSupervisorNames.join(", ")}',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: _muted),
                    const SizedBox(width: 4),
                    Text(
                      _formatRelativeTime(request.timestamp),
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: request.status == 'approved' ? _greenLt : _redLt,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        request.status == 'approved' ? 'Approved' : 'Rejected',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: request.status == 'approved' ? _green : _red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }
}

// ============================================================================
// SETTINGS TAB (Theme‑aware & dark‑mode creativity)
// ============================================================================
class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _service = CollaborationService();
  EscalationSettings? _settings;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _service.getEscalationSettings();
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    await _service.saveEscalationSettings(_settings!);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: context.appTheme.green,
        ),
      );
    }
  }

  void _updateThreshold(String type, int unclaimed, int claimed) {
    if (_settings == null) return;
    final newThresholds =
        Map<String, EscalationThreshold>.from(_settings!.thresholds);
    newThresholds[type] = EscalationThreshold(
      type: type,
      unclaimedMinutes: unclaimed,
      claimedMinutes: claimed,
    );
    setState(() {
      _settings = EscalationSettings(thresholds: newThresholds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.navy));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.settings, color: t.navy, size: 20),
            const SizedBox(width: 8),
            Text('Escalation Time Thresholds',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: t.navy)),
          ]),
          const SizedBox(height: 8),
          Text(
              'Configure default time limits before alerts are escalated to your attention',
              style: TextStyle(fontSize: 12, color: t.muted)),
          const SizedBox(height: 16),
          // Info Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: t.isDark
                    ? [t.yellowLt.withOpacity(0.4), t.yellowLt.withOpacity(0.2)]
                    : [t.yellowLt, t.yellowLt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.yellow.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info, color: t.yellow, size: 16),
                  const SizedBox(width: 8),
                  Text('How Escalation Works:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: t.isDark
                              ? const Color(0xFFFFE0A0)
                              : const Color(0xFF78350F))),
                ]),
                const SizedBox(height: 8),
                _buildInfoBullet(t,
                    'Unclaimed Alert Threshold: Time before an unclaimed alert is escalated'),
                _buildInfoBullet(t,
                    'Claimed Alert Threshold: Time a supervisor has to fix a claimed alert before escalation'),
                _buildInfoBullet(t,
                    'Escalated alerts appear in the "Escalated Alerts" section for immediate attention'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Threshold cards
          _ThresholdCard(
            type: 'qualite',
            label: 'Quality Issues',
            color: t.red,
            bgColor: t.redLt,
            icon: Icons.warning_amber_rounded,
            threshold: _settings!.thresholds['qualite']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('qualite', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'maintenance',
            label: 'Maintenance',
            color: t.blue,
            bgColor: t.blueLt,
            icon: Icons.build_circle,
            threshold: _settings!.thresholds['maintenance']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('maintenance', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'defaut_produit',
            label: 'Damaged Product',
            color: t.green,
            bgColor: t.greenLt,
            icon: Icons.cancel,
            threshold: _settings!.thresholds['defaut_produit']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('defaut_produit', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'manque_ressource',
            label: 'Resource Deficiency',
            color: t.orange,
            bgColor: t.orangeLt,
            icon: Icons.inventory_2,
            threshold: _settings!.thresholds['manque_ressource']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('manque_ressource', unclaimed, claimed),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white)))
                  : const Text('Save Settings',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBullet(AppTheme t, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ',
              style: TextStyle(
                  fontSize: 11,
                  color: t.isDark
                      ? const Color(0xFFFFE0A0)
                      : const Color(0xFF78350F))),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11,
                      color: t.isDark
                          ? const Color(0xFFFFF3CC)
                          : const Color(0xFF78350F)))),
        ],
      ),
    );
  }
}

class _ThresholdCard extends StatefulWidget {
  final String type, label;
  final Color color, bgColor;
  final IconData icon;
  final EscalationThreshold threshold;
  final Function(int unclaimed, int claimed) onUpdate;

  const _ThresholdCard({
    required this.type,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.threshold,
    required this.onUpdate,
  });

  @override
  State<_ThresholdCard> createState() => _ThresholdCardState();
}

class _ThresholdCardState extends State<_ThresholdCard> {
  late TextEditingController _unclaimedController;
  late TextEditingController _claimedController;

  @override
  void initState() {
    super.initState();
    _unclaimedController = TextEditingController(
        text: widget.threshold.unclaimedMinutes.toString());
    _claimedController =
        TextEditingController(text: widget.threshold.claimedMinutes.toString());
  }

  @override
  void dispose() {
    _unclaimedController.dispose();
    _claimedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    // Dark mode: add subtle inner gradient to the card for depth
    final cardDecoration = BoxDecoration(
      gradient: t.isDark
          ? LinearGradient(
              colors: [widget.bgColor, widget.bgColor.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      color: t.isDark ? null : widget.bgColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: widget.color.withOpacity(0.3)),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(widget.icon, color: widget.color, size: 20),
            const SizedBox(width: 8),
            Text(widget.label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: widget.color)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unclaimed Alert Threshold',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.color)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: t.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: t.border),
                            boxShadow: t.isDark
                                ? [
                                    BoxShadow(
                                        color: widget.color.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: Offset(0, 2))
                                  ]
                                : null,
                          ),
                          child: TextField(
                            controller: _unclaimedController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: t.text),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(12),
                            ),
                            onChanged: (value) {
                              final unclaimed = int.tryParse(value) ?? 0;
                              final claimed =
                                  int.tryParse(_claimedController.text) ?? 0;
                              widget.onUpdate(unclaimed, claimed);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('minutes',
                          style: TextStyle(fontSize: 11, color: widget.color)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Alert escalates if not claimed within this time',
                        style: TextStyle(
                            fontSize: 10,
                            color: widget.color.withOpacity(0.7))),
                  ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Claimed Alert Threshold',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.color)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: t.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: t.border),
                            boxShadow: t.isDark
                                ? [
                                    BoxShadow(
                                        color: widget.color.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: Offset(0, 2))
                                  ]
                                : null,
                          ),
                          child: TextField(
                            controller: _claimedController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: t.text),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(12),
                            ),
                            onChanged: (value) {
                              final unclaimed =
                                  int.tryParse(_unclaimedController.text) ?? 0;
                              final claimed = int.tryParse(value) ?? 0;
                              widget.onUpdate(unclaimed, claimed);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('minutes',
                          style: TextStyle(fontSize: 11, color: widget.color)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        'Alert escalates if claimed but not fixed within this time',
                        style: TextStyle(
                            fontSize: 10,
                            color: widget.color.withOpacity(0.7))),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: widget.color.withOpacity(0.2)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Preview:',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: t.navy)),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: widget.bgColor,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('Unclaimed',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: t.navy)),
                ),
                const SizedBox(width: 6),
                Text('→', style: TextStyle(fontSize: 10, color: t.muted)),
                const SizedBox(width: 6),
                Text('Escalates after ${_unclaimedController.text} min',
                    style: TextStyle(fontSize: 10, color: widget.color)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: widget.bgColor,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('Claimed',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: t.navy)),
                ),
                const SizedBox(width: 6),
                Text('→', style: TextStyle(fontSize: 10, color: t.muted)),
                const SizedBox(width: 6),
                Text(
                    'Escalates after ${_claimedController.text} min without fix',
                    style: TextStyle(fontSize: 10, color: widget.color)),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/alert_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';
import '../theme.dart';

const _purple = Color(0xFF9333EA);
const _purpleLt = Color(0xFFF3E8FF);
const _green = Color(0xFF16A34A);
const _greenLt = Color(0xFFDCFCE7);
const _red = Color(0xFFDC2626);

// ============================================================================
// COLLABORATION PROGRESS SCREEN
// ============================================================================
class CollaborationProgressScreen extends StatelessWidget {
  const CollaborationProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final service = CollaborationService();
    final t = context.appTheme;

    return Scaffold(
      backgroundColor: t.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.shield, color: _purple, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Collab Progress',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: t.navy,
                    ),
                  ),
                ],
              ),
            ),
            // Page indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: t.muted, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Container(
                      width: 20,
                      height: 6,
                      decoration: BoxDecoration(
                          color: _purple,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 4),
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: t.muted, shape: BoxShape.circle)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Content
            Expanded(
              child: StreamBuilder<List<CollaborationRequest>>(
                stream: service.getCollaborationRequestsForSupervisor(userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(color: t.navy));
                  }
                  final requests = snapshot.data ?? [];
                  if (requests.isEmpty) return _buildEmpty(context);

                  // Split into sent (I'm requester) vs received (I'm a target)
                  final sent =
                      requests.where((r) => r.requesterId == userId).toList();
                  final received = requests
                      .where((r) =>
                          r.targetSupervisorIds.contains(userId) &&
                          r.requesterId != userId)
                      .toList();

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (received.isNotEmpty) ...[
                        _sectionHeader(
                            context, Icons.inbox, 'Requests For You', _red),
                        const SizedBox(height: 8),
                        ...received.map(
                            (r) => _ReceivedCard(request: r, userId: userId)),
                        const SizedBox(height: 20),
                      ],
                      if (sent.isNotEmpty) ...[
                        _sectionHeader(
                            context, Icons.send, 'Sent Requests', t.navy),
                        const SizedBox(height: 8),
                        ...sent.map((r) => _SentCard(request: r)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(
      BuildContext context, IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.appTheme.text)),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups, size: 48, color: _purple),
          ),
          const SizedBox(height: 16),
          Text('No Collaboration Requests',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: t.text)),
          const SizedBox(height: 4),
          Text('Your collaboration requests will appear here',
              style: TextStyle(fontSize: 13, color: t.muted)),
        ],
      ),
    );
  }
}

// ============================================================================
// SENT CARD — shown to the requester (progress timeline + cancel)
// ============================================================================
class _SentCard extends StatefulWidget {
  final CollaborationRequest request;
  const _SentCard({required this.request});

  @override
  State<_SentCard> createState() => _SentCardState();
}

class _SentCardState extends State<_SentCard> {
  bool _cancelling = false;

  Future<void> _confirmCancel() async {
    final r = widget.request;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
          SizedBox(width: 8),
          Text('Cancel Collaboration?'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will permanently cancel the request.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            _InfoRow('Request ID', 'collab-${r.id.substring(0, 12)}'),
            const SizedBox(height: 8),
            _InfoRow('Members', r.targetSupervisorNames.join(', ')),
            const SizedBox(height: 8),
            _InfoRow('Alert type', r.alertType ?? '—'),
            const SizedBox(height: 8),
            _InfoRow(
                'Description',
                (r.alertDescription?.isNotEmpty ?? false)
                    ? r.alertDescription!
                    : '—'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.cancel, size: 16),
            label: const Text('Cancel Request'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await CollaborationService().cancelCollaborationRequest(
          widget.request.id, widget.request.alertId);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final r = widget.request;
    final canCancel = !r.pmApproved && r.status != 'rejected';

    // Calculate overall assistant status
    final allAccepted = r.targetSupervisorIds.isNotEmpty &&
        r.targetSupervisorIds.every(
          (id) => (r.assistantDecisions[id] ?? 'pending') == 'accepted',
        );
    final anyRefused = r.assistantDecision == 'refused' ||
        r.targetSupervisorIds.any(
          (id) => (r.assistantDecisions[id] ?? 'pending') == 'refused',
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: anyRefused ? _red.withOpacity(0.4) : t.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Row(children: [
            Icon(Icons.send, color: _purple, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Sent Request',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: t.navy)),
            ),
            _StatusBadge(r),
          ]),
          const SizedBox(height: 4),
          Text('ID: collab-${r.id.substring(0, 12)}',
              style: TextStyle(
                  fontSize: 10, color: t.muted, fontFamily: 'monospace')),
          const SizedBox(height: 14),

          // Progress steps
          _ProgressStep(
            t,
            icon: Icons.check_circle,
            title: 'Request Sent',
            subtitle: 'Sent to ${r.targetSupervisorNames.join(", ")}',
            state: _StepState.done,
          ),
          // Assistant responses – one line per supervisor
          ...List.generate(r.targetSupervisorIds.length, (i) {
            final id = r.targetSupervisorIds[i];
            final name = r.targetSupervisorNames[i];
            final decision = r.assistantDecisions[id] ?? 'pending';
            final state = decision == 'accepted'
                ? _StepState.done
                : decision == 'refused'
                    ? _StepState.failed
                    : _StepState.waiting;
            return _ProgressStep(
              t,
              icon: state == _StepState.done
                  ? Icons.check_circle
                  : state == _StepState.failed
                      ? Icons.cancel
                      : Icons.pending,
              title: name,
              subtitle: decision == 'accepted'
                  ? 'Accepted'
                  : decision == 'refused'
                      ? 'Declined'
                      : 'Waiting',
              state: state,
            );
          }),
          _ProgressStep(
            t,
            icon: Icons.admin_panel_settings,
            title: 'PM Approval',
            subtitle: r.pmApproved
                ? 'Approved by Production Manager'
                : r.status == 'rejected'
                    ? (r.assistantDecision == 'refused'
                        ? 'All assistants declined'
                        : 'Declined by Production Manager')
                    : r.assistantDecision == 'accepted'
                        ? (allAccepted
                            ? 'All assistants accepted — awaiting PM'
                            : 'Some assistants declined — awaiting PM')
                        : 'Waiting for assistants to respond',
            state: r.pmApproved
                ? _StepState.done
                : r.status == 'rejected'
                    ? _StepState.declined
                    : _StepState.waiting,
            isLast: true,
          ),

          if (!r.pmApproved && r.assistantDecision != 'accepted' && r.status != 'rejected') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.blueLt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.blue.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: t.blue, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Awaiting assistant responses before Production Manager review.',
                    style: TextStyle(fontSize: 11, color: t.blue),
                  ),
                ),
              ]),
            ),
          ],

          if (canCancel) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _cancelling ? null : _confirmCancel,
                icon: _cancelling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.red))
                    : const Icon(Icons.cancel, size: 16, color: Colors.red),
                label: Text(_cancelling ? 'Cancelling…' : 'Cancel Request',
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  backgroundColor: Colors.red.withOpacity(0.06),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// RECEIVED CARD — shown to the targeted assistant (Accept / Decline)
// ============================================================================
class _ReceivedCard extends StatefulWidget {
  final CollaborationRequest request;
  final String userId;
  const _ReceivedCard({required this.request, required this.userId});

  @override
  State<_ReceivedCard> createState() => _ReceivedCardState();
}

class _ReceivedCardState extends State<_ReceivedCard> {
  bool _loading = false;

  Future<void> _respond(bool accept) async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser!;
    try {
      await CollaborationService().respondToCollaborationRequest(
        requestId: widget.request.id,
        responderId: user.uid,
        responderName: user.email?.split('@').first ?? 'Supervisor',
        accepted: accept,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accept
              ? 'Collaboration accepted. Waiting for PM approval.'
              : 'Collaboration declined.'),
          backgroundColor: accept ? _green : _red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final r = widget.request;
    final myDecision = r.assistantDecisions[widget.userId];
    final isAccepted = myDecision == 'accepted';
    final isRefused = myDecision == 'refused';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAccepted
              ? _green.withOpacity(0.5)
              : isRefused
                  ? _red.withOpacity(0.4)
                  : _purple.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(Icons.inbox, color: _purple, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Collaboration Request',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: t.navy)),
            ),
            if (isAccepted)
              _chip('Accepted', _green, _greenLt)
            else if (isRefused)
              _chip('Declined', _red, _red.withOpacity(0.1))
            else if (r.pmApproved)
              _chip('PM Approved', _green, _greenLt)
            else
              _chip('Awaiting you', _purple, _purpleLt),
          ]),
          const SizedBox(height: 12),

          // Alert info block
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.scaffold,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: t.orange),
                const SizedBox(width: 6),
                Text(_typeLabel(r.alertType ?? ''),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.text)),
              ]),
              const SizedBox(height: 4),
              Text(
                '${r.usine ?? "—"}  ·  Line ${r.convoyeur ?? "—"}  ·  Post ${r.poste ?? "—"}',
                style: TextStyle(fontSize: 11, color: t.muted),
              ),
              if (r.alertDescription?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(r.alertDescription!,
                    style: TextStyle(fontSize: 12, color: t.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          const SizedBox(height: 10),

          // Requester info
          Row(children: [
            Icon(Icons.person_outline, size: 14, color: t.muted),
            const SizedBox(width: 6),
            Text('From: ', style: TextStyle(fontSize: 12, color: t.muted)),
            Text(r.requesterName,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: t.navy)),
          ]),

          // Message
          if (r.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.scaffold,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.border),
              ),
              child: Text(r.message,
                  style: TextStyle(fontSize: 12, color: t.text),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
          const SizedBox(height: 14),

          // Decision area
          if (r.pmApproved) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _greenLt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, size: 16, color: _green),
                const SizedBox(width: 8),
                Text('Collaboration fully approved by Production Manager',
                    style: const TextStyle(
                        fontSize: 12,
                        color: _green,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ] else if (isAccepted) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _greenLt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, size: 16, color: _green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('You accepted. Waiting for all assistants.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: _green,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ] else if (isRefused) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _red.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.cancel, size: 16, color: _red),
                const SizedBox(width: 8),
                Text('You declined this request.',
                    style: const TextStyle(
                        fontSize: 12,
                        color: _red,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ] else ...[
            // Pending — show Accept / Decline
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _respond(false),
                  icon: const Icon(Icons.close, size: 16, color: _red),
                  label: const Text('Decline',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _red)),
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
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : () => _respond(true),
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle, size: 16),
                  label: const Text('Accept',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

// ============================================================================
// SHARED HELPERS
// ============================================================================

enum _StepState { done, failed, declined, waiting }

class _ProgressStep extends StatelessWidget {
  final AppTheme t;
  final IconData icon;
  final String title;
  final String subtitle;
  final _StepState state;
  final bool isLast;

  const _ProgressStep(
    this.t, {
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = state == _StepState.done;
    final isFailed = state == _StepState.failed;
    final isDeclined = state == _StepState.declined;
    final circleColor = isDone
        ? _green
        : isFailed
            ? _red
            : isDeclined
                ? _red.withValues(alpha: 0.12)
                : t.scaffold;
    final borderColor = isDone
        ? _green
        : (isFailed || isDeclined)
            ? _red
            : t.border;
    final iconColor = isDone
        ? Colors.white
        : isFailed
            ? Colors.white
            : isDeclined
                ? _red
                : t.muted;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2)),
          child: Icon(
            isDone
                ? Icons.check
                : (isFailed || isDeclined)
                    ? Icons.close
                    : icon,
            color: iconColor,
            size: 15,
          ),
        ),
        if (!isLast)
          Container(
            width: 2,
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
                color: isDone
                    ? _green
                    : isFailed
                        ? _red.withValues(alpha: 0.4)
                        : t.border,
                borderRadius: BorderRadius.circular(1)),
          ),
      ]),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(top: 6, bottom: isLast ? 0 : 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDone
                        ? t.navy
                        : (isFailed || isDeclined)
                            ? _red
                            : t.muted)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: t.muted)),
          ]),
        ),
      ),
    ]);
  }
}

class _StatusBadge extends StatelessWidget {
  final CollaborationRequest r;
  const _StatusBadge(this.r);

  @override
  Widget build(BuildContext context) {
    if (r.pmApproved) return _badge('Approved', _green);
    if (r.status == 'rejected' || r.assistantDecision == 'refused')
      return _badge('Declined', _red);
    if (r.assistantDecision == 'accepted')
      return _badge('PM Pending', Colors.orange);
    return _badge('Pending', _purple);
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withOpacity(0.4))),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.appTheme.muted)),
          ),
          Expanded(
              child: Text(value,
                  style:
                      TextStyle(fontSize: 12, color: context.appTheme.text))),
        ],
      );
}

String _typeLabel(String type) => switch (type) {
      'qualite' => 'Quality',
      'maintenance' => 'Maintenance',
      'defaut_produit' => 'Damaged Product',
      'manque_ressource' => 'Resource Deficiency',
      _ => type.isEmpty ? 'Unknown' : type,
    };

// ============================================================================
// REQUEST COLLABORATION DIALOG (send new request)
// ============================================================================
class RequestCollaborationDialog extends StatefulWidget {
  final AlertModel alert;
  const RequestCollaborationDialog({super.key, required this.alert});

  @override
  State<RequestCollaborationDialog> createState() =>
      _RequestCollaborationDialogState();
}

class _RequestCollaborationDialogState
    extends State<RequestCollaborationDialog> {
  final _service = CollaborationService();
  final _authService = AuthService();
  final _messageController = TextEditingController();
  List<UserModel> _supervisors = [];
  List<UserModel> _selectedSupervisors = [];
  bool _loading = true;
  bool _sending = false;
  String? _blockReason;

  @override
  void initState() {
    super.initState();
    _messageController.text =
        'Hi team! I need help with this ${widget.alert.type} alert at ${widget.alert.usine} '
        '(Line ${widget.alert.convoyeur}, Workstation ${widget.alert.poste}). '
        'Can you collaborate with me on this?\n\nIssue: ${widget.alert.description}\n\nThanks!';
    _loadSupervisors();
  }

  Future<void> _loadSupervisors() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Check if the user already has an active outgoing request.
    final hasActive =
        uid != null ? await _service.hasActiveCollaborationRequest(uid) : false;

    final sups = await _authService.getActiveSupervisors();
    final filtered = sups.where((s) => s.id != uid).toList();

    if (mounted) {
      setState(() {
        _supervisors = filtered;
        _loading = false;
        _blockReason = hasActive
            ? 'You already have a pending collaboration request. Cancel it before sending a new one.'
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.scaffold,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(children: [
                const Icon(Icons.people, color: _purple, size: 22),
                const SizedBox(width: 8),
                Text('Request Collaboration',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: t.navy)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: t.muted),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            Divider(height: 1, color: t.border),

            // Blocked banner
            if (_blockReason != null)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _red.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.block, color: _red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_blockReason!,
                        style: const TextStyle(fontSize: 12, color: _red)),
                  ),
                ]),
              ),

            if (_blockReason == null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tag supervisors to help with this alert (requires PM approval)',
                        style: TextStyle(fontSize: 12, color: t.muted),
                      ),
                      const SizedBox(height: 14),

                      // Alert Info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.orangeLt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: t.orange.withOpacity(0.4)),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.alert.type,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: t.orange)),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.alert.usine} - Line ${widget.alert.convoyeur} - Workstation ${widget.alert.poste}',
                                style: TextStyle(fontSize: 11, color: t.muted),
                              ),
                            ]),
                      ),
                      const SizedBox(height: 16),

                      // Supervisor Selection
                      Text('SELECT SUPERVISOR(S)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: t.muted,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildSupervisorList(t),

                      if (_selectedSupervisors.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('TAGGED',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: t.muted,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedSupervisors
                              .map((sup) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                        color: _purple,
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('@${sup.fullName}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () => setState(() =>
                                                _selectedSupervisors
                                                    .remove(sup)),
                                            child: const Icon(Icons.close,
                                                size: 14, color: Colors.white),
                                          ),
                                        ]),
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Message
                      Text('MESSAGE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: t.muted,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _messageController,
                        maxLines: 5,
                        style: TextStyle(fontSize: 13, color: t.text),
                        decoration: InputDecoration(
                          hintText: 'Enter your message...',
                          hintStyle: TextStyle(color: t.muted),
                          filled: true,
                          fillColor: t.scaffold,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: t.border)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: t.border)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: _purple, width: 2)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Divider(height: 1, color: t.border),
            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    side: BorderSide(color: t.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cancel',
                      style: TextStyle(fontSize: 13, color: t.muted)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: (_selectedSupervisors.isEmpty ||
                          _sending ||
                          _blockReason != null)
                      ? null
                      : () => _sendRequest(context),
                  icon: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 16),
                  label: const Text('Send Request',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupervisorList(AppTheme t) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(8)),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _supervisors.length,
        itemBuilder: (context, index) {
          final sup = _supervisors[index];
          final isSelected = _selectedSupervisors.contains(sup);
          return ListTile(
            dense: true,
            leading: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: _green, shape: BoxShape.circle),
            ),
            title: Text(sup.fullName,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: t.navy)),
            subtitle:
                Text(sup.usine, style: TextStyle(fontSize: 11, color: t.muted)),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: _purple, size: 18)
                : null,
            selected: isSelected,
            selectedTileColor: _purple.withOpacity(0.08),
            onTap: () => setState(() {
              if (isSelected) {
                _selectedSupervisors.remove(sup);
              } else {
                _selectedSupervisors.add(sup);
              }
            }),
          );
        },
      ),
    );
  }

  Future<void> _sendRequest(BuildContext context) async {
    if (_selectedSupervisors.isEmpty) return;
    setState(() => _sending = true);

    final currentUser = FirebaseAuth.instance.currentUser!;
    final requesterName = currentUser.email?.split('@').first ?? 'Supervisor';

    try {
      await _service.createCollaborationRequest(
        alertId: widget.alert.id,
        requesterId: currentUser.uid,
        requesterName: requesterName,
        targetSupervisorIds: _selectedSupervisors.map((s) => s.id).toList(),
        targetSupervisorNames:
            _selectedSupervisors.map((s) => s.fullName).toList(),
        message: _messageController.text,
        usine: widget.alert.usine,
        convoyeur: widget.alert.convoyeur,
        poste: widget.alert.poste,
        alertType: widget.alert.type,
        alertDescription: widget.alert.description,
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Collaboration request sent!'),
        backgroundColor: _green,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}

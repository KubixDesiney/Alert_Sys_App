import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/alert_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';
import '../theme.dart';

const _navy = AppColors.navy;
const _purple = Color(0xFF9333EA);
const _white = Colors.white;
const _bg = AppColors.bg;
const _border = AppColors.border;
const _muted = AppColors.mutedDark;
const _green = Color(0xFF16A34A);
const _red = AppColors.red;

class CollaborationProgressScreen extends StatelessWidget {
  const CollaborationProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final service = CollaborationService();

    return Scaffold(
      backgroundColor: context.appTheme.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.shield, color: _purple, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Collab Progress',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ],
              ),
            ),
            // Swipe hint
            Center(
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFFCBD5E1),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 20,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFFCBD5E1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '← Swipe to navigate →',
                    style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Content
            Expanded(
              child: StreamBuilder<List<CollaborationRequest>>(
                stream: service.getCollaborationRequestsForSupervisor(userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmpty();
                  }
                  final requests = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      return _CollaborationCard(request: request);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.groups, size: 48, color: _purple),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Collaboration Requests',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your collaboration requests will appear here',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _CollaborationCard extends StatefulWidget {
  final CollaborationRequest request;
  const _CollaborationCard({required this.request});

  @override
  State<_CollaborationCard> createState() => _CollaborationCardState();
}

class _CollaborationCardState extends State<_CollaborationCard> {
  bool _cancelling = false;

  Future<void> _confirmCancel(BuildContext context) async {
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
            const Text('This will permanently cancel the request.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            _DialogDetail(label: 'Request ID', value: 'collab-${r.id.substring(0, 12)}'),
            const SizedBox(height: 8),
            _DialogDetail(
              label: 'Members',
              value: r.targetSupervisorNames.join(', '),
            ),
            const SizedBox(height: 8),
            _DialogDetail(
              label: 'Alert type',
              value: r.alertType ?? '—',
            ),
            const SizedBox(height: 8),
            _DialogDetail(
              label: 'Description',
              value: (r.alertDescription?.isNotEmpty ?? false) ? r.alertDescription! : '—',
            ),
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
      await CollaborationService()
          .cancelCollaborationRequest(r.id, r.alertId);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final r = widget.request;
    final canCancel = !r.pmApproved && r.status != 'rejected';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.send, color: _purple, size: 20),
              const SizedBox(width: 8),
              Text(
                'Collaboration Request Progress',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: t.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Request ID: collab-${r.id.substring(0, 12)}',
            style: TextStyle(
              fontSize: 11,
              color: t.muted,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          _buildProgressStep(t, Icons.check_circle,
            title: 'Request Sent',
            subtitle: 'Sent to ${r.targetSupervisorNames.join(", ")}',
            isCompleted: true,
          ),
          _buildProgressStep(t, Icons.pending,
            title: 'Assistant Response',
            subtitle: r.assistantDecision == 'accepted'
                ? 'Accepted by ${r.assistantName ?? r.targetSupervisorNames.first}'
                : r.assistantDecision == 'refused'
                    ? 'Refused by ${r.assistantName ?? r.targetSupervisorNames.first}'
                    : 'Waiting for ${r.targetSupervisorNames.first} to accept or refuse',
            isCompleted: r.assistantDecision == 'accepted',
          ),
          _buildProgressStep(t, Icons.admin_panel_settings,
            title: 'Production Manager Approval',
            subtitle: r.pmApproved
                ? 'Approved by Production Manager'
                : 'Waiting for PM final approval',
            isCompleted: r.pmApproved,
            isLast: true,
          ),
          if (!r.pmApproved) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.blueLt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.blue.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: t.blue, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reviewed by assistant first, then by Production Manager.',
                    style: TextStyle(fontSize: 11, color: t.blue),
                  ),
                ),
              ]),
            ),
          ],
          if (canCancel) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _cancelling ? null : () => _confirmCancel(context),
                icon: _cancelling
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                    : const Icon(Icons.cancel, size: 16, color: Colors.red),
                label: Text(
                  _cancelling ? 'Cancelling…' : 'Cancel Request',
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  backgroundColor: Colors.red.withValues(alpha: 0.06),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressStep(AppTheme t, IconData icon, {
    required String title,
    required String subtitle,
    required bool isCompleted,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCompleted ? _green : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted ? _green : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: Icon(
                isCompleted ? Icons.check : icon,
                color: isCompleted ? _white : _muted,
                size: 16,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isCompleted ? _green : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isCompleted ? _navy : _muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: _muted),
              ),
              if (!isLast) const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialogDetail extends StatelessWidget {
  final String label;
  final String value;
  const _DialogDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B))),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

// Dialog for requesting collaboration
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

  @override
  void initState() {
    super.initState();
    _loadSupervisors();
    _messageController.text =
        'Hi team! I need help with this ${widget.alert.type} alert at ${widget.alert.usine} (Line ${widget.alert.convoyeur}, Workstation ${widget.alert.poste}). Can you collaborate with me on this?\n\nIssue: ${widget.alert.description}\n\nThanks for your support!';
  }

Future<void> _loadSupervisors() async {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final sups = await _authService.getActiveSupervisors();
  // Show all supervisors from any factory, excluding current user
  final filtered = sups.where((s) => s.id != currentUserId).toList();
  setState(() {
    _supervisors = filtered;
    _loading = false;
  });
}

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: _purple, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Request Collaboration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tag supervisors to help you with this alert (requires PM approval)',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(height: 16),
                    // Alert Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.alert.type,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.alert.usine} - Line ${widget.alert.convoyeur} - Workstation ${widget.alert.poste}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Supervisor Selection
                    const Text(
                      'SELECT SUPERVISOR(S)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _muted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      _buildSupervisorList(),
                    if (_selectedSupervisors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'TAGGED SUPERVISORS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _muted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedSupervisors.map((sup) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _purple,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '@${sup.fullName}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedSupervisors.remove(sup);
                                    });
                                  },
                                  child: const Icon(Icons.close,
                                      size: 14, color: _white),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Message
                    const Text(
                      'MESSAGE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _muted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _messageController,
                      maxLines: 6,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Enter your message...',
                        hintStyle: TextStyle(color: _muted.withOpacity(0.5)),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _purple, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This message will be posted to the Supervisors Feed with tags',
                      style: TextStyle(fontSize: 10, color: _muted),
                    ),
                    const SizedBox(height: 16),
                    // Preview
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Preview:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (_selectedSupervisors.isNotEmpty)
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF1E40AF),
                                ),
                                children: [
                                  const TextSpan(text: 'Tagging: '),
                                  ..._selectedSupervisors
                                      .map((sup) => TextSpan(
                                            text: '@${sup.fullName} ',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ))
                                      .toList(),
                                ],
                              ),
                            ),
                          if (_selectedSupervisors.isNotEmpty)
                            const SizedBox(height: 4),
                          Text(
                            _messageController.text,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      side: const BorderSide(color: _border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _selectedSupervisors.isEmpty
                        ? null
                        : () => _sendRequest(context),
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text(
                      'Send Request',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: _white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      disabledBackgroundColor: _muted.withOpacity(0.3),
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

  Widget _buildSupervisorList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _supervisors.length,
        itemBuilder: (context, index) {
          final sup = _supervisors[index];
          final isSelected = _selectedSupervisors.contains(sup);
          final isWorking = sup.status == 'active'; // Assuming active means working

          return ListTile(
            dense: true,
            enabled: isWorking,
            leading: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isWorking ? _green : _muted,
                shape: BoxShape.circle,
              ),
            ),
            title: Text(
              sup.fullName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isWorking ? _navy : _muted,
              ),
            ),
            subtitle: Text(
              sup.usine,
              style: TextStyle(fontSize: 11, color: _muted),
            ),
            trailing: isWorking
                ? (sup.status == 'active' && !isWorking
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Working',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFEA580C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : null)
                : null,
            selected: isSelected,
            selectedTileColor: _purple.withOpacity(0.1),
            onTap: isWorking
                ? () {
                    setState(() {
                      if (isSelected) {
                        _selectedSupervisors.remove(sup);
                      } else {
                        _selectedSupervisors.add(sup);
                      }
                    });
                  }
                : null,
          );
        },
      ),
    );
  }

  Future<void> _sendRequest(BuildContext context) async {
    if (_selectedSupervisors.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser!;
    final requesterName =
        currentUser.email?.split('@').first ?? 'Supervisor';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Collaboration request sent successfully!'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending request: $e'),
          backgroundColor: _red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}

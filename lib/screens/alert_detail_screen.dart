import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/alert_model.dart';
import '../providers/alert_provider.dart';
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';
import '../services/ai_assignment_service.dart';

class AlertDetailScreen extends StatefulWidget {
  final String alertId;
  final String? collabRequestId;
  final bool showCollaborationDecision;
  const AlertDetailScreen({
    super.key,
    required this.alertId,
    this.collabRequestId,
    this.showCollaborationDecision = false,
  });

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late Future<AlertModel> _alertFuture;
  Future<CollaborationRequest?>? _collabFuture;
  final _commentController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isAiLoading = false;
  String? _aiSuggestion;
  final _collabService = CollaborationService();

  // AI auto-assignment metadata pulled from /alerts/{id}.
  bool _aiAssigned = false;
  String? _aiReason;
  double? _aiConfidence;
  bool _isRejecting = false;

  @override
  void initState() {
    super.initState();
    _alertFuture = _loadAlert();
    _loadAIMetadata();
    if (widget.showCollaborationDecision && widget.collabRequestId != null) {
      _collabFuture = _collabService.getCollaborationRequest(widget.collabRequestId!);
    }
  }

  Future<void> _loadAIMetadata() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('alerts/${widget.alertId}')
          .get();
      if (!snap.exists || !mounted) return;
      final data = Map<String, dynamic>.from(snap.value as Map);
      setState(() {
        _aiAssigned = data['aiAssigned'] == true;
        _aiReason = data['aiAssignmentReason']?.toString();
        _aiConfidence = (data['aiConfidence'] as num?)?.toDouble();
      });
    } catch (_) {}
  }

  Future<void> _rejectAIAssignment(AlertModel alert) async {
    if (_isRejecting) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.thumb_down_outlined, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 10),
            Text('Reject AI assignment?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This alert will be returned to the queue and the Production Manager will be notified.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Optional reason (e.g. wrong factory, busy elsewhere)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.thumb_down, size: 16, color: Colors.white),
            label: const Text('Reject',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRejecting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      final name = user?.email?.split('@').first ?? 'Supervisor';
      await AIAssignmentService.instance.handleSupervisorRejection(
        alertId: alert.id,
        supervisorId: uid,
        supervisorName: name,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI assignment rejected — alert returned to the queue'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject: $e')),
      );
    } finally {
      if (mounted) setState(() => _isRejecting = false);
    }
  }

  Future<AlertModel> _loadAlert() async {
    final provider = context.read<AlertProvider>();
    final local = provider.allAlerts;
    try {
      return local.firstWhere((a) => a.id == widget.alertId);
    } catch (_) {
      final snap = await FirebaseDatabase.instance.ref('alerts/${widget.alertId}').get();
      if (!snap.exists || snap.value == null) {
        throw Exception('Alert not found');
      }
      return AlertModel.fromMap(
        widget.alertId,
        Map<String, dynamic>.from(snap.value as Map),
      );
    }
  }

  void _addComment(AlertProvider provider, AlertModel alert) async {
    if (_commentController.text.trim().isEmpty) return;
    await provider.addComment(alert.id, _commentController.text.trim());
    setState(() {
      _alertFuture = _loadAlert();
      _commentController.clear();
    });
  }

  void _resolveWithReason(AlertProvider provider, AlertModel alert) async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a resolution reason')));
      return;
    }
    await provider.resolveAlert(alert.id, reason);
    if (mounted) Navigator.pop(context);
  }

 Future<void> _getAiAssist(AlertModel alert) async {
  setState(() {
    _isAiLoading = true;
    _aiSuggestion = null;
  });
  // Simulate network delay
  await Future.delayed(const Duration(seconds: 2));
  setState(() {
    _aiSuggestion = '• Check the ${alert.type} sensor calibration.\n• Restart the affected machine.\n• If the issue persists, escalate to maintenance.';
    _isAiLoading = false;
  });
}

  Future<void> _respondToCollab({
    required bool accepted,
    required CollaborationRequest request,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final name = user.email?.split('@').first ?? 'Supervisor';
    try {
      await _collabService.respondToCollaborationRequest(
        requestId: request.id,
        responderId: uid,
        responderName: name,
        accepted: accepted,
      );
      if (!mounted) return;
      setState(() {
        _collabFuture = _collabService.getCollaborationRequest(request.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepted
              ? 'Collaboration accepted. Waiting for PM approval.'
              : 'Collaboration refused.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlertProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Alert Details')),
      body: FutureBuilder<AlertModel>(
        future: _alertFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final alert = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Alert info card
                Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Type: ${alert.type}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Location: ${alert.usine} - Line ${alert.convoyeur} - Post ${alert.poste}'),
                    Text('Address: ${alert.adresse}'),
                    Text('Description: ${alert.description}'),
                    Text('Timestamp: ${alert.timestamp}'),
                    if (alert.status == 'en_cours' && alert.takenAtTimestamp != null)
                      Text('Elapsed: ${provider.getElapsedTime(alert)}', style: const TextStyle(color: Colors.blue)),
                    if (alert.status == 'validee' && alert.elapsedTime != null)
                      Text('Resolution time: ${provider.formatElapsedTime(alert.elapsedTime)}', style: const TextStyle(color: Colors.green)),
                    if (alert.resolutionReason != null)
                      Text('Reason: ${alert.resolutionReason}'),
                  ]),
                )),
                const SizedBox(height: 12),

                if (_aiAssigned) _buildAIBadge(),

                const SizedBox(height: 4),

                if (widget.showCollaborationDecision &&
                    widget.collabRequestId != null &&
                    _collabFuture != null) ...[
                  FutureBuilder<CollaborationRequest?>(
                    future: _collabFuture,
                    builder: (context, collabSnap) {
                      if (collabSnap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        );
                      }
                      final req = collabSnap.data;
                      if (req == null) return const SizedBox.shrink();

                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      final isTarget = uid != null && req.targetSupervisorIds.contains(uid);

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Collaboration Request',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text('From: ${req.requesterName}'),
                              const SizedBox(height: 4),
                              Text(req.message),
                              const SizedBox(height: 12),
                              if (!isTarget)
                                const Text(
                                  'You are not a target for this collaboration request.',
                                  style: TextStyle(color: Colors.grey),
                                )
                              else if (req.assistantDecision == 'pending')
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _respondToCollab(
                                          accepted: false,
                                          request: req,
                                        ),
                                        icon: const Icon(Icons.close, color: Colors.white),
                                        label: const Text('Decline'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFFFB3BA), // Light red
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _respondToCollab(
                                          accepted: true,
                                          request: req,
                                        ),
                                        icon: const Icon(Icons.check, color: Colors.white),
                                        label: const Text('Approve'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  'Decision: ${req.assistantDecision}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // AI Assist button (only if not resolved)
                if (alert.status != 'validee') ...[
                  ElevatedButton.icon(
                    onPressed: _isAiLoading ? null : () => _getAiAssist(alert),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('AI Assist'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  ),
                  if (_isAiLoading)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: LinearProgressIndicator(),
                    ),
                  if (_aiSuggestion != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        border: Border.all(color: Colors.purple),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                            SizedBox(width: 6),
                            Text('AI Suggestion', style: TextStyle(fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 4),
                          Text(_aiSuggestion!),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                // Comments section
                const Text('Comments', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...alert.comments.map((c) => ListTile(title: Text(c))),
                Row(children: [
                  Expanded(child: TextField(controller: _commentController, decoration: const InputDecoration(hintText: 'Add comment...'))),
                  IconButton(onPressed: () => _addComment(provider, alert), icon: const Icon(Icons.send)),
                ]),
                const SizedBox(height: 16),

                // Action buttons
                if (alert.status == 'disponible')
                  ElevatedButton(onPressed: () => provider.takeAlert(alert.id, provider.currentSuperviseurId, provider.currentSuperviseurName), child: const Text('Claim')),
                if (alert.status == 'en_cours' && alert.superviseurId == provider.currentSuperviseurId) ...[
                  Row(children: [
                    Expanded(child: ElevatedButton(onPressed: () => provider.returnToQueue(alert.id), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('Detach'))),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton(onPressed: () => _showResolveDialog(provider, alert), child: const Text('Resolve'))),
                  ]),
                  if (_aiAssigned) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isRejecting ? null : () => _rejectAIAssignment(alert),
                        icon: _isRejecting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFFEF4444)),
                              )
                            : const Icon(Icons.thumb_down_outlined,
                                size: 16, color: Color(0xFFEF4444)),
                        label: Text(
                          _isRejecting ? 'Rejecting…' : 'Reject AI Assignment',
                          style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE2E2),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAIBadge() {
    final pct = _aiConfidence != null ? (_aiConfidence! * 100).round() : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFF2563EB),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_outlined,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Assigned by Automated AI',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E40AF)),
                    ),
                    if (pct != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$pct%',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ],
                  ],
                ),
                if (_aiReason != null && _aiReason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _aiReason!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF1E40AF)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showResolveDialog(AlertProvider provider, AlertModel alert) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Resolve Alert'),
      content: TextField(controller: _reasonController, decoration: const InputDecoration(hintText: 'Resolution reason'), maxLines: 3),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => _resolveWithReason(provider, alert), child: const Text('Resolve')),
      ],
    ));
  }
}

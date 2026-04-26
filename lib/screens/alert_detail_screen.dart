import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/alert_model.dart';
import '../providers/alert_provider.dart';
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';
import '../theme.dart';

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

  @override
  void initState() {
    super.initState();
    _alertFuture = _loadAlert();
    if (widget.showCollaborationDecision && widget.collabRequestId != null) {
      _collabFuture = _collabService.getCollaborationRequest(widget.collabRequestId!);
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

  Widget _collabStatusBanner(
      IconData icon, String message, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ),
      ]),
    );
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
                const SizedBox(height: 16),

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

                      final t = context.appTheme;
                      final myDecision = req.assistantDecisions[uid];
                      final decided =
                          myDecision == 'accepted' || myDecision == 'refused';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: decided
                                ? (myDecision == 'accepted'
                                    ? const Color(0xFF16A34A)
                                    : Colors.red)
                                    .withValues(alpha: 0.4)
                                : const Color(0xFF9333EA).withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(children: [
                              const Icon(Icons.people,
                                  color: Color(0xFF9333EA), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('Collaboration Request',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: t.navy)),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            // Requester
                            Row(children: [
                              Icon(Icons.person_outline, size: 14, color: t.muted),
                              const SizedBox(width: 6),
                              Text('From: ',
                                  style: TextStyle(fontSize: 13, color: t.muted)),
                              Text(req.requesterName,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: t.navy)),
                            ]),
                            // Message
                            if (req.message.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: t.scaffold,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: t.border)),
                                child: Text(req.message,
                                    style: TextStyle(fontSize: 12, color: t.text),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                            const SizedBox(height: 14),
                            if (!isTarget)
                              Text('You are not a target for this request.',
                                  style: TextStyle(color: t.muted, fontSize: 13))
                            else if (req.pmApproved)
                              _collabStatusBanner(
                                  Icons.verified, 'Fully approved by PM',
                                  const Color(0xFF16A34A),
                                  const Color(0xFFDCFCE7))
                            else if (myDecision == 'accepted')
                              _collabStatusBanner(
                                  Icons.check_circle,
                                  'You accepted — waiting for PM approval',
                                  const Color(0xFF16A34A),
                                  const Color(0xFFDCFCE7))
                            else if (myDecision == 'refused')
                              _collabStatusBanner(
                                  Icons.cancel,
                                  'You declined this request',
                                  Colors.red,
                                  Colors.red.withValues(alpha: 0.08))
                            else
                              Row(children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _respondToCollab(accepted: false, request: req),
                                    icon: const Icon(Icons.close,
                                        size: 16, color: Colors.red),
                                    label: const Text('Decline',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
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
                                    onPressed: () =>
                                        _respondToCollab(accepted: true, request: req),
                                    icon: const Icon(Icons.check_circle, size: 16),
                                    label: const Text('Accept',
                                        style: TextStyle(fontWeight: FontWeight.w600)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      foregroundColor: Colors.white,
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
                ],
              ],
            ),
          );
        },
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

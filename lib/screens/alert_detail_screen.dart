import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alert_model.dart';
import '../providers/alert_provider.dart';
import '../services/ai_service.dart';

class AlertDetailScreen extends StatefulWidget {
  final String alertId;
  const AlertDetailScreen({super.key, required this.alertId});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late Future<AlertModel> _alertFuture;
  final _commentController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isAiLoading = false;
  String? _aiSuggestion;

  @override
  void initState() {
    super.initState();
    _alertFuture = _loadAlert();
  }

  Future<AlertModel> _loadAlert() async {
    final provider = context.read<AlertProvider>();
    await Future.delayed(const Duration(milliseconds: 500));
    final all = [...provider.availableAlerts, ...provider.inProgressAlerts(provider.currentSuperviseurId), ...provider.validatedAlerts(provider.currentSuperviseurId)];
    return all.firstWhere((a) => a.id == widget.alertId);
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
                          const Text('💡 AI Suggestion', style: TextStyle(fontWeight: FontWeight.bold)),
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
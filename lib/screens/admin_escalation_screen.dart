import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';
import '../models/alert_model.dart';
import '../theme.dart';

const _navy = AppColors.navy;
const _white = AppColors.white;
const _bg = AppColors.bg;
const _border = AppColors.border;
const _muted = AppColors.mutedDark;
const _green = AppColors.green;
const _greenLt = AppColors.greenLight;
const _red = AppColors.red;
const _redLt = Color(0xFFFEE2E2);
const _orange = AppColors.orange;
const _orangeLt = AppColors.orangeLight;
const _blue = AppColors.blue;
const _blueLt = AppColors.blueLight;
const _yellow = Color(0xFFFBBF24);
const _yellowLt = Color(0xFFFEF3C7);
const _purple = Color(0xFF9333EA);

// ignore: unused_element
Color _typeColor(String type) => switch (type) {
      'qualite' => _red,
      'maintenance' => _blue,
      'defaut_produit' => _green,
      'manque_ressource' => _orange,
      _ => _muted,
    };

// ignore: unused_element
Color _typeBgColor(String type) => switch (type) {
      'qualite' => _redLt,
      'maintenance' => _blueLt,
      'defaut_produit' => _greenLt,
      'manque_ressource' => _orangeLt,
      _ => const Color(0xFFF1F5F9),
    };

String _typeLabel(String type) => switch (type) {
      'qualite' => 'Quality Issues',
      'maintenance' => 'Maintenance',
      'defaut_produit' => 'Damaged Product',
      'manque_ressource' => 'Resource Deficiency',
      _ => type,
    };

// ignore: unused_element
IconData _typeIcon(String type) => switch (type) {
      'qualite' => Icons.warning_amber_rounded,
      'maintenance' => Icons.build_circle_outlined,
      'defaut_produit' => Icons.cancel_outlined,
      'manque_ressource' => Icons.inventory_2_outlined,
      _ => Icons.notifications_outlined,
    };

class AdminEscalationScreen extends StatefulWidget {
  const AdminEscalationScreen({super.key});

  @override
  State<AdminEscalationScreen> createState() => _AdminEscalationScreenState();
}

class _AdminEscalationScreenState extends State<AdminEscalationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = CollaborationService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: _white,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, color: _orange, size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Escalations',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Tab Bar
                  Container(
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: _white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      labelColor: _navy,
                      unselectedLabelColor: _muted,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning, size: 16),
                              const SizedBox(width: 6),
                              const Text('Escalated Alerts'),
                              const SizedBox(width: 4),
                              StreamBuilder<List<dynamic>>(
                                stream: _getEscalatedAlertsCount(),
                                builder: (context, snapshot) {
                                  final count = snapshot.data?.length ?? 0;
                                  if (count == 0)
                                    return const SizedBox.shrink();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _red,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined, size: 16),
                              const SizedBox(width: 6),
                              const Text('Collaborations'),
                              const SizedBox(width: 4),
                              StreamBuilder<List<CollaborationRequest>>(
                                stream:
                                    _service.getPendingCollaborationRequests(),
                                builder: (context, snapshot) {
                                  final count = snapshot.data?.length ?? 0;
                                  if (count == 0)
                                    return const SizedBox.shrink();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _red,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.settings, size: 16),
                              SizedBox(width: 6),
                              Text('Settings'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _EscalatedAlertsTab(),
                  _CollaborationsTab(),
                  _SettingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<List<dynamic>> _getEscalatedAlertsCount() {
    // For now, return empty stream - will be implemented when escalated alerts are ready
    return Stream.value([]);
  }
}

// ============================================================================
// ESCALATED ALERTS TAB (Empty for now)
// ============================================================================
class _EscalatedAlertsTab extends StatelessWidget {
  const _EscalatedAlertsTab();

  @override
  Widget build(BuildContext context) {
    final database = FirebaseDatabase.instance.ref();
    return StreamBuilder(
      stream: database.child('alerts').onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final alertsMap = snapshot.data!.snapshot.value;
        if (alertsMap == null) {
          return _buildEmpty();
        }
        final List<MapEntry<String, dynamic>> entries =
            Map<String, dynamic>.from(alertsMap as Map).entries.toList();
        final escalated = entries
            .where((entry) => entry.value['isEscalated'] == true)
            .map(
                (entry) => AlertModel.fromMap(entry.key, Map.from(entry.value)))
            .toList()
          ..sort((a, b) => b.escalatedAt!.compareTo(a.escalatedAt!));

        if (escalated.isEmpty) {
          return _buildEmpty();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: escalated.length,
          itemBuilder: (context, index) {
            final alert = escalated[index];
            return _EscalatedAlertCard(alert: alert);
          },
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber, size: 48, color: _orange),
          const SizedBox(height: 16),
          const Text(
            'No Escalated Alerts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Alerts that exceed time thresholds will appear here',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ],
      ),
    );
  }
}

// Helper widget for each escalated alert
class _EscalatedAlertCard extends StatelessWidget {
  final AlertModel alert;
  const _EscalatedAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _redLt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: _red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_typeLabel(alert.type)} - ${alert.description}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              '📍 ${alert.usine} | Line ${alert.convoyeur} | Post ${alert.poste}'),
          Text('⏰ Escalated at: ${_formatDateTime(alert.escalatedAt!)}'),
          if (alert.status == 'disponible')
            const Text('⚠️ Unclaimed alert exceeded threshold',
                style: TextStyle(color: _red, fontSize: 12))
          else if (alert.status == 'en_cours')
            const Text('⚠️ Claimed but not resolved in time',
                style: TextStyle(color: _red, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// COLLABORATIONS TAB
// ============================================================================
class _CollaborationsTab extends StatelessWidget {
  const _CollaborationsTab();

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
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: _green.withOpacity(0.5)),
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
                return const Center(child: CircularProgressIndicator());
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

class _CollaborationRequestCard extends StatelessWidget {
  final CollaborationRequest request;

  const _CollaborationRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (unchanged)
          Row(
            children: [
              Text(
                request.requesterName,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: _navy),
              ),
              const SizedBox(width: 8),
              Text(
                'Alert #${request.alertId.substring(0, 8)}',
                style: const TextStyle(
                    fontSize: 12, color: _muted, fontFamily: 'monospace'),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: _orange, borderRadius: BorderRadius.circular(12)),
                child: const Text('Pending',
                    style: TextStyle(
                        fontSize: 10,
                        color: _white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('⏰ ${_formatTime(request.timestamp)}',
              style: const TextStyle(fontSize: 11, color: _muted)),
          const SizedBox(height: 12),
          const Text('Requesting collaboration with:',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: request.targetSupervisorNames
                .map((name) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: _purple,
                          borderRadius: BorderRadius.circular(16)),
                      child: Text('@$name',
                          style: const TextStyle(
                              fontSize: 11,
                              color: _white,
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.message,
                    style: const TextStyle(fontSize: 12, color: _navy)),
                const SizedBox(height: 8),
                Text('Issue: ${request.alertDescription}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: _muted,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _handleApprove(context, request),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Approve',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: _white,
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
                    await CollaborationService().rejectCollaborationRequest(
                        request.id, currentUserId, '');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Collaboration rejected'),
                            backgroundColor: _red),
                      );
                    }
                  },
                  icon: const Icon(Icons.cancel, size: 16),
                  label: const Text('Reject',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(
      BuildContext context, CollaborationRequest request) async {
    final service = CollaborationService();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final alertSnapshot =
        await FirebaseDatabase.instance.ref('alerts/${request.alertId}').get();
    if (!alertSnapshot.exists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Alert not found'), backgroundColor: _red));
      return;
    }
    final alertData = Map<String, dynamic>.from(alertSnapshot.value as Map);
    final alertUsine = alertData['usine'] ?? '';

    // 1. Cross-factory detection
    final List<String> crossFactorySupervisors = [];
    for (int i = 0; i < request.targetSupervisorIds.length; i++) {
      final supId = request.targetSupervisorIds[i];
      final supName = request.targetSupervisorNames[i];
      final supSnapshot =
          await FirebaseDatabase.instance.ref('users/$supId').get();
      if (supSnapshot.exists) {
        final supData = Map<String, dynamic>.from(supSnapshot.value as Map);
        final supUsine = supData['usine'] ?? '';
        if (supUsine != alertUsine) {
          crossFactorySupervisors.add(supName);
        }
      }
    }

    // 2. Find existing alerts for target supervisors (as claimant OR assistant)
    final List<String> existingAlertIds = [];
    for (final supId in request.targetSupervisorIds) {
      // As claimant
      final claimantSnapshot = await FirebaseDatabase.instance
          .ref('alerts')
          .orderByChild('superviseurId')
          .equalTo(supId)
          .once();
      if (claimantSnapshot.snapshot.exists) {
        final alertsMap =
            Map<String, dynamic>.from(claimantSnapshot.snapshot.value as Map);
        for (final entry in alertsMap.entries) {
          final alert = Map<String, dynamic>.from(entry.value);
          if (alert['status'] == 'en_cours' ||
              alert['status'] == 'disponible') {
            existingAlertIds.add(entry.key);
          }
        }
      }
      // As assistant
      final assistantSnapshot = await FirebaseDatabase.instance
          .ref('alerts')
          .orderByChild('assistantId')
          .equalTo(supId)
          .once();
      if (assistantSnapshot.snapshot.exists) {
        final alertsMap =
            Map<String, dynamic>.from(assistantSnapshot.snapshot.value as Map);
        for (final entry in alertsMap.entries) {
          final alert = Map<String, dynamic>.from(entry.value);
          if (alert['status'] == 'en_cours' ||
              alert['status'] == 'disponible') {
            existingAlertIds.add(entry.key);
          }
        }
      }
    }

    bool transferConfirmed = false;
    bool cancelConfirmed = false;

    // Helper to approve after all dialogs
    Future<void> doApproval() async {
      await service.approveCollaborationRequestWithDetails(
        requestId: request.id,
        approverId: currentUserId,
        approverName: 'Production Manager',
        isPMApproval: true,
        confirmTransfer: transferConfirmed,
        confirmCancelOriginal: cancelConfirmed,
        cancelExistingAlertIds: cancelConfirmed ? existingAlertIds : null,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Collaboration approved'), backgroundColor: _green),
        );
      }
    }

    // --- Cross-factory dialog ---
    if (crossFactorySupervisors.isNotEmpty) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Cross-Factory Transfer Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Approving this collaboration will require supervisor(s) to be transferred to work on an alert in a different factory.'),
              const SizedBox(height: 16),
              ...crossFactorySupervisors.map((name) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: _orangeLt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _orange.withOpacity(0.3))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                            'Will be transferred from their current factory to $alertUsine',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  )),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: _green),
                child: const Text('Confirm Transfer & Approve')),
          ],
        ),
      );
      if (confirmed != true) return;
      transferConfirmed = true;
      // Continue to next dialog
    }

    // --- Cancel original alert dialog ---
    if (existingAlertIds.isNotEmpty) {
      // Fetch details of existing alerts
      List<Map<String, dynamic>> existingAlertsData = [];
      for (final alertId in existingAlertIds) {
        final alertSnap =
            await FirebaseDatabase.instance.ref('alerts/$alertId').get();
        if (alertSnap.exists) {
          existingAlertsData
              .add(Map<String, dynamic>.from(alertSnap.value as Map));
        }
      }

      final bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Cancel Original Alert(s)?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'The assistant(s) already have an active alert. Approving this collaboration will cancel their current alert(s).'),
              const SizedBox(height: 12),
              ...existingAlertsData.map((alert) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: _redLt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _red.withOpacity(0.3))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '⚠️ Alert: ${alert['description'] ?? 'No description'}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Factory: ${alert['usine'] ?? 'Unknown'}',
                            style: const TextStyle(fontSize: 12)),
                        Text('Status: ${alert['status'] ?? 'unknown'}',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              const Text(
                  'Do you confirm canceling the original alert(s) and approving this collaboration?'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: _green),
                child: const Text('Confirm & Approve')),
          ],
        ),
      );
      if (confirmed != true) return;
      cancelConfirmed = true;
    }

    // Finally approve
    await doApproval();
  }

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
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
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
// SETTINGS TAB
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
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: _green,
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings, color: _navy, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Escalation Time Thresholds',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure default time limits before alerts are escalated to your attention',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 16),
          // Info Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _yellowLt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _yellow.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: _yellow.withOpacity(0.8), size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'How Escalation Works:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF78350F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildInfoBullet(
                    'Unclaimed Alert Threshold: Time before an unclaimed alert is escalated'),
                _buildInfoBullet(
                    'Claimed Alert Threshold: Time a supervisor has to fix a claimed alert before escalation'),
                _buildInfoBullet(
                    'Escalated alerts appear in the "Escalated Alerts" section for immediate attention'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Threshold cards
          _ThresholdCard(
            type: 'qualite',
            label: 'Quality Issues',
            color: _red,
            bgColor: _redLt,
            icon: Icons.warning_amber_rounded,
            threshold: _settings!.thresholds['qualite']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('qualite', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'maintenance',
            label: 'Maintenance',
            color: _blue,
            bgColor: _blueLt,
            icon: Icons.build_circle_outlined,
            threshold: _settings!.thresholds['maintenance']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('maintenance', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'defaut_produit',
            label: 'Damaged Product',
            color: _green,
            bgColor: _greenLt,
            icon: Icons.cancel_outlined,
            threshold: _settings!.thresholds['defaut_produit']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('defaut_produit', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'manque_ressource',
            label: 'Resource Deficiency',
            color: _orange,
            bgColor: _orangeLt,
            icon: Icons.inventory_2_outlined,
            threshold: _settings!.thresholds['manque_ressource']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('manque_ressource', unclaimed, claimed),
          ),
          const SizedBox(height: 24),
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: _white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_white),
                      ),
                    )
                  : const Text(
                      'Save Settings',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(fontSize: 11, color: Color(0xFF78350F))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: Color(0xFF78350F)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdCard extends StatefulWidget {
  final String type;
  final String label;
  final Color color;
  final Color bgColor;
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: widget.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unclaimed Alert Threshold',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _border),
                            ),
                            child: TextField(
                              controller: _unclaimedController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
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
                        Text(
                          'minutes',
                          style: TextStyle(fontSize: 11, color: widget.color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alert escalates if not claimed within this time',
                      style: TextStyle(
                          fontSize: 10, color: widget.color.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Claimed Alert Threshold',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _border),
                            ),
                            child: TextField(
                              controller: _claimedController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              onChanged: (value) {
                                final unclaimed =
                                    int.tryParse(_unclaimedController.text) ??
                                        0;
                                final claimed = int.tryParse(value) ?? 0;
                                widget.onUpdate(unclaimed, claimed);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'minutes',
                          style: TextStyle(fontSize: 11, color: widget.color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alert escalates if claimed but not fixed within this time',
                      style: TextStyle(
                          fontSize: 10, color: widget.color.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: widget.color.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preview:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Unclaimed',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('→',
                        style: TextStyle(fontSize: 10, color: _muted)),
                    const SizedBox(width: 6),
                    Text(
                      'Escalates after ${_unclaimedController.text} min',
                      style: TextStyle(fontSize: 10, color: widget.color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Claimed',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('→',
                        style: TextStyle(fontSize: 10, color: _muted)),
                    const SizedBox(width: 6),
                    Text(
                      'Escalates after ${_claimedController.text} min without fix',
                      style: TextStyle(fontSize: 10, color: widget.color),
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
}

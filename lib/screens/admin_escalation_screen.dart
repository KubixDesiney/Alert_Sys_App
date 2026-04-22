import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/collaboration_model.dart';
import '../services/collaboration_service.dart';

const _navy = Color(0xFF0D4A75);
const _white = Colors.white;
const _bg = Color(0xFFF8FAFC);
const _border = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);
const _green = Color(0xFF16A34A);
const _greenLt = Color(0xFFDCFCE7);
const _red = Color(0xFFDC2626);
const _redLt = Color(0xFFFEE2E2);
const _orange = Color(0xFFEA580C);
const _orangeLt = Color(0xFFFFF7ED);
const _blue = Color(0xFF2563EB);
const _blueLt = Color(0xFFEFF6FF);
const _yellow = Color(0xFFFBBF24);
const _yellowLt = Color(0xFFFEF3C7);
const _purple = Color(0xFF9333EA);

Color _typeColor(String type) => switch (type) {
      'qualite' => _red,
      'maintenance' => _blue,
      'defaut_produit' => _green,
      'manque_ressource' => _orange,
      _ => _muted,
    };

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
                                  if (count == 0) return const SizedBox.shrink();
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
                                stream: _service.getPendingCollaborationRequests(),
                                builder: (context, snapshot) {
                                  final count = snapshot.data?.length ?? 0;
                                  if (count == 0) return const SizedBox.shrink();
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _orangeLt,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber, size: 48, color: _orange),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Escalated Alerts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Escalated alerts will appear here',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ],
      ),
    );
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

    return StreamBuilder<List<CollaborationRequest>>(
      stream: service.getPendingCollaborationRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
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
                  child: Icon(Icons.groups, size: 48, color: _purple),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Pending Collaborations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Collaboration requests will appear here',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
              ],
            ),
          );
        }

        final requests = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.people, color: _purple, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Pending Collaboration Requests',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${requests.length} Pending',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Approve or reject collaboration requests from supervisors',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final request = requests[index];
                  return _CollaborationRequestCard(request: request);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CollaborationRequestCard extends StatelessWidget {
  final CollaborationRequest request;

  const _CollaborationRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final service = CollaborationService();
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
          Row(
            children: [
              Text(
                request.requesterName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Alert #${request.alertId.substring(0, 8)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: _muted,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 10,
                    color: _white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '⏰ ${_formatTime(request.timestamp)}',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
          const SizedBox(height: 12),
          const Text(
            'Requesting collaboration with:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: request.targetSupervisorNames.map((name) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '@$name',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.message,
                  style: const TextStyle(fontSize: 12, color: _navy),
                ),
                const SizedBox(height: 8),
                Text(
                  'Issue: ${request.alertDescription}',
                  style: TextStyle(fontSize: 11, color: _muted, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await service.approveCollaborationRequest(
                      request.id,
                      currentUserId,
                      'Production Manager',
                      true,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Collaboration approved'),
                          backgroundColor: _green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text(
                    'Approve',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: _white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await service.rejectCollaborationRequest(
                      request.id,
                      currentUserId,
                      '',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Collaboration rejected'),
                          backgroundColor: _red,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.cancel, size: 16),
                  label: const Text(
                    'Reject',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
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
    final newThresholds = Map<String, EscalationThreshold>.from(_settings!.thresholds);
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
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
          const Text('• ', style: TextStyle(fontSize: 11, color: Color(0xFF78350F))),
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
    _unclaimedController =
        TextEditingController(text: widget.threshold.unclaimedMinutes.toString());
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
                      style: TextStyle(fontSize: 10, color: widget.color.withOpacity(0.7)),
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
                                    int.tryParse(_unclaimedController.text) ?? 0;
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
                      style: TextStyle(fontSize: 10, color: widget.color.withOpacity(0.7)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    const Text('→', style: TextStyle(fontSize: 10, color: _muted)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    const Text('→', style: TextStyle(fontSize: 10, color: _muted)),
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

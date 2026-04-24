import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/alert_provider.dart';
import '../models/alert_model.dart';
import '../services/user_service.dart';
import 'login_screen.dart';

class ProductionManagerScreen extends StatefulWidget {
  const ProductionManagerScreen({super.key});

  @override
  State<ProductionManagerScreen> createState() => _ProductionManagerScreenState();
}

class _ProductionManagerScreenState extends State<ProductionManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // ✅ WORKING LOGOUT
  Future<void> _logout() async {
    await _userService.logout();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlertProvider>();
    final unsolved = provider.allAlerts.where((a) => a.status != 'validee').toList();
    final solved = provider.allAlerts.where((a) => a.status == 'validee').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Production Manager'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Unsolved'), Tab(text: 'Solved')],
        ),
        actions: [
          IconButton(
            onPressed: () => _showSupervisorManagement(),
            icon: const Icon(Icons.people),
            tooltip: 'Manage Supervisors',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AlertList(alerts: unsolved, provider: provider, showReason: false),
          _AlertList(alerts: solved, provider: provider, showReason: true),
        ],
      ),
    );
  }

  void _showSupervisorManagement() {
    showDialog(
      context: context,
      builder: (_) => const ManageSupervisorsDialog(),
    );
  }
}

class _AlertList extends StatelessWidget {
  final List<AlertModel> alerts;
  final AlertProvider provider;
  final bool showReason;

  const _AlertList({required this.alerts, required this.provider, required this.showReason});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const Center(child: Text('No alerts'));
    }
    return ListView.builder(
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final a = alerts[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ExpansionTile(
            title: Text('${a.type.toUpperCase()} - ${a.usine} Line ${a.convoyeur}'),
            subtitle: Text('Status: ${_statusLabel(a.status)}'),
            children: [
              ListTile(title: const Text('Description'), subtitle: Text(a.description)),
              ListTile(title: const Text('Location'), subtitle: Text('${a.usine}, Post ${a.poste}, ${a.adresse}')),
              ListTile(title: const Text('Timestamp'), subtitle: Text(a.timestamp.toString())),
              if (a.status == 'validee' && a.elapsedTime != null)
                ListTile(title: const Text('Resolution Time'), subtitle: Text(provider.formatElapsedTime(a.elapsedTime))),
              if (showReason && a.resolutionReason != null)
                ListTile(title: const Text('Resolution Reason'), subtitle: Text(a.resolutionReason!)),
              if (a.comments.isNotEmpty)
                ListTile(
                  title: const Text('Comments'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: a.comments.map((c) => Text(c, style: const TextStyle(fontSize: 12))).toList(),
                  ),
                ),
              if (a.superviseurName != null)
                ListTile(title: const Text('Assigned Supervisor'), subtitle: Text(a.superviseurName!)),
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'disponible': return 'Available';
      case 'en_cours': return 'In Progress';
      case 'validee': return 'Resolved';
      default: return status;
    }
  }
}

class ManageSupervisorsDialog extends StatefulWidget {
  const ManageSupervisorsDialog({super.key});

  @override
  State<ManageSupervisorsDialog> createState() => _ManageSupervisorsDialogState();
}

class _ManageSupervisorsDialogState extends State<ManageSupervisorsDialog> {
  final UserService _userService = UserService();
  final TextEditingController _emailController = TextEditingController();
  List<Map<String, dynamic>> _supervisors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSupervisors();
  }

  Future<void> _loadSupervisors() async {
    setState(() => _loading = true);
    final supervisors = await _userService.getAllSupervisors();
    setState(() {
      _supervisors = supervisors;
      _loading = false;
    });
  }

  Future<void> _addSupervisor() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    // In a real app, you would create the user in Firebase Auth and then set role.
    // For simplicity, we assume the user already exists in Auth and we just set the role.
    // Here we would need to find the UID by email (requires Admin SDK or a custom endpoint).
    // This is a placeholder.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add supervisor feature requires backend integration.')),
    );
  }

  Future<void> _removeSupervisor(String uid) async {
    await _userService.removeSupervisor(uid);
    _loadSupervisors();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Supervisors'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(hintText: 'Supervisor email'),
                  ),
                ),
                IconButton(onPressed: _addSupervisor, icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_supervisors.isEmpty)
              const Text('No supervisors found')
            else
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _supervisors.length,
                  itemBuilder: (_, i) {
                    final sup = _supervisors[i];
                    return ListTile(
                      title: Text(sup['email'] ?? sup['uid']),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeSupervisor(sup['uid']),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

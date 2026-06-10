import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../services/superadmin_service.dart';
import 'superadmin_theme.dart';

/// SuperAdmin tab 2: provision and manage Production Manager accounts.
class ProductionManagersTab extends StatefulWidget {
  const ProductionManagersTab({super.key});

  @override
  State<ProductionManagersTab> createState() => _ProductionManagersTabState();
}

class _ProductionManagersTabState extends State<ProductionManagersTab> {
  final _service = SuperAdminService();
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _managers = const [];
  bool _loading = true;
  String? _streamError;
  String _search = '';

  List<String> _factories = const [];

  @override
  void initState() {
    super.initState();
    _sub = _service.productionManagersStream().listen((list) {
      if (mounted) {
        setState(() {
          _managers = list;
          _loading = false;
          _streamError = null;
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _streamError = '$e';
        });
      }
    });
    _loadFactories();
  }

  Future<void> _loadFactories() async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('hierarchy/factories').get();
      if (snap.value is Map && mounted) {
        final names = (snap.value as Map)
            .values
            .whereType<Map>()
            .map((f) => (f['name'] ?? '').toString())
            .where((n) => n.isNotEmpty)
            .toList()
          ..sort();
        setState(() => _factories = names);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.trim().isEmpty) return _managers;
    final q = _search.trim().toLowerCase();
    return _managers.where((m) {
      return (m['fullName'] ?? '').toString().toLowerCase().contains(q) ||
          (m['email'] ?? '').toString().toLowerCase().contains(q) ||
          (m['usine'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SaSectionHeader(
                      icon: Icons.badge_outlined,
                      title: 'PRODUCTION MANAGER ACCOUNTS',
                      subtitle:
                          'Managers run the admin dashboard: alerts, shifts, supervisors and AI oversight.',
                      accent: Sa.blue,
                      trailing: GlowChip(
                        label: '${_managers.length} ACTIVE',
                        color: Sa.blue,
                        icon: Icons.people_alt_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            style: Sa.body(size: 13),
                            cursorColor: Sa.cyan,
                            decoration: InputDecoration(
                              hintText: 'Search by name, email or plant…',
                              hintStyle: Sa.body(size: 12.5, color: Sa.muted),
                              prefixIcon: const Icon(Icons.search,
                                  size: 17, color: Sa.muted),
                              filled: true,
                              fillColor: Sa.bgRaised.withValues(alpha: 0.7),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Sa.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Sa.cyan),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SaButton(
                          label: 'NEW MANAGER',
                          icon: Icons.person_add_alt_1,
                          onPressed: _showCreateDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Sa.blue),
                        ),
                      )
                    else if (_streamError != null)
                      SaEmptyState(
                        icon: Icons.lock_outline,
                        title: 'Cannot load accounts',
                        message: _streamError!,
                        accent: Sa.red,
                      )
                    else if (_filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: SaEmptyState(
                          icon: Icons.badge_outlined,
                          title: 'No Production Managers yet',
                          message:
                              'Create the first manager account — they will land on the admin dashboard at next sign-in.',
                          accent: Sa.blue,
                        ),
                      )
                    else
                      LayoutBuilder(builder: (context, constraints) {
                        final cols = constraints.maxWidth > 880
                            ? 2
                            : 1;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final m in _filtered)
                              SizedBox(
                                width: cols == 1
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 12) / 2,
                                child: _ManagerCard(
                                  manager: m,
                                  onDelete: () => _confirmDelete(m),
                                  onResetPassword: () => _resetPassword(m),
                                ),
                              ),
                          ],
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetPassword(Map<String, dynamic> m) async {
    final email = (m['email'] ?? '').toString();
    if (email.isEmpty) return;
    try {
      await _service.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Password reset email sent to $email'),
          backgroundColor: Sa.panelSolid,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reset failed: $e'),
          backgroundColor: Colors.red.shade900,
        ));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> m) async {
    final name = (m['fullName'] ?? m['email'] ?? 'this account').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sa.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Sa.border),
        ),
        title: Text('Revoke $name?', style: Sa.heading(size: 16)),
        content: Text(
          'The account record and dashboard access are removed immediately. '
          'The Firebase Auth login remains but has no role.',
          style: Sa.body(size: 12.5, color: Sa.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: Sa.body(color: Sa.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Revoke access', style: Sa.body(color: Sa.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.deleteProductionManager((m['uid'] ?? '').toString());
    }
  }

  Future<void> _showCreateDialog() async {
    final first = TextEditingController();
    final last = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final pass = TextEditingController();
    final confirm = TextEditingController();
    String? usine;
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Sa.panelSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Sa.borderBright),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SaSectionHeader(
                      icon: Icons.person_add_alt_1,
                      title: 'NEW PRODUCTION MANAGER',
                      subtitle: 'Provision dashboard access',
                      accent: Sa.blue,
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: SaTextField(
                              controller: first, label: 'First name')),
                      const SizedBox(width: 10),
                      Expanded(
                          child:
                              SaTextField(controller: last, label: 'Last name')),
                    ]),
                    const SizedBox(height: 12),
                    SaTextField(
                      controller: email,
                      label: 'Email',
                      keyboard: TextInputType.emailAddress,
                      icon: Icons.alternate_email,
                    ),
                    const SizedBox(height: 12),
                    SaTextField(
                      controller: phone,
                      label: 'Phone',
                      keyboard: TextInputType.phone,
                      icon: Icons.phone_outlined,
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: SaTextField(
                              controller: pass,
                              label: 'Password',
                              obscure: true)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: SaTextField(
                              controller: confirm,
                              label: 'Confirm',
                              obscure: true)),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: usine,
                      dropdownColor: Sa.panelSolid,
                      style: Sa.body(size: 13),
                      decoration: InputDecoration(
                        labelText: 'Plant scope (optional)',
                        labelStyle: Sa.body(size: 12.5, color: Sa.textDim),
                        filled: true,
                        fillColor: Sa.bgRaised.withValues(alpha: 0.7),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Sa.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Sa.cyan),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: null,
                            child: Text('All plants',
                                style: Sa.body(size: 13))),
                        for (final f in _factories)
                          DropdownMenuItem(
                              value: f,
                              child: Text(f, style: Sa.body(size: 13))),
                      ],
                      onChanged: (v) => setS(() => usine = v),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Sa.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Sa.red.withValues(alpha: 0.4)),
                        ),
                        child: Text(error!,
                            style: Sa.body(size: 12, color: Sa.red)),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        SaButton(
                          label: busy ? 'CREATING…' : 'CREATE ACCOUNT',
                          icon: Icons.check_rounded,
                          color: Sa.blue,
                          busy: busy,
                          onPressed: busy
                              ? null
                              : () async {
                                  if ([first, last, email, pass, confirm]
                                      .any((c) => c.text.trim().isEmpty)) {
                                    setS(() =>
                                        error = 'All fields are required.');
                                    return;
                                  }
                                  if (pass.text != confirm.text) {
                                    setS(() =>
                                        error = 'Passwords do not match.');
                                    return;
                                  }
                                  if (pass.text.length < 6) {
                                    setS(() => error =
                                        'Password must be at least 6 characters.');
                                    return;
                                  }
                                  setS(() {
                                    busy = true;
                                    error = null;
                                  });
                                  final err =
                                      await _service.createProductionManager(
                                    firstName: first.text.trim(),
                                    lastName: last.text.trim(),
                                    email: email.text.trim(),
                                    password: pass.text,
                                    phone: phone.text.trim(),
                                    usine: usine,
                                  );
                                  if (!ctx.mounted) return;
                                  if (err != null) {
                                    setS(() {
                                      busy = false;
                                      error = err;
                                    });
                                  } else {
                                    Navigator.pop(ctx);
                                  }
                                },
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: busy ? null : () => Navigator.pop(ctx),
                          child:
                              Text('Cancel', style: Sa.body(color: Sa.muted)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManagerCard extends StatelessWidget {
  final Map<String, dynamic> manager;
  final VoidCallback onDelete;
  final VoidCallback onResetPassword;

  const _ManagerCard({
    required this.manager,
    required this.onDelete,
    required this.onResetPassword,
  });

  @override
  Widget build(BuildContext context) {
    final name = (manager['fullName'] ??
            '${manager['firstName'] ?? ''} ${manager['lastName'] ?? ''}')
        .toString()
        .trim();
    final email = (manager['email'] ?? '').toString();
    final usine = (manager['usine'] ?? '').toString();
    final status = (manager['status'] ?? '').toString();
    final online = status == 'active';
    final initials = name.isEmpty
        ? '?'
        : name
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
            .join();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Sa.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Sa.blue, Sa.violet]),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(initials,
                style: Sa.heading(size: 14, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? email : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Sa.body(size: 13.5, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlowChip(
                      label: online ? 'ACTIVE' : 'OFFLINE',
                      color: online ? Sa.green : Sa.muted,
                      pulse: online,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.mono(size: 10.5, color: Sa.textDim)),
                if (usine.isNotEmpty)
                  Text('Plant: $usine',
                      style: Sa.body(size: 11, color: Sa.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Send password reset',
            onPressed: onResetPassword,
            icon: const Icon(Icons.lock_reset, size: 18, color: Sa.amber),
          ),
          IconButton(
            tooltip: 'Revoke access',
            onPressed: onDelete,
            icon:
                const Icon(Icons.delete_outline, size: 18, color: Sa.red),
          ),
        ],
      ),
    );
  }
}

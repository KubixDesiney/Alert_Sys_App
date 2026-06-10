import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'hardware_tab.dart';
import 'logs_tab.dart';
import 'lstm_training_tab.dart';
import 'production_managers_tab.dart';
import 'superadmin_theme.dart';

/// SuperAdmin command console: AI model training, Production Manager account
/// management, platform-wide logs/diagnostics, and (future) hardware fleet.
class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  int _tab = 0;
  late Timer _clock;
  DateTime _now = DateTime.now();
  StreamSubscription<DatabaseEvent>? _healthSub;
  DateTime? _lastCronRun;

  static const _tabs = [
    (icon: Icons.psychology_outlined, label: 'AI TRAINING'),
    (icon: Icons.badge_outlined, label: 'PRODUCTION MANAGERS'),
    (icon: Icons.terminal_outlined, label: 'LOGS'),
    (icon: Icons.memory_outlined, label: 'HARDWARE'),
  ];

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _healthSub = FirebaseDatabase.instance
        .ref('workers/health/lastRun')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (v is Map) {
        final at = DateTime.tryParse((v['at'] ?? v['finishedAt'] ?? '').toString());
        if (mounted) setState(() => _lastCronRun = at);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _clock.cancel();
    _healthSub?.cancel();
    super.dispose();
  }

  Color get _systemColor {
    if (_lastCronRun == null) return Sa.muted;
    final age = DateTime.now().toUtc().difference(_lastCronRun!.toUtc());
    if (age.inMinutes <= 3) return Sa.green;
    if (age.inMinutes <= 10) return Sa.amber;
    return Sa.red;
  }

  String get _systemLabel {
    if (_lastCronRun == null) return 'SYSTEM: PROBING';
    final age = DateTime.now().toUtc().difference(_lastCronRun!.toUtc());
    if (age.inMinutes <= 3) return 'SYSTEM: NOMINAL';
    if (age.inMinutes <= 10) return 'SYSTEM: DEGRADED';
    return 'SYSTEM: CRON STALLED';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 980;
    return Scaffold(
      backgroundColor: Sa.bg,
      body: NeuralBackground(
        child: SafeArea(
          child: Row(
            children: [
              _NavRail(
                expanded: wide,
                tab: _tab,
                tabs: _tabs,
                onSelect: (i) => setState(() => _tab = i),
              ),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(wide),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.02),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_tab),
                          child: switch (_tab) {
                            0 => const LstmTrainingTab(),
                            1 => const ProductionManagersTab(),
                            2 => const SuperAdminLogsTab(),
                            _ => const HardwareTab(),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool wide) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = _now.second.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Sa.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tabs[_tab].label, style: Sa.display(size: wide ? 18 : 14)),
                const SizedBox(height: 2),
                Text(
                  'SUPERADMIN CONSOLE · SMART INDUSTRIAL ALERT',
                  style: Sa.mono(size: 9, color: Sa.muted),
                ),
              ],
            ),
          ),
          if (wide) ...[
            GlowChip(label: _systemLabel, color: _systemColor, pulse: true),
            const SizedBox(width: 12),
            Text('$hh:$mm:$ss', style: Sa.mono(size: 16, color: Sa.cyan)),
            const SizedBox(width: 16),
          ],
          _LogoutButton(onLogout: () async {
            await AuthService().logout();
          }),
        ],
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  final bool expanded;
  final int tab;
  final List<({IconData icon, String label})> tabs;
  final ValueChanged<int> onSelect;

  const _NavRail({
    required this.expanded,
    required this.tab,
    required this.tabs,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: expanded ? 232 : 68,
      decoration: const BoxDecoration(
        color: Color(0xCC060E22),
        border: Border(right: BorderSide(color: Sa.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 26),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Sa.cyan, Sa.violet],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                          color: Sa.cyan.withValues(alpha: 0.35), blurRadius: 16),
                    ],
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: Color(0xFF03101F), size: 20),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SIA CORE', style: Sa.display(size: 13)),
                        Text('SUPERADMIN',
                            style: Sa.mono(size: 8.5, color: Sa.cyan)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (var i = 0; i < tabs.length; i++)
            _NavItem(
              icon: tabs[i].icon,
              label: tabs[i].label,
              selected: tab == i,
              expanded: expanded,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          if (expanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Sa.bgRaised.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Sa.border),
                ),
                child: Row(
                  children: [
                    const PulseDot(color: Sa.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Sa.mono(size: 9.5, color: Sa.textDim),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final color = active
        ? Sa.cyan
        : _hover
            ? Sa.text
            : Sa.muted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: EdgeInsets.symmetric(
              horizontal: widget.expanded ? 14 : 0, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? Sa.cyan.withValues(alpha: 0.10)
                : _hover
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: active ? Sa.cyan.withValues(alpha: 0.4) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 18, color: color),
              if (widget.expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.heading(size: 12, color: color),
                  ),
                ),
                if (active) const PulseDot(color: Sa.cyan, size: 5),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final Future<void> Function() onLogout;
  const _LogoutButton({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sign out',
      child: InkWell(
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Sa.panelSolid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Sa.border),
              ),
              title: Text('Sign out of the console?', style: Sa.heading(size: 16)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: Sa.body(color: Sa.textDim)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Sign out', style: Sa.body(color: Sa.red)),
                ),
              ],
            ),
          );
          if (confirmed == true) await onLogout();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Sa.border),
          ),
          child: const Icon(Icons.power_settings_new, size: 17, color: Sa.red),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/auth_service.dart';
import '../../services/forecast/forecast_training_controller.dart';
import 'access_identity_tab.dart';
import 'ai_agents_tab.dart';
import 'ai_training_tab.dart';
import 'hardware_tab.dart';
import 'logs_tab.dart';
import 'production_managers_tab.dart';
import 'reliability_tab.dart';
import 'superadmin_theme.dart';
import 'theme_studio_tab.dart';

/// SuperAdmin command center: AI model training, Production Manager account
/// management, platform-wide logs/diagnostics, and (future) hardware fleet.
class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  int _tab = 0;
  StreamSubscription<DatabaseEvent>? _healthSub;
  DateTime? _lastCronRun;

  static const _tabs = [
    (icon: Icons.psychology_outlined, label: 'AI TRAINING'),
    (icon: Icons.hub_outlined, label: 'AI AGENTS'),
    (icon: Icons.badge_outlined, label: 'PRODUCTION MANAGERS'),
    (icon: Icons.vpn_key_outlined, label: 'ACCESS & IDENTITY'),
    (icon: Icons.health_and_safety_outlined, label: 'RELIABILITY'),
    (icon: Icons.palette_outlined, label: 'BRANDING'),
    (icon: Icons.terminal_outlined, label: 'LOGS'),
    (icon: Icons.memory_outlined, label: 'HARDWARE'),
  ];

  @override
  void initState() {
    super.initState();
    // Pick up any training run that was interrupted by a closed tab/app, and
    // restore the uploaded dataset — training must complete with or without
    // an operator watching.
    ForecastTrainingController.instance.ensureResumed();
    _healthSub = FirebaseDatabase.instance
        .ref('workers/health/lastRun')
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (v is Map) {
        final at =
            DateTime.tryParse((v['at'] ?? v['finishedAt'] ?? '').toString());
        if (mounted) setState(() => _lastCronRun = at);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _healthSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The console follows the app theme; resolve the token palette before any
    // child reads it.
    final themeProvider = context.watch<ThemeProvider>();
    Sa.setDark(themeProvider.isDark);

    final wide = MediaQuery.of(context).size.width >= 980;
    return Scaffold(
      backgroundColor: Sa.bg,
      body: NeuralBackground(
        child: SafeArea(
          child: Row(
            children: [
              ListenableBuilder(
                listenable: ForecastTrainingController.instance,
                builder: (context, _) => _NavRail(
                  expanded: wide,
                  tab: _tab,
                  tabs: _tabs,
                  trainingActive: ForecastTrainingController.instance.runActive,
                  onSelect: (i) => setState(() => _tab = i),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(wide, themeProvider),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.015),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_tab),
                          child: switch (_tab) {
                            0 => const AiTrainingTab(),
                            1 => const AiAgentsTab(),
                            2 => const ProductionManagersTab(),
                            3 => const AccessIdentityTab(),
                            4 => const ReliabilityTab(),
                            5 => const ThemeStudioTab(),
                            6 => const SuperAdminLogsTab(),
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

  Widget _buildHeader(bool wide, ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
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
                  'COMMAND CENTER · SMART INDUSTRIAL ALERT',
                  style: Sa.mono(size: 9, color: Sa.muted),
                ),
              ],
            ),
          ),
          if (wide) ...[
            _SystemStatusChip(lastCronRun: _lastCronRun),
            const SizedBox(width: 12),
            const _HeaderClock(),
            const SizedBox(width: 14),
          ],
          _ThemeToggleButton(
            isDark: themeProvider.isDark,
            onToggle: themeProvider.toggle,
          ),
          const SizedBox(width: 8),
          _LogoutButton(onLogout: () async {
            await AuthService().logout();
          }),
        ],
      ),
    );
  }
}

/// Worker-cron freshness chip. Self-refreshes on a slow timer so the rest of
/// the screen never rebuilds for it.
class _SystemStatusChip extends StatefulWidget {
  final DateTime? lastCronRun;
  const _SystemStatusChip({required this.lastCronRun});

  @override
  State<_SystemStatusChip> createState() => _SystemStatusChipState();
}

class _SystemStatusChipState extends State<_SystemStatusChip> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.lastCronRun;
    Color color;
    String label;
    if (last == null) {
      color = Sa.muted;
      label = 'SYSTEM: PROBING';
    } else {
      final age = DateTime.now().toUtc().difference(last.toUtc());
      if (age.inMinutes <= 3) {
        color = Sa.green;
        label = 'SYSTEM: NOMINAL';
      } else if (age.inMinutes <= 10) {
        color = Sa.amber;
        label = 'SYSTEM: DEGRADED';
      } else {
        color = Sa.red;
        label = 'SYSTEM: CRON STALLED';
      }
    }
    return GlowChip(label: label, color: color, pulse: true);
  }
}

/// Live clock isolated in its own widget so the per-second tick repaints a
/// few glyphs instead of the whole console.
class _HeaderClock extends StatefulWidget {
  const _HeaderClock();

  @override
  State<_HeaderClock> createState() => _HeaderClockState();
}

class _HeaderClockState extends State<_HeaderClock> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = _now.second.toString().padLeft(2, '0');
    return RepaintBoundary(
      child: Text('$hh:$mm:$ss', style: Sa.mono(size: 16, color: Sa.cyan)),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggle;
  const _ThemeToggleButton({required this.isDark, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Sa.border),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) =>
                RotationTransition(turns: anim, child: FadeTransition(opacity: anim, child: child)),
            child: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              key: ValueKey(isDark),
              size: 17,
              color: isDark ? Sa.amber : Sa.violet,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  final bool expanded;
  final int tab;
  final List<({IconData icon, String label})> tabs;
  final bool trainingActive;
  final ValueChanged<int> onSelect;

  const _NavRail({
    required this.expanded,
    required this.tab,
    required this.tabs,
    required this.trainingActive,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: expanded ? 232 : 68,
      decoration: BoxDecoration(
        color: Sa.isDark ? const Color(0xCC060E22) : const Color(0xE8FFFFFF),
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
                    gradient: LinearGradient(
                      colors: [Sa.cyan, Sa.violet],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                          color: Sa.cyan.withValues(alpha: 0.35),
                          blurRadius: 16),
                    ],
                  ),
                  child: Icon(Icons.shield_outlined,
                      color: Sa.onAccent, size: 20),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('COMMAND', style: Sa.display(size: 12.5)),
                        Text('CENTER',
                            style: Sa.display(size: 12.5, color: Sa.cyan)),
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
              // Surface a live-training heartbeat on the AI tab even while
              // the operator works elsewhere in the console.
              activity: i == 0 && trainingActive,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          if (expanded && trainingActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Sa.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Sa.green.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    PulseDot(color: Sa.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'MODEL TRAINING IN PROGRESS',
                        maxLines: 2,
                        style: Sa.mono(
                            size: 8.5,
                            color: Sa.green,
                            weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                    PulseDot(color: Sa.green),
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
  final bool activity;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
    this.activity = false,
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
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: EdgeInsets.symmetric(
              horizontal: widget.expanded ? 12 : 0, vertical: 12),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(colors: [
                    Sa.cyan.withValues(alpha: 0.14),
                    Sa.cyan.withValues(alpha: 0.04),
                  ])
                : null,
            color: !active && _hover
                ? Sa.text.withValues(alpha: 0.05)
                : null,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color:
                  active ? Sa.cyan.withValues(alpha: 0.4) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              // Active indicator bar keeps a fixed slot so items never shift.
              if (widget.expanded) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: active
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Sa.cyan, Sa.violet],
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Icon(widget.icon, size: 18, color: color),
              if (widget.expanded) ...[
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.heading(size: 12, color: color),
                  ),
                ),
                if (widget.activity)
                  PulseDot(color: Sa.green, size: 6)
                else if (active)
                  PulseDot(color: Sa.cyan, size: 5),
              ] else if (widget.activity)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: PulseDot(color: Sa.green, size: 5),
                ),
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
          final training = ForecastTrainingController.instance.training;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Sa.panelSolid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Sa.border),
              ),
              title:
                  Text('Sign out of the console?', style: Sa.heading(size: 16)),
              content: training
                  ? Text(
                      'A model training run is in progress. It keeps running '
                      'while this app stays open, and its checkpoint lets any '
                      'future session finish it — signing out is safe.',
                      style: Sa.body(size: 12.5, color: Sa.textDim),
                    )
                  : null,
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
          child: Icon(Icons.power_settings_new, size: 17, color: Sa.red),
        ),
      ),
    );
  }
}

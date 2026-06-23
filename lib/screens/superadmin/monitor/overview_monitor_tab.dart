import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../services/telemetry_service.dart';
import '../hardware/hw_machines.dart';
import '../superadmin_theme.dart';
import 'database_hologram.dart';
import 'fleet_workers.dart';
import 'monitor_data.dart';
import 'monitor_kit.dart';
import 'security_feed.dart';
import 'sessions_panel.dart';

/// SuperAdmin → **Overview Monitor**: a holographic war-room that lays the
/// entire platform bare for the IT team in one scroll — fleet, edge workers,
/// database, operational posture and live sessions.
///
/// Replaces the old Logs tab; everything here reads live RTDB / worker state
/// through a single [MonitorController].
class OverviewMonitorTab extends StatefulWidget {
  const OverviewMonitorTab({super.key});

  @override
  State<OverviewMonitorTab> createState() => _OverviewMonitorTabState();
}

class _OverviewMonitorTabState extends State<OverviewMonitorTab> {
  final MonitorController _c = MonitorController();
  Timer? _ageTicker;

  @override
  void initState() {
    super.initState();
    _c.start();
    // Re-render every 15s so "Xs ago" freshness and presence age stay honest.
    _ageTicker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTicker?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CommandStrip(controller: _c, onRefresh: () => _c.refreshHeavy()),
                  const SizedBox(height: 18),
                  OperationalInsight(controller: _c),
                  const SizedBox(height: 18),
                  LayoutBuilder(builder: (context, cns) {
                    final fleet = FleetConstellation(controller: _c);
                    final workers = WorkersGrid(controller: _c);
                    if (cns.maxWidth >= 1080) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: fleet),
                          const SizedBox(width: 18),
                          Expanded(flex: 6, child: workers),
                        ],
                      );
                    }
                    return Column(
                      children: [fleet, const SizedBox(height: 18), workers],
                    );
                  }),
                  const SizedBox(height: 18),
                  LayoutBuilder(builder: (context, cns) {
                    final db = DatabaseHologram(controller: _c);
                    final sec = SecurityFeed(controller: _c);
                    if (cns.maxWidth >= 1080) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: db),
                          const SizedBox(width: 18),
                          Expanded(flex: 5, child: sec),
                        ],
                      );
                    }
                    return Column(
                      children: [db, const SizedBox(height: 18), sec],
                    );
                  }),
                  const SizedBox(height: 18),
                  SessionsPanel(controller: _c),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

const List<String> _agentIds = [
  'shift', 'briefing', 'assist', 'security', 'predictive', 'guardian',
];

class _CommandStrip extends StatelessWidget {
  final MonitorController controller;
  final VoidCallback onRefresh;
  const _CommandStrip({required this.controller, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final c = controller;

    final aiState = workerLiveState(c.aiHealth, onMin: 3, idleMin: 10);
    final notifyState = workerLiveState(c.notifyHealth, onMin: 3, idleMin: 10);
    final backupState = workerLiveState(c.backupHealth,
        onMin: 26 * 60, idleMin: 50 * 60, okKey: 'ok');
    final monitorState = workerLiveState(c.monitorHealth,
        onMin: 7, idleMin: 20, stateKey: 'state');
    final githubUp = c.github?.connected == true;

    bool up(LiveState s) => s == LiveState.online || s == LiveState.idle;
    final workersLive = [aiState, notifyState, backupState, monitorState]
            .where(up)
            .length +
        (githubUp ? 1 : 0);

    final agentsOnline =
        _agentIds.where((id) => c.agent(id).enabled).length;

    final machines = c.catalog?.machines ?? const [];
    final activeMachines =
        machines.where((m) => m.status == HwMachineStatus.active).length;

    final crashFree = TelemetryService.crashFreeRate(
        sessions: c.telemetrySessions, errorSessions: c.telemetryErrorSessions);

    final dbReach = c.dbReachableCount;

    // Overall posture.
    final criticalDown =
        aiState == LiveState.offline || notifyState == LiveState.offline;
    final degraded = workersLive < 5 ||
        agentsOnline < _agentIds.length ||
        dbReach < kDbNodes.length ||
        crashFree < 0.95;
    final (postureColor, postureLabel) = criticalDown
        ? (Sa.red, context.tr('CRITICAL'))
        : (degraded
            ? (Sa.amber, context.tr('DEGRADED'))
            : (Sa.green, context.tr('NOMINAL')));

    final kpis = <Widget>[
      KpiReadout(
        icon: Icons.dns_outlined,
        label: context.tr('EDGE WORKERS'),
        value: workersLive,
        suffix: '/5',
        accent: workersLive == 5 ? Sa.green : Sa.amber,
        sub: context.tr('cloudflare cron live'),
        pulse: workersLive == 5,
      ),
      KpiReadout(
        icon: Icons.hub_outlined,
        label: context.tr('AI AGENTS'),
        value: agentsOnline,
        suffix: '/${_agentIds.length}',
        accent: agentsOnline == _agentIds.length ? Sa.violet : Sa.amber,
        sub: context.tr('autonomous units'),
        pulse: true,
      ),
      KpiReadout(
        icon: Icons.groups_2_outlined,
        label: context.tr('LIVE SESSIONS'),
        value: c.onlineSessions,
        accent: Sa.cyan,
        sub: context.tr('{count} accounts total', {
          'count': '${c.sessions.length}',
        }),
        pulse: c.onlineSessions > 0,
      ),
      KpiReadout(
        icon: Icons.memory_outlined,
        label: context.tr('MACHINES ACTIVE'),
        value: activeMachines,
        accent: Sa.blue,
        sub: context.tr('{count} units mapped', {
          'count': '${machines.length}',
        }),
      ),
      KpiReadout(
        icon: Icons.schema_outlined,
        label: context.tr('DB ROOTS LIVE'),
        value: dbReach,
        suffix: '/${kDbNodes.length}',
        accent: dbReach == kDbNodes.length ? Sa.green : Sa.amber,
        sub: context.tr('realtime topology'),
      ),
      KpiReadout(
        icon: Icons.health_and_safety_outlined,
        label: context.tr('CRASH-FREE'),
        value: double.parse((crashFree * 100).toStringAsFixed(1)),
        suffix: '%',
        accent: crashFree >= 0.99
            ? Sa.green
            : (crashFree >= 0.95 ? Sa.amber : Sa.red),
        sub: context.tr('today · {count} errors', {
          'count': '${c.telemetryErrors}',
        }),
      ),
    ];

    return HoloPanel(
      accent: postureColor,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _RadarSpinner(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('GLOBAL OVERVIEW MONITOR'),
                        style: Sa.display(size: 17)),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(
                        'BACKEND · INFRASTRUCTURE · APPLICATION — ALL LAYERS, ONE GLASS',
                      ),
                      style: Sa.mono(size: 9, color: Sa.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    postureColor.withValues(alpha: 0.22),
                    postureColor.withValues(alpha: 0.08),
                  ]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: postureColor.withValues(alpha: 0.55)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PulseDot(color: postureColor),
                    const SizedBox(width: 9),
                    Text(
                        context.tr('SYSTEM {label}', {
                          'label': postureLabel,
                        }),
                        style: Sa.heading(size: 14, color: postureColor)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SaButton(
                label: context.tr('SYNC'),
                icon: Icons.sync,
                outlined: true,
                busy: c.dbProbing || c.catalogLoading || c.githubProbing,
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, cns) {
            final cols = cns.maxWidth >= 1180
                ? 6
                : cns.maxWidth >= 860
                    ? 3
                    : (cns.maxWidth >= 460 ? 2 : 1);
            const gap = 12.0;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final k in kpis)
                  SizedBox(width: (cns.maxWidth - (cols - 1) * gap) / cols, child: k),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// A slow sweeping radar disc — the war-room's pulse.
class _RadarSpinner extends StatefulWidget {
  const _RadarSpinner();

  @override
  State<_RadarSpinner> createState() => _RadarSpinnerState();
}

class _RadarSpinnerState extends State<_RadarSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 42,
        height: 42,
        child: CustomPaint(painter: _RadarPainter(_c)),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Animation<double> t;
  _RadarPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final base = Sa.cyan;
    for (final rr in [r, r * 0.66, r * 0.33]) {
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..color = base.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // Sweep wedge.
    final ang = t.value * 3.14159 * 2;
    final sweep = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r), ang, 0.9, false)
      ..close();
    canvas.drawPath(
      sweep,
      Paint()
        ..shader = SweepGradient(
          startAngle: ang,
          endAngle: ang + 0.9,
          colors: [base.withValues(alpha: 0.5), base.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, 2.4, Paint()..color = base);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => false;
}

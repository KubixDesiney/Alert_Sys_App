import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../services/telemetry_service.dart';
import '../superadmin_theme.dart';
import 'monitor_data.dart';
import 'monitor_kit.dart';

/// Every account that has touched the platform, with a live presence read from
/// each user's `lastSeen` heartbeat — plus today's self-hosted telemetry
/// (sessions, crash-free rate, error budget) on the side.
class SessionsPanel extends StatefulWidget {
  final MonitorController controller;
  const SessionsPanel({super.key, required this.controller});

  @override
  State<SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends State<SessionsPanel> {
  String _filter = 'all';
  static const _maxShown = 48;

  static Color _roleColor(String role) => switch (role.toLowerCase()) {
        'superadmin' => Sa.violet,
        'admin' => Sa.amber,
        'supervisor' => Sa.cyan,
        _ => Sa.blue,
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final all = c.sessions;
    final online = c.onlineSessions;
    final idle = c.idleSessions;

    final filtered = _filter == 'all'
        ? all
        : all.where((s) {
            return switch (_filter) {
              'online' => s.state == LiveState.online,
              'idle' => s.state == LiveState.idle,
              _ => s.role.toLowerCase() == _filter,
            };
          }).toList();

    final crashFree = TelemetryService.crashFreeRate(
        sessions: c.telemetrySessions, errorSessions: c.telemetryErrorSessions);

    return HoloPanel(
      accent: Sa.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoloHeader(
            icon: Icons.groups_2_outlined,
            title: context.tr('ACTIVE SESSIONS'),
            subtitle: context.tr(
              'Live presence across every provisioned account.',
            ),
            accent: Sa.blue,
            trailing: GlowChip(
              label: context.tr('{count} LIVE', {'count': '$online'}),
              color: online > 0 ? Sa.green : Sa.muted,
              pulse: online > 0,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, cns) {
            final narrow = cns.maxWidth < 640;
            final gauges = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RingGauge(
                  value: all.isEmpty ? 0 : online / all.length,
                  accent: Sa.green,
                  size: 104,
                  center: '$online',
                  caption: context.tr('ONLINE'),
                ),
                const SizedBox(width: 18),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _miniStat(
                        context.tr('TOTAL ACCOUNTS'), '${all.length}', Sa.blue),
                    _miniStat(context.tr('IDLE'), '$idle', Sa.amber),
                    _miniStat(context.tr('TODAY · SESSIONS'),
                        '${c.telemetrySessions}', Sa.cyan),
                    _miniStat(
                        context.tr('CRASH-FREE'),
                        '${(crashFree * 100).toStringAsFixed(1)}%',
                        crashFree >= 0.99 ? Sa.green : (crashFree >= 0.95 ? Sa.amber : Sa.red)),
                  ],
                ),
              ],
            );
            return narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [gauges])
                : gauges;
          }),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final f in const [
                ('all', 'ALL'),
                ('online', 'ONLINE'),
                ('idle', 'IDLE'),
                ('supervisor', 'SUPERVISORS'),
                ('admin', 'MANAGERS'),
              ])
                _FilterPill(
                  label: context.tr(f.$2),
                  selected: _filter == f.$1,
                  onTap: () => setState(() => _filter = f.$1),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(context.tr('No accounts match this filter.'),
                    style: Sa.body(size: 12.5, color: Sa.textDim)),
              ),
            )
          else
            LayoutBuilder(builder: (context, cns) {
              final cols = cns.maxWidth >= 1080
                  ? 3
                  : cns.maxWidth >= 680
                      ? 2
                      : 1;
              final shown = filtered.take(_maxShown).toList();
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final s in shown)
                    SizedBox(
                      width: (cns.maxWidth - (cols - 1) * 12) / cols,
                      child: _SessionCard(row: s, roleColor: _roleColor(s.role)),
                    ),
                  if (filtered.length > _maxShown)
                    SizedBox(
                      width: (cns.maxWidth - (cols - 1) * 12) / cols,
                      child: _MoreCard(n: filtered.length - _maxShown),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(
              color: color, shape: BoxShape.circle)),
          const SizedBox(width: 9),
          Text(value, style: Sa.mono(size: 14, color: Sa.text, weight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(label, style: Sa.mono(size: 9, color: Sa.muted, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SessionRow row;
  final Color roleColor;
  const _SessionCard({required this.row, required this.roleColor});

  @override
  Widget build(BuildContext context) {
    final c = liveColor(row.state);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.5 : 0.92),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [roleColor.withValues(alpha: 0.35), roleColor.withValues(alpha: 0.08)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: roleColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(row.initials,
                        style: Sa.heading(size: 14, color: roleColor)),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: Sa.panelSolid, width: 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Sa.heading(size: 13)),
                    Text(row.factory.isEmpty ? (row.email.isEmpty ? '—' : row.email) : row.factory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Sa.mono(size: 9.5, color: Sa.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _tag(row.role.toUpperCase(), roleColor),
              const SizedBox(width: 6),
              if (row.pushEnabled)
                Icon(Icons.notifications_active_outlined, size: 13, color: Sa.green),
              if (row.located) ...[
                const SizedBox(width: 4),
                Icon(Icons.location_on_outlined, size: 13, color: Sa.cyan),
              ],
              const Spacer(),
              Text(
                row.lastSeen == null
                    ? context.tr('never')
                    : shortAgo(context, row.lastSeen),
                style: Sa.mono(size: 9.5, color: c),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: Sa.mono(size: 8.5, color: color, weight: FontWeight.w700)),
    );
  }
}

class _MoreCard extends StatelessWidget {
  final int n;
  const _MoreCard({required this.n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Sa.border),
      ),
      child: Text(context.tr('+ {n} more accounts', {'n': '$n'}),
          style: Sa.mono(size: 11, color: Sa.muted, weight: FontWeight.w600)),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Sa.blue.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? Sa.blue : Sa.border),
        ),
        child: Text(label,
            style: Sa.mono(
                size: 10, color: selected ? Sa.blue : Sa.muted, weight: FontWeight.w700)),
      ),
    );
  }
}

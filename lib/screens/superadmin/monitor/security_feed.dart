import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../superadmin_theme.dart';
import 'monitor_data.dart';
import 'monitor_kit.dart';

/// War-room security rail: the edge Sentinel's live enforcement feed plus the
/// platform's integrity pulse (open client bugs). Read-only — the controls live
/// in the AI Agents tab; this is the IT team's at-a-glance threat board.
class SecurityFeed extends StatelessWidget {
  final MonitorController controller;
  const SecurityFeed({super.key, required this.controller});

  static Map<String, Color> get _kindColors => {
        'rate_limit': Sa.amber,
        'prompt_injection': Sa.red,
        'blocked': Sa.red,
        'sanitize': Sa.amber,
        'alert_flood': Sa.red,
        'malformed_alerts': Sa.amber,
        'notification_backlog': Sa.blue,
        'auth_surge': Sa.violet,
      };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final actions = c.securityActions;
    final clean = actions.isEmpty;

    return HoloPanel(
      accent: clean ? Sa.green : Sa.red,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoloHeader(
            icon: Icons.security_outlined,
            title: context.tr('SECURITY & INTEGRITY'),
            subtitle: context.tr(
              'Edge Sentinel enforcements and platform error budget, live.',
            ),
            accent: clean ? Sa.green : Sa.red,
            trailing: GlowChip(
              label: clean
                  ? context.tr('NO THREATS')
                  : context.tr('{count} BLOCKED', {
                      'count': '${actions.length}',
                    }),
              color: clean ? Sa.green : Sa.red,
              pulse: !clean,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SaStatTile(
                label: context.tr('enforcements'),
                value: '${actions.length}',
                icon: Icons.gpp_good_outlined,
                color: clean ? Sa.green : Sa.red,
              ),
              SaStatTile(
                label: context.tr('open bugs'),
                value: '${c.openBugs}',
                icon: Icons.bug_report_outlined,
                color: c.openBugs == 0 ? Sa.green : Sa.amber,
              ),
              SaStatTile(
                label: context.tr('bugs total'),
                value: '${c.totalBugs}',
                icon: Icons.fact_check_outlined,
                color: Sa.blue,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (clean)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 18, color: Sa.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(
                        'No hostile traffic has reached the workers recently — the edge is quiet.',
                      ),
                      style: Sa.body(size: 12, color: Sa.textDim),
                    ),
                  ),
                ],
              ),
            )
          else
            ...actions.take(12).map((e) => _ThreatRow(
                  event: e,
                  color: _kindColors[(e['kind'] ?? '').toString()] ?? Sa.cyan,
                )),
        ],
      ),
    );
  }
}

class _ThreatRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final Color color;
  const _ThreatRow({required this.event, required this.color});

  @override
  Widget build(BuildContext context) {
    final kind = (event['kind'] ?? 'event').toString();
    final endpoint = (event['endpoint'] ?? '').toString();
    final fp = (event['fingerprint'] ?? '').toString();
    final reason = (event['reason'] ?? event['matches'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Sa.bgRaised.withValues(alpha: Sa.isDark ? 0.45 : 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(kind,
                        style: Sa.mono(size: 10.5, color: color, weight: FontWeight.w700)),
                    if (endpoint.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(endpoint, style: Sa.mono(size: 9.5, color: Sa.textDim)),
                    ],
                  ],
                ),
                if (reason.isNotEmpty)
                  Text(reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Sa.body(size: 10.5, color: Sa.muted)),
              ],
            ),
          ),
          if (fp.isNotEmpty)
            Text(fp.length > 8 ? '…${fp.substring(fp.length - 8)}' : fp,
                style: Sa.mono(size: 8.5, color: Sa.muted)),
          const SizedBox(width: 8),
          Text(_short(event['at']), style: Sa.mono(size: 9, color: Sa.muted)),
        ],
      ),
    );
  }

  static String _short(Object? iso) {
    final dt = DateTime.tryParse((iso ?? '').toString());
    if (dt == null) return '—';
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

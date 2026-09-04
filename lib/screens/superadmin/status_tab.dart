import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../services/github_service.dart';
import 'monitor/monitor_data.dart';
import 'monitor/monitor_kit.dart';
import 'superadmin_theme.dart';

/// SuperAdmin → **Status**: a public-style status page (Anthropic-grade, in the
/// SIAS command-center theme) for every backend SIAS depends on — the
/// Cloudflare edge workers, the GitHub integration and Firebase. Each service
/// shows its live reachability plus a rolling session-uptime strip sampled
/// every 20s while the page is open.
class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  final _StatusController _c = _StatusController();
  Timer? _sampler;
  Timer? _ageTicker;

  @override
  void initState() {
    super.initState();
    _c.start();
    // Roll a fresh sample into every service's uptime strip on a steady cadence.
    _sampler = Timer.periodic(const Duration(seconds: 20), (_) => _c.sample());
    _ageTicker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sampler?.cancel();
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
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PostureBanner(controller: _c, onRefresh: () => _c.probeAll()),
                  const SizedBox(height: 18),
                  for (final g in kStatusGroups) ...[
                    _GroupPanel(controller: _c, group: g),
                    const SizedBox(height: 16),
                  ],
                  const _KubixCopilotCard(),
                  const SizedBox(height: 16),
                  _FootNote(controller: _c),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  POSTURE BANNER
// ════════════════════════════════════════════════════════════════════════════

class _PostureBanner extends StatelessWidget {
  final _StatusController controller;
  final VoidCallback onRefresh;
  const _PostureBanner({required this.controller, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final states = [for (final s in kStatusServices) controller.stateFor(s.id)];
    final op = states.where((s) => s == LiveState.online).length;
    final degraded = states.where((s) => s == LiveState.idle).length;
    final down = states.where((s) => s == LiveState.offline).length;
    final unknown = states.where((s) => s == LiveState.unknown).length;

    final criticalDown = kStatusServices.any((s) =>
        s.critical && controller.stateFor(s.id) == LiveState.offline);

    final Color color;
    final String label;
    if (criticalDown) {
      (color, label) = (Sa.red, context.tr('MAJOR OUTAGE'));
    } else if (down > 0) {
      (color, label) = (Sa.amber, context.tr('PARTIAL OUTAGE'));
    } else if (degraded > 0) {
      (color, label) = (Sa.amber, context.tr('DEGRADED PERFORMANCE'));
    } else if (unknown == states.length) {
      (color, label) = (Sa.muted, context.tr('PROBING SYSTEMS'));
    } else if (unknown > 0) {
      (color, label) = (Sa.cyan, context.tr('MOSTLY OPERATIONAL'));
    } else {
      (color, label) = (Sa.green, context.tr('ALL SYSTEMS OPERATIONAL'));
    }

    return HoloPanel(
      accent: color,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.3),
                      color.withValues(alpha: 0.06)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: color.withValues(alpha: 0.55)),
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 16),
                  ],
                ),
                child: Icon(
                  criticalDown || down > 0
                      ? Icons.error_outline
                      : (degraded > 0
                          ? Icons.warning_amber_rounded
                          : Icons.verified_outlined),
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PulseDot(color: color),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Sa.display(size: 17, color: color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr(
                          'Live status of every backend SIAS depends on.'),
                      style: Sa.mono(size: 9.5, color: Sa.muted),
                    ),
                  ],
                ),
              ),
              SaButton(
                label: context.tr('RE-CHECK'),
                icon: Icons.sync,
                outlined: true,
                busy: controller.githubProbing || controller.ingestProbing,
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CountChip(
                  label: context.tr('Operational'),
                  count: op,
                  color: Sa.green),
              _CountChip(
                  label: context.tr('Degraded'),
                  count: degraded,
                  color: Sa.amber),
              _CountChip(
                  label: context.tr('Down'), count: down, color: Sa.red),
              if (unknown > 0)
                _CountChip(
                    label: context.tr('Probing'),
                    count: unknown,
                    color: Sa.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: Sa.display(size: 18, color: color)),
          const SizedBox(width: 8),
          Text(label.toUpperCase(),
              style: Sa.mono(size: 9, color: Sa.textDim, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  GROUP PANEL + SERVICE ROWS
// ════════════════════════════════════════════════════════════════════════════

class _GroupPanel extends StatelessWidget {
  final _StatusController controller;
  final _StatusGroup group;
  const _GroupPanel({required this.controller, required this.group});

  @override
  Widget build(BuildContext context) {
    final services =
        kStatusServices.where((s) => s.group == group.id).toList();
    final states = [for (final s in services) controller.stateFor(s.id)];
    final allUp = states.every((s) => s == LiveState.online);
    final anyDown = states.any((s) => s == LiveState.offline);
    final chipColor = anyDown ? Sa.red : (allUp ? Sa.green : Sa.amber);
    final chipLabel = anyDown
        ? context.tr('DISRUPTED')
        : (allUp ? context.tr('OPERATIONAL') : context.tr('DEGRADED'));

    return HoloPanel(
      accent: group.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoloHeader(
            icon: group.icon,
            title: context.tr(group.title),
            subtitle: context.tr(group.subtitle),
            accent: group.accent,
            trailing: GlowChip(
              label: chipLabel,
              color: chipColor,
              pulse: !anyDown,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < services.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Sa.border.withValues(alpha: 0.6)),
            _ServiceRow(
              svc: services[i],
              state: controller.stateFor(services[i].id),
              history: controller.history[services[i].id] ?? const [],
              detail: controller.detailFor(context, services[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final _Svc svc;
  final LiveState state;
  final List<LiveState> history;
  final String detail;
  const _ServiceRow({
    required this.svc,
    required this.state,
    required this.history,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final c = liveColor(state);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: svc.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: svc.accent.withValues(alpha: 0.35)),
                ),
                child: Icon(svc.icon, size: 17, color: svc.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr(svc.name), style: Sa.heading(size: 14)),
                    const SizedBox(height: 1),
                    Text(svc.sub, style: Sa.mono(size: 8.5, color: Sa.muted)),
                  ],
                ),
              ),
              _StatusLabel(state: state),
            ],
          ),
          const SizedBox(height: 10),
          _UptimeBar(history: history, color: c),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.schedule, size: 11, color: Sa.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Sa.mono(size: 9, color: Sa.textDim)),
              ),
              Text(
                _uptimeLabel(context, history),
                style: Sa.mono(size: 9, color: Sa.muted, weight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _uptimeLabel(BuildContext context, List<LiveState> hist) {
    final counted =
        hist.where((s) => s != LiveState.unknown).toList(growable: false);
    if (counted.isEmpty) return context.tr('no data yet');
    final up =
        counted.where((s) => s == LiveState.online || s == LiveState.idle).length;
    final pct = up / counted.length * 100;
    return context.tr('{pct}% session uptime', {
      'pct': pct.toStringAsFixed(pct >= 99.95 ? 0 : 1),
    });
  }
}

class _StatusLabel extends StatelessWidget {
  final LiveState state;
  const _StatusLabel({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = liveColor(state);
    final label = switch (state) {
      LiveState.online => context.tr('Operational'),
      LiveState.idle => context.tr('Degraded'),
      LiveState.offline => context.tr('Outage'),
      LiveState.unknown => context.tr('Probing'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state == LiveState.online)
          PulseDot(color: c, size: 7)
        else
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
        const SizedBox(width: 7),
        Text(label, style: Sa.heading(size: 12.5, color: c)),
      ],
    );
  }
}

/// A right-aligned rolling uptime strip — newest sample on the right, empty
/// slots faintly drawn while telemetry is still being collected.
class _UptimeBar extends StatelessWidget {
  final List<LiveState> history;
  final Color color;
  const _UptimeBar({required this.history, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      width: double.infinity,
      child: CustomPaint(
        painter: _UptimeBarPainter(history: history, border: Sa.border),
      ),
    );
  }
}

class _UptimeBarPainter extends CustomPainter {
  final List<LiveState> history;
  final Color border;
  static const int segments = 72;

  _UptimeBarPainter({required this.history, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    final segW = (size.width - (segments - 1) * gap) / segments;
    final radius = Radius.circular(segW / 2);
    for (var i = 0; i < segments; i++) {
      final idx = history.length - segments + i;
      final hasData = idx >= 0;
      final state = hasData ? history[idx] : null;
      final color = state == null
          ? border.withValues(alpha: 0.5)
          : liveColor(state).withValues(alpha: 0.92);
      final x = i * (segW + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, segW, size.height),
          radius,
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UptimeBarPainter old) =>
      old.history.length != history.length ||
      (history.isNotEmpty &&
          old.history.isNotEmpty &&
          old.history.last != history.last);
}

// ════════════════════════════════════════════════════════════════════════════
//  KUBIX COPILOT — owner-console entry point to the buyer-facing chat
// ════════════════════════════════════════════════════════════════════════════

class _KubixCopilotCard extends StatelessWidget {
  const _KubixCopilotCard();

  Future<void> _open(BuildContext context) async {
    // Per-tenant builds bake the tenant context into ALERTSYS_COPILOT_URL;
    // web tenants get it from window.__SIAS_CONFIG__ (resolvedCopilotUrl);
    // here we only append the console's active language.
    final base = AppConfig.resolvedCopilotUrl;
    final sep = base.contains('?') ? '&' : '?';
    final url = context.isFrench ? '$base${sep}lang=fr' : base;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best effort — the Status page keeps working if no browser is available.
    }
  }

  @override
  Widget build(BuildContext context) {
    return HoloPanel(
      accent: Sa.amber,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Sa.amber, Sa.amber.withValues(alpha: .55)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Sa.amber.withValues(alpha: .35),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Text(
              'K',
              style: Sa.mono(
                size: 19,
                color: const Color(0xFF14171C),
                weight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Kubix Copilot', style: Sa.heading(size: 14)),
                    const SizedBox(width: 8),
                    // Sa.* colors are palette getters — never const-capture them.
                    PulseDot(color: Sa.green, size: 7),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'Your dedicated SIAS engineer — activation, integrations, '
                    'anything. It knows this instance and answers in EN or FR.',
                  ),
                  style: Sa.body(size: 12, color: Sa.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SaButton(
            label: context.tr('OPEN COPILOT CHAT'),
            icon: Icons.forum_outlined,
            color: Sa.amber,
            onPressed: () => _open(context),
          ),
        ],
      ),
    );
  }
}

class _FootNote extends StatelessWidget {
  final _StatusController controller;
  const _FootNote({required this.controller});

  @override
  Widget build(BuildContext context) {
    final updated = controller.updatedAt;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.update, size: 12, color: Sa.muted),
        const SizedBox(width: 6),
        Text(
          updated == null
              ? context.tr('Collecting telemetry…')
              : context.tr('Last sampled {ago} · auto-refresh every 20s', {
                  'ago': shortAgo(context, updated),
                }),
          style: Sa.mono(size: 9.5, color: Sa.muted),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SERVICE CATALOG
// ════════════════════════════════════════════════════════════════════════════

class _Svc {
  final String id;
  final String name;
  final String sub;
  final IconData icon;
  final Color accent;
  final String group;

  /// Critical services pull the whole platform to MAJOR OUTAGE when they fall.
  final bool critical;

  const _Svc(this.id, this.name, this.sub, this.icon, this.accent, this.group,
      {this.critical = false});
}

// Accent colors are palette getters, so this can't be `const`.
final List<_Svc> kStatusServices = [
  _Svc('ai', 'AI · Security Worker', 'alert-notifier · cron 1m',
      Icons.psychology_outlined, Sa.violet, 'cloudflare', critical: true),
  _Svc('notify', 'Notifications Worker', 'alertsys · cron 1m',
      Icons.notifications_active_outlined, Sa.cyan, 'cloudflare',
      critical: true),
  _Svc('ingest', 'Ingest Worker', 'alertsys-ingest · SCADA / MQTT',
      Icons.input_outlined, Sa.amber, 'cloudflare'),
  _Svc('backup', 'Backup Worker', 'alertsys-backup · nightly R2',
      Icons.cloud_done_outlined, Sa.blue, 'cloudflare'),
  _Svc('monitor', 'Monitor Worker', 'alertsys-monitor · deadman 5m',
      Icons.radar_outlined, Sa.green, 'cloudflare'),
  _Svc('github', 'GitHub Integration', 'alertsys-github proxy',
      Icons.account_tree_outlined, Sa.pink, 'github'),
  _Svc('rtdb', 'Realtime Database', 'firebase · alertappsys',
      Icons.schema_outlined, Sa.amber, 'firebase', critical: true),
  _Svc('auth', 'Authentication', 'firebase auth',
      Icons.vpn_key_outlined, Sa.green, 'firebase', critical: true),
];

final List<String> kStatusServiceIds = [for (final s in kStatusServices) s.id];

class _StatusGroup {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  const _StatusGroup(
      this.id, this.title, this.subtitle, this.icon, this.accent);
}

final List<_StatusGroup> kStatusGroups = [
  _StatusGroup('cloudflare', 'CLOUDFLARE',
      'Edge workers — cron heartbeat & reachability', Icons.cloud_outlined, Sa.cyan),
  _StatusGroup('github', 'GITHUB',
      'Guardian CI integration via the edge proxy', Icons.hub_outlined, Sa.pink),
  _StatusGroup('firebase', 'FIREBASE',
      'Realtime Database & Authentication', Icons.local_fire_department_outlined,
      Sa.amber),
];

// ════════════════════════════════════════════════════════════════════════════
//  CONTROLLER
// ════════════════════════════════════════════════════════════════════════════

class _StatusController extends ChangeNotifier {
  _StatusController({FirebaseDatabase? db, GithubService? github})
      : _db = db ?? FirebaseDatabase.instance,
        _github = github ??
            GithubService(
              baseUrl: AppConfig.githubWorkerBase,
              sharedSecret: AppConfig.clientWorkerKey,
            );

  final FirebaseDatabase _db;
  final GithubService _github;
  final List<StreamSubscription> _subs = [];

  Map<String, dynamic>? aiHealth;
  Map<String, dynamic>? notifyHealth;
  Map<String, dynamic>? backupHealth;
  Map<String, dynamic>? monitorHealth;

  bool rtdbConnected = false;
  bool authReady = FirebaseAuth.instance.currentUser != null;
  ({bool connected, String repo})? github;
  bool githubProbing = false;
  LiveState ingestState = LiveState.unknown;
  bool ingestProbing = false;
  DateTime? updatedAt;

  final Map<String, List<LiveState>> history = {};
  static const int maxHistory = 90;

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _listen('workers/health/lastRun', (m) => aiHealth = m);
    _listen('workers/health/notifyLastRun', (m) => notifyHealth = m);
    _listen('workers/health/backup', (m) => backupHealth = m);
    _listen('workers/health/monitor', (m) => monitorHealth = m);
    _subs.add(_db.ref('.info/connected').onValue.listen((e) {
      rtdbConnected = e.snapshot.value == true;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(FirebaseAuth.instance.authStateChanges().listen((u) {
      authReady = u != null;
      notifyListeners();
    }));
    unawaited(probeAll());
  }

  void _listen(String path, void Function(Map<String, dynamic>?) assign) {
    _subs.add(_db.ref(path).onValue.listen((e) {
      final v = e.snapshot.value;
      assign(v is Map ? Map<String, dynamic>.from(v) : null);
      notifyListeners();
    }, onError: (_) {}));
  }

  Future<void> probeAll() async {
    await Future.wait([_probeGithub(), _probeIngest()]);
    sample();
  }

  Future<void> _probeGithub() async {
    if (githubProbing) return;
    githubProbing = true;
    notifyListeners();
    try {
      github = await _github.status();
    } catch (_) {
      github = (connected: false, repo: '');
    }
    githubProbing = false;
    notifyListeners();
  }

  Future<void> _probeIngest() async {
    if (ingestProbing) return;
    ingestProbing = true;
    notifyListeners();
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.resolvedIngestWorkerBase}/config'))
          .timeout(const Duration(seconds: 6));
      ingestState = (res.statusCode >= 200 && res.statusCode < 300)
          ? LiveState.online
          : LiveState.offline;
    } catch (_) {
      // A network/CORS failure from the web console isn't proof the worker is
      // down — leave it unknown rather than falsely red.
      ingestState = LiveState.unknown;
    }
    ingestProbing = false;
    notifyListeners();
  }

  LiveState stateFor(String id) {
    switch (id) {
      case 'ai':
        return workerLiveState(aiHealth, onMin: 3, idleMin: 10);
      case 'notify':
        return workerLiveState(notifyHealth, onMin: 3, idleMin: 10);
      case 'backup':
        return workerLiveState(backupHealth,
            onMin: 26 * 60, idleMin: 50 * 60, okKey: 'ok');
      case 'monitor':
        return workerLiveState(monitorHealth,
            onMin: 7, idleMin: 20, stateKey: 'state');
      case 'ingest':
        return ingestState;
      case 'github':
        return github == null
            ? LiveState.unknown
            : (github!.connected ? LiveState.online : LiveState.offline);
      case 'rtdb':
        return rtdbConnected ? LiveState.online : LiveState.offline;
      case 'auth':
        return authReady ? LiveState.online : LiveState.offline;
      default:
        return LiveState.unknown;
    }
  }

  String detailFor(BuildContext context, String id) {
    switch (id) {
      case 'ai':
        return _ranAgo(context, aiHealth);
      case 'notify':
        return _ranAgo(context, notifyHealth);
      case 'backup':
        return _ranAgo(context, backupHealth);
      case 'monitor':
        return _ranAgo(context, monitorHealth);
      case 'ingest':
        return ingestProbing
            ? context.tr('probing…')
            : (ingestState == LiveState.unknown
                ? context.tr('config probe blocked')
                : context.tr('config probe ok'));
      case 'github':
        final g = github;
        if (githubProbing) return context.tr('probing…');
        if (g == null) return context.tr('probing…');
        if (!g.connected) return context.tr('proxy unreachable');
        return g.repo.isEmpty ? context.tr('connected') : g.repo;
      case 'rtdb':
        return rtdbConnected
            ? context.tr('socket connected')
            : context.tr('socket lost');
      case 'auth':
        return authReady
            ? context.tr('session authenticated')
            : context.tr('signed out');
      default:
        return '';
    }
  }

  static String _ranAgo(BuildContext context, Map<String, dynamic>? data) {
    final at = DateTime.tryParse(
        (data?['at'] ?? data?['finishedAt'] ?? data?['ranAt'] ?? '').toString());
    if (at == null) return context.tr('no heartbeat yet');
    return context.tr('ran {ago}', {'ago': shortAgo(context, at)});
  }

  void sample() {
    for (final id in kStatusServiceIds) {
      final list = history.putIfAbsent(id, () => <LiveState>[]);
      list.add(stateFor(id));
      if (list.length > maxHistory) list.removeAt(0);
    }
    updatedAt = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../l10n/app_strings.dart';
import '../../../services/github_service.dart';
import '../../../services/telemetry_service.dart';
import '../hardware/hw_machines.dart';

/// Liveness state shared by workers, agents and sessions.
enum LiveState { online, idle, offline, unknown }

/// One logged-in account, derived live from the `users` node. Online state is
/// inferred from `lastSeen` (written on login and on every FCM token refresh).
class SessionRow {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String factory;
  final String status;
  final bool pushEnabled;
  final bool located;
  final DateTime? lastSeen;

  const SessionRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.factory,
    required this.status,
    required this.pushEnabled,
    required this.located,
    required this.lastSeen,
  });

  Duration? get age =>
      lastSeen == null ? null : DateTime.now().difference(lastSeen!);

  LiveState get state {
    final a = age;
    if (a == null) return LiveState.unknown;
    if (a.inMinutes <= 4) return LiveState.online;
    if (a.inMinutes <= 30) return LiveState.idle;
    return LiveState.offline;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return email.isNotEmpty ? email[0].toUpperCase() : '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

/// Runtime state of one fleet agent read from `ai_agents/{id}`.
class AgentRuntime {
  final bool enabled;
  final Map<String, dynamic> stats;
  const AgentRuntime({required this.enabled, this.stats = const {}});

  /// Best-effort headline number from the agent's stats deck.
  int get headline {
    const preferred = [
      'runs', 'served', 'assignments', 'generated', 'blocked', 'graded',
      'sent', 'count', 'total', 'cycles', 'processed',
    ];
    for (final k in preferred) {
      final v = stats[k];
      if (v is num) return v.toInt();
    }
    var sum = 0;
    for (final v in stats.values) {
      if (v is num) sum += v.toInt();
    }
    return sum;
  }
}

/// A conceptual Realtime Database root, hand-placed for the topology hologram.
class DbNodeSpec {
  final String path;
  final String label;
  final String domain;
  final double x; // normalized 0..1
  final double y;
  const DbNodeSpec(this.path, this.label, this.domain, this.x, this.y);
}

const List<DbNodeSpec> kDbNodes = [
  DbNodeSpec('alerts', 'alerts', 'operations', 0.16, 0.30),
  DbNodeSpec('alertCounter', 'alertCounter', 'operations', 0.06, 0.13),
  DbNodeSpec('supervisor_active_alerts', 'active_claims', 'operations', 0.19, 0.60),
  DbNodeSpec('hierarchy', 'hierarchy', 'operations', 0.07, 0.45),
  DbNodeSpec('assets', 'assets', 'operations', 0.07, 0.74),
  DbNodeSpec('users', 'users', 'people', 0.40, 0.15),
  DbNodeSpec('notifications', 'notifications', 'people', 0.43, 0.44),
  DbNodeSpec('collaboration_requests', 'collaborations', 'coordination', 0.34, 0.71),
  DbNodeSpec('help_requests', 'help_requests', 'coordination', 0.49, 0.87),
  DbNodeSpec('shifts', 'shifts', 'coordination', 0.61, 0.67),
  DbNodeSpec('shift_presence', 'shift_presence', 'coordination', 0.73, 0.85),
  DbNodeSpec('ai_decisions', 'ai_decisions', 'ai', 0.60, 0.17),
  DbNodeSpec('ai_predictions', 'ai_predictions', 'ai', 0.73, 0.37),
  DbNodeSpec('ai_forecast', 'ai_forecast', 'ai', 0.88, 0.19),
  DbNodeSpec('ai_briefing', 'ai_briefing', 'ai', 0.86, 0.53),
  DbNodeSpec('ai_agents', 'ai_agents', 'ai', 0.50, 0.30),
  DbNodeSpec('hardware_lab', 'hardware_lab', 'platform', 0.30, 0.88),
  DbNodeSpec('security/logs', 'security', 'platform', 0.90, 0.75),
  DbNodeSpec('workers/health', 'worker_health', 'platform', 0.73, 0.10),
  DbNodeSpec('bugs/client', 'bugs', 'platform', 0.94, 0.40),
];

const List<(String, String)> kDbEdges = [
  ('alerts', 'users'),
  ('alerts', 'alertCounter'),
  ('alerts', 'supervisor_active_alerts'),
  ('alerts', 'hierarchy'),
  ('hierarchy', 'assets'),
  ('hierarchy', 'hardware_lab'),
  ('users', 'notifications'),
  ('alerts', 'notifications'),
  ('alerts', 'collaboration_requests'),
  ('collaboration_requests', 'help_requests'),
  ('users', 'shifts'),
  ('shifts', 'shift_presence'),
  ('alerts', 'ai_decisions'),
  ('ai_decisions', 'ai_predictions'),
  ('ai_forecast', 'ai_predictions'),
  ('ai_predictions', 'ai_briefing'),
  ('ai_agents', 'ai_decisions'),
  ('workers/health', 'ai_agents'),
  ('workers/health', 'security/logs'),
  ('bugs/client', 'workers/health'),
];

/// Owns every live stream and one-shot probe behind the Overview Monitor.
///
/// A single [ChangeNotifier] so the war-room rebuilds coherently and every
/// painter shares the same snapshot. Heavy work (factory catalog, RTDB shallow
/// probe, GitHub proxy reachability) runs on demand via [refreshHeavy].
class MonitorController extends ChangeNotifier {
  MonitorController({FirebaseDatabase? db, GithubService? github})
      : _db = db ?? FirebaseDatabase.instance,
        _github = github ??
            GithubService(
              baseUrl: AppConfig.githubWorkerBase,
              sharedSecret: AppConfig.workerSharedSecret,
            );

  final FirebaseDatabase _db;
  final GithubService _github;

  final List<StreamSubscription<DatabaseEvent>> _subs = [];

  Map<String, dynamic>? aiHealth;
  Map<String, dynamic>? notifyHealth;
  Map<String, dynamic>? backupHealth;
  Map<String, dynamic>? monitorHealth;

  final Map<String, AgentRuntime> _agents = {};
  AgentRuntime agent(String id) =>
      _agents[id] ?? const AgentRuntime(enabled: true);

  /// One-shot fetch of an agent's most recent `ai_agents/{id}/logs` entry,
  /// for the fleet detail popup. Not kept as a live subscription — the
  /// fleet constellation only needs this when an operator opens the dialog.
  Future<Map<String, dynamic>?> fetchLatestAgentLog(String id) async {
    try {
      final snap = await _db.ref('ai_agents/$id/logs').limitToLast(1).get();
      final v = snap.value;
      if (v is Map && v.isNotEmpty) {
        return Map<String, dynamic>.from(v.values.first as Map);
      }
    } catch (_) {}
    return null;
  }

  List<SessionRow> sessions = const [];

  int telemetrySessions = 0;
  int telemetryErrors = 0;
  int telemetryErrorSessions = 0;

  List<Map<String, dynamic>> securityActions = const [];
  int openBugs = 0;
  int totalBugs = 0;

  HwFactoryCatalog? catalog;
  bool catalogLoading = false;

  final Map<String, int?> dbCounts = {};
  final Map<String, bool> dbReachable = {};
  bool dbProbing = false;
  DateTime? dbProbedAt;

  ({bool connected, String repo})? github;
  bool githubProbing = false;

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;

    _listen('workers/health/lastRun', (m) => aiHealth = m);
    _listen('workers/health/notifyLastRun', (m) => notifyHealth = m);
    _listen('workers/health/backup', (m) => backupHealth = m);
    _listen('workers/health/monitor', (m) => monitorHealth = m);

    _subs.add(_db.ref('ai_agents').onValue.listen((e) {
      _agents.clear();
      final v = e.snapshot.value;
      if (v is Map) {
        v.forEach((k, val) {
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            _agents['$k'] = AgentRuntime(
              enabled: m['enabled'] != false,
              stats: m['stats'] is Map
                  ? Map<String, dynamic>.from(m['stats'] as Map)
                  : const {},
            );
          }
        });
      }
      notifyListeners();
    }, onError: (_) {}));

    _subs.add(_db.ref('users').onValue.listen((e) {
      sessions = _decodeSessions(e.snapshot.value);
      notifyListeners();
    }, onError: (_) {}));

    _subs.add(_db
        .ref('telemetry/daily/${TelemetryService.todayKey()}')
        .onValue
        .listen((e) {
      final v = e.snapshot.value;
      if (v is Map) {
        telemetrySessions = (v['sessions'] as num?)?.toInt() ?? 0;
        telemetryErrors = (v['errors'] as num?)?.toInt() ?? 0;
        telemetryErrorSessions = (v['errorSessions'] as num?)?.toInt() ?? 0;
      }
      notifyListeners();
    }, onError: (_) {}));

    _subs.add(_db
        .ref('security/actions')
        .limitToLast(28)
        .onValue
        .listen((e) {
      securityActions = _decodeList(e.snapshot.value, 'at');
      notifyListeners();
    }, onError: (_) {}));

    _subs.add(_db.ref('bugs/client').limitToLast(200).onValue.listen((e) {
      final v = e.snapshot.value;
      var open = 0, total = 0;
      if (v is Map) {
        v.forEach((_, val) {
          if (val is Map) {
            total++;
            if ((val['status'] ?? 'detected') == 'detected') open++;
          }
        });
      }
      openBugs = open;
      totalBugs = total;
      notifyListeners();
    }, onError: (_) {}));

    unawaited(refreshHeavy());
  }

  static List<Map<String, dynamic>> _decodeList(Object? v, String sortKey) {
    final list = <Map<String, dynamic>>[];
    if (v is Map) {
      v.forEach((k, val) {
        if (val is Map) {
          final m = Map<String, dynamic>.from(val);
          m['id'] = k.toString();
          list.add(m);
        }
      });
      list.sort((a, b) =>
          (b[sortKey] ?? '').toString().compareTo((a[sortKey] ?? '').toString()));
    }
    return list;
  }

  void _listen(String path, void Function(Map<String, dynamic>?) assign) {
    _subs.add(_db.ref(path).onValue.listen((e) {
      final v = e.snapshot.value;
      assign(v is Map ? Map<String, dynamic>.from(v) : null);
      notifyListeners();
    }, onError: (_) {}));
  }

  static List<SessionRow> _decodeSessions(Object? v) {
    final out = <SessionRow>[];
    if (v is Map) {
      v.forEach((uid, val) {
        if (val is! Map) return;
        final m = Map<String, dynamic>.from(val);
        final first = (m['firstName'] ?? '').toString().trim();
        final last = (m['lastName'] ?? '').toString().trim();
        final name = '$first $last'.trim();
        final loc = m['currentLocation'];
        out.add(SessionRow(
          uid: '$uid',
          name: name.isEmpty ? (m['email'] ?? '$uid').toString() : name,
          email: (m['email'] ?? '').toString(),
          role: (m['role'] ?? 'supervisor').toString(),
          factory: (m['factoryName'] ?? m['usine'] ?? '').toString(),
          status: (m['status'] ?? '').toString(),
          pushEnabled: (m['fcmToken'] ?? '').toString().isNotEmpty,
          located: loc is Map && loc['lat'] != null && loc['lng'] != null,
          lastSeen: DateTime.tryParse((m['lastSeen'] ?? '').toString()),
        ));
      });
    }
    out.sort((a, b) {
      // Online first, then most recently seen.
      final sa = a.state.index, sb = b.state.index;
      if (sa != sb) return sa.compareTo(sb);
      final la = a.lastSeen?.millisecondsSinceEpoch ?? 0;
      final lb = b.lastSeen?.millisecondsSinceEpoch ?? 0;
      return lb.compareTo(la);
    });
    return out;
  }

  int get onlineSessions =>
      sessions.where((s) => s.state == LiveState.online).length;
  int get idleSessions =>
      sessions.where((s) => s.state == LiveState.idle).length;

  /// Reloads the factory catalog, re-probes the RTDB topology and re-checks the
  /// GitHub proxy worker. Safe to call repeatedly.
  Future<void> refreshHeavy() async {
    await Future.wait([
      _loadCatalog(),
      probeDatabase(),
      _probeGithub(),
    ]);
  }

  Future<void> _loadCatalog() async {
    if (catalogLoading) return;
    catalogLoading = true;
    notifyListeners();
    try {
      catalog = await HwMachineStore(db: _db).loadCatalog();
    } catch (_) {}
    catalogLoading = false;
    notifyListeners();
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

  Future<void> probeDatabase() async {
    if (dbProbing) return;
    dbProbing = true;
    notifyListeners();

    final dbUrl = _db.app.options.databaseURL?.replaceAll(RegExp(r'/$'), '');
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    for (final node in kDbNodes) {
      var count = dbCounts[node.path];
      var ok = false;
      if (dbUrl != null && token != null) {
        try {
          final res = await http
              .get(Uri.parse('$dbUrl/${node.path}.json?shallow=true&auth=$token'))
              .timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            ok = true;
            final body = jsonDecode(res.body);
            count = body is Map ? body.length : (body == null ? 0 : 1);
          }
        } catch (_) {}
      }
      dbCounts[node.path] = count;
      dbReachable[node.path] = ok;
      notifyListeners();
    }

    dbProbing = false;
    dbProbedAt = DateTime.now();
    notifyListeners();
  }

  int get dbReachableCount =>
      dbReachable.values.where((v) => v).length;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}

/// Parsed freshness of a worker health pulse.
class WorkerFreshness {
  final DateTime? at;
  final Duration? age;
  final LiveState state;
  const WorkerFreshness(this.at, this.age, this.state);

  factory WorkerFreshness.from(Map<String, dynamic>? data) {
    if (data == null) return const WorkerFreshness(null, null, LiveState.unknown);
    final at = DateTime.tryParse(
        (data['at'] ?? data['finishedAt'] ?? data['ranAt'] ?? '').toString());
    if (at == null) return const WorkerFreshness(null, null, LiveState.unknown);
    final age = DateTime.now().toUtc().difference(at.toUtc());
    final state = age.inMinutes <= 3
        ? LiveState.online
        : (age.inMinutes <= 10 ? LiveState.idle : LiveState.offline);
    return WorkerFreshness(at, age, state);
  }

  String get ageLabel {
    final a = age;
    if (a == null) return '—';
    if (a.inSeconds < 90) return '${a.inSeconds}s ago';
    if (a.inMinutes < 90) return '${a.inMinutes}m ago';
    if (a.inHours < 48) return '${a.inHours}h ago';
    return '${a.inDays}d ago';
  }
}

/// Resolves a worker's [LiveState] from its health pulse using per-worker
/// freshness windows (minutes). [okKey]/[stateKey] force OFFLINE on an explicit
/// failure or degraded flag.
LiveState workerLiveState(
  Map<String, dynamic>? data, {
  required int onMin,
  required int idleMin,
  String? okKey,
  String? stateKey,
}) {
  final at = DateTime.tryParse(
      (data?['at'] ?? data?['finishedAt'] ?? data?['ranAt'] ?? '').toString());
  if (data == null || at == null) return LiveState.unknown;
  if (okKey != null && data[okKey] == false) return LiveState.offline;
  if (stateKey != null && (data[stateKey] ?? '').toString() == 'degraded') {
    return LiveState.offline;
  }
  final mins = DateTime.now().toUtc().difference(at.toUtc()).inMinutes;
  return mins <= onMin
      ? LiveState.online
      : (mins <= idleMin ? LiveState.idle : LiveState.offline);
}

String shortAgo(BuildContext context, DateTime? t) {
  if (t == null) return context.tr('never');
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) {
    return context.tr('{n}s ago', {'n': '${d.inSeconds}'});
  }
  if (d.inMinutes < 60) {
    return context.tr('{n}m ago', {'n': '${d.inMinutes}'});
  }
  if (d.inHours < 24) {
    return context.tr('{n}h ago', {'n': '${d.inHours}'});
  }
  return context.tr('{n}d ago', {'n': '${d.inDays}'});
}

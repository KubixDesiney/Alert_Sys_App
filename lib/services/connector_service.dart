import 'dart:convert';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Industrial connector framework (SuperAdmin → Infrastructure → Connectors).
///
/// Lets the IT team wire SIAS on top of an existing automation estate — SCADA,
/// PLC, historian, MQTT broker, or any REST source — without ripping anything
/// out. Two honest ingestion modes, both handled by `cloudflare_ingest_worker.js`:
///
///  * **pull**  — the worker reaches OUT on a per-minute cron and polls an
///    HTTPS-reachable source (PI Web API, Ignition, REST) with the stored token.
///  * **push**  — an edge gateway near the PLC POSTs telemetry to
///    `/ingest/{id}` (the only real path off an air-gapped OT network).
///  * **mqtt**  — a broker rule posts in (push) and `Verify` proves the broker
///    link with a real MQTT CONNECT/CONNACK over WebSocket.
///
/// Non-secret config lives in RTDB `connectors/{id}`; credentials live write-only
/// in `connector_secrets/{id}` (SuperAdmin + the worker only). The worker writes
/// live `runtime` status back; the console streams it.
enum ConnectorMode { pull, push, mqtt }

enum ConnectorKind {
  opcua('opcua', 'OPC-UA · SCADA / DCS', ConnectorMode.push),
  modbus('modbus', 'Modbus TCP · PLC', ConnectorMode.push),
  mqtt('mqtt', 'MQTT / Sparkplug B', ConnectorMode.mqtt),
  historianPi('historian_pi', 'Historian · OSIsoft / AVEVA PI', ConnectorMode.pull),
  historianIgnition('historian_ignition', 'Historian · Ignition', ConnectorMode.pull),
  rest('rest', 'REST / Webhook · MES / CMMS', ConnectorMode.pull),
  microcontroller('microcontroller', 'Microcontroller · ESP32 / Arduino', ConnectorMode.push),
  custom('custom', 'Custom / Generic', ConnectorMode.push);

  const ConnectorKind(this.wireId, this.label, this.mode);

  /// The string the worker uses (mirrors PULL_KINDS / PUSH_KINDS / mqtt).
  final String wireId;
  final String label;
  final ConnectorMode mode;

  bool get isPull => mode == ConnectorMode.pull;
  bool get isPush => mode == ConnectorMode.push;
  bool get isMqtt => mode == ConnectorMode.mqtt;

  static ConnectorKind fromWire(String? id) => values.firstWhere(
        (k) => k.wireId == id,
        orElse: () => ConnectorKind.custom,
      );
}

class ConnectorThresholds {
  final num? warn;
  final num? critical;
  final String direction; // 'high' (default) | 'low'

  const ConnectorThresholds({this.warn, this.critical, this.direction = 'high'});

  bool get isEmpty => warn == null && critical == null;

  Map<String, dynamic> toMap() => {
        if (warn != null) 'warn': warn,
        if (critical != null) 'critical': critical,
        'direction': direction,
      };

  factory ConnectorThresholds.fromMap(Map? m) {
    if (m == null) return const ConnectorThresholds();
    num? n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
    return ConnectorThresholds(
      warn: n(m['warn']),
      critical: n(m['critical']),
      direction: (m['direction'] ?? 'high').toString(),
    );
  }
}

/// One tag / register / node / metric the connector reads or receives.
class ConnectorTag {
  final String tag; // source identifier (PI tag, Modbus register, OPC node id…)
  final String metric; // human metric name → drives canonical type inference
  final String? type; // explicit canonical type override (Mechanical/…)
  final String? unit;
  final String? valuePath; // pull: JSON path to the value in the response
  final String? webId; // pull: PI Web API stream WebId
  final String? path; // pull: URL path template, e.g. /tags/{tag}/value
  final ConnectorThresholds thresholds;

  const ConnectorTag({
    required this.tag,
    this.metric = '',
    this.type,
    this.unit,
    this.valuePath,
    this.webId,
    this.path,
    this.thresholds = const ConnectorThresholds(),
  });

  Map<String, dynamic> toMap() => {
        'tag': tag,
        if (metric.isNotEmpty) 'metric': metric,
        if (type != null && type!.isNotEmpty) 'type': type,
        if (unit != null && unit!.isNotEmpty) 'unit': unit,
        if (valuePath != null && valuePath!.isNotEmpty) 'valuePath': valuePath,
        if (webId != null && webId!.isNotEmpty) 'webId': webId,
        if (path != null && path!.isNotEmpty) 'path': path,
        if (!thresholds.isEmpty) 'thresholds': thresholds.toMap(),
      };

  factory ConnectorTag.fromMap(Map m) => ConnectorTag(
        tag: (m['tag'] ?? '').toString(),
        metric: (m['metric'] ?? '').toString(),
        type: m['type']?.toString(),
        unit: m['unit']?.toString(),
        valuePath: m['valuePath']?.toString(),
        webId: m['webId']?.toString(),
        path: m['path']?.toString(),
        thresholds: ConnectorThresholds.fromMap(m['thresholds'] as Map?),
      );

  ConnectorTag copyWith({
    String? tag,
    String? metric,
    String? type,
    String? unit,
    String? valuePath,
    String? webId,
    String? path,
    ConnectorThresholds? thresholds,
  }) =>
      ConnectorTag(
        tag: tag ?? this.tag,
        metric: metric ?? this.metric,
        type: type ?? this.type,
        unit: unit ?? this.unit,
        valuePath: valuePath ?? this.valuePath,
        webId: webId ?? this.webId,
        path: path ?? this.path,
        thresholds: thresholds ?? this.thresholds,
      );
}

class ConnectorAuth {
  final String scheme; // none | bearer | basic | header | query
  final String? headerName; // for scheme=header
  final String? queryParam; // for scheme=query
  final String? username; // non-secret half of basic auth

  const ConnectorAuth({
    this.scheme = 'none',
    this.headerName,
    this.queryParam,
    this.username,
  });

  Map<String, dynamic> toMap() => {
        'scheme': scheme,
        if (headerName != null && headerName!.isNotEmpty) 'headerName': headerName,
        if (queryParam != null && queryParam!.isNotEmpty) 'queryParam': queryParam,
        if (username != null && username!.isNotEmpty) 'username': username,
      };

  factory ConnectorAuth.fromMap(Map? m) {
    if (m == null) return const ConnectorAuth();
    return ConnectorAuth(
      scheme: (m['scheme'] ?? 'none').toString(),
      headerName: m['headerName']?.toString(),
      queryParam: m['queryParam']?.toString(),
      username: m['username']?.toString(),
    );
  }
}

/// Worker-written live status (read-only in the app).
class ConnectorRuntime {
  final String status; // linked | waiting | error | idle | ''
  final bool lastVerifyOk;
  final String lastVerifyAt;
  final String lastVerifyMessage;
  final String lastIngestAt;
  final String lastPollAt;
  final String lastError;
  final int eventsIngested;
  final num? lastValue;

  const ConnectorRuntime({
    this.status = '',
    this.lastVerifyOk = false,
    this.lastVerifyAt = '',
    this.lastVerifyMessage = '',
    this.lastIngestAt = '',
    this.lastPollAt = '',
    this.lastError = '',
    this.eventsIngested = 0,
    this.lastValue,
  });

  factory ConnectorRuntime.fromMap(Map? m) {
    if (m == null) return const ConnectorRuntime();
    int i(dynamic v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    return ConnectorRuntime(
      status: (m['status'] ?? '').toString(),
      lastVerifyOk: m['lastVerifyOk'] == true,
      lastVerifyAt: (m['lastVerifyAt'] ?? '').toString(),
      lastVerifyMessage: (m['lastVerifyMessage'] ?? '').toString(),
      lastIngestAt: (m['lastIngestAt'] ?? '').toString(),
      lastPollAt: (m['lastPollAt'] ?? '').toString(),
      lastError: (m['lastError'] ?? '').toString(),
      eventsIngested: i(m['eventsIngested']),
      lastValue: m['lastValue'] is num ? m['lastValue'] as num : null,
    );
  }
}

class IndustrialConnector {
  final String id;
  final String name;
  final ConnectorKind kind;
  final bool enabled;
  final String factory;
  final String line;
  final String station;
  final String endpoint;
  final int pollIntervalSec;
  final ConnectorAuth auth;
  final List<ConnectorTag> tags;
  final String mqttTopic;
  final String mqttClientId;
  final ConnectorRuntime runtime;
  final String createdAt;

  const IndustrialConnector({
    required this.id,
    required this.name,
    required this.kind,
    this.enabled = true,
    this.factory = '',
    this.line = '',
    this.station = '',
    this.endpoint = '',
    this.pollIntervalSec = 60,
    this.auth = const ConnectorAuth(),
    this.tags = const [],
    this.mqttTopic = '',
    this.mqttClientId = '',
    this.runtime = const ConnectorRuntime(),
    this.createdAt = '',
  });

  ConnectorMode get mode => kind.mode;

  /// Non-secret config persisted to `connectors/{id}` (never `runtime`, which is
  /// worker-owned, so `update()` preserves it).
  Map<String, dynamic> toMap() => {
        'name': name,
        'kind': kind.wireId,
        'mode': kind.mode.name,
        'enabled': enabled,
        'factory': factory.trim(),
        'line': line.trim(),
        'station': station.trim(),
        'endpoint': endpoint.trim(),
        'pollIntervalSec': pollIntervalSec,
        'auth': auth.toMap(),
        'tags': tags.map((t) => t.toMap()).toList(),
        if (kind.isMqtt) 'mqtt': {'topic': mqttTopic, 'clientId': mqttClientId},
        'createdAt': createdAt.isEmpty ? DateTime.now().toIso8601String() : createdAt,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  factory IndustrialConnector.fromMap(String id, Map m) {
    final mqtt = m['mqtt'] as Map?;
    return IndustrialConnector(
      id: id,
      name: (m['name'] ?? '').toString(),
      kind: ConnectorKind.fromWire(m['kind']?.toString()),
      enabled: m['enabled'] != false,
      factory: (m['factory'] ?? '').toString(),
      line: (m['line'] ?? '').toString(),
      station: (m['station'] ?? '').toString(),
      endpoint: (m['endpoint'] ?? '').toString(),
      pollIntervalSec: m['pollIntervalSec'] is int
          ? m['pollIntervalSec'] as int
          : int.tryParse('${m['pollIntervalSec'] ?? 60}') ?? 60,
      auth: ConnectorAuth.fromMap(m['auth'] as Map?),
      tags: ((m['tags'] as List?) ?? const [])
          .whereType<Map>()
          .map(ConnectorTag.fromMap)
          .toList(),
      mqttTopic: (mqtt?['topic'] ?? '').toString(),
      mqttClientId: (mqtt?['clientId'] ?? '').toString(),
      runtime: ConnectorRuntime.fromMap(m['runtime'] as Map?),
      createdAt: (m['createdAt'] ?? '').toString(),
    );
  }

  IndustrialConnector copyWith({
    String? name,
    ConnectorKind? kind,
    bool? enabled,
    String? factory,
    String? line,
    String? station,
    String? endpoint,
    int? pollIntervalSec,
    ConnectorAuth? auth,
    List<ConnectorTag>? tags,
    String? mqttTopic,
    String? mqttClientId,
  }) =>
      IndustrialConnector(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        enabled: enabled ?? this.enabled,
        factory: factory ?? this.factory,
        line: line ?? this.line,
        station: station ?? this.station,
        endpoint: endpoint ?? this.endpoint,
        pollIntervalSec: pollIntervalSec ?? this.pollIntervalSec,
        auth: auth ?? this.auth,
        tags: tags ?? this.tags,
        mqttTopic: mqttTopic ?? this.mqttTopic,
        mqttClientId: mqttClientId ?? this.mqttClientId,
        runtime: runtime,
        createdAt: createdAt,
      );
}

/// Write-only credential bundle for `connector_secrets/{id}`.
class ConnectorSecret {
  final String? token; // bearer / api-key / query value / MQTT password
  final String? username; // basic / MQTT username (if you prefer it secret)
  final String? password; // basic auth password
  final String? ingestKey; // per-connector edge-push key

  const ConnectorSecret({this.token, this.username, this.password, this.ingestKey});

  /// Only non-empty fields, so editing without re-typing a secret never wipes it.
  Map<String, dynamic> toUpdate() => {
        if (token != null && token!.trim().isNotEmpty) 'token': token!.trim(),
        if (username != null && username!.trim().isNotEmpty) 'username': username!.trim(),
        if (password != null && password!.trim().isNotEmpty) 'password': password!.trim(),
        if (ingestKey != null && ingestKey!.trim().isNotEmpty) 'ingestKey': ingestKey!.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

  bool get hasAny =>
      [token, username, password, ingestKey].any((v) => v != null && v.trim().isNotEmpty);
}

class VerifyResult {
  final bool ok;
  final String status; // linked | waiting | error
  final String message;
  final num? sample;

  const VerifyResult(this.ok, this.status, this.message, [this.sample]);

  factory VerifyResult.fromMap(Map m) => VerifyResult(
        m['ok'] == true,
        (m['status'] ?? 'error').toString(),
        (m['message'] ?? '').toString(),
        m['sample'] is num ? m['sample'] as num : null,
      );
}

class ConnectorService {
  ConnectorService({FirebaseDatabase? db, http.Client? client})
      : _db = db ?? FirebaseDatabase.instance,
        _http = client ?? http.Client();

  final FirebaseDatabase _db;
  final http.Client _http;

  DatabaseReference get _ref => _db.ref('connectors');
  DatabaseReference get _secretRef => _db.ref('connector_secrets');

  Stream<List<IndustrialConnector>> stream() => _ref.onValue.map((e) {
        final v = e.snapshot.value;
        if (v is! Map) return <IndustrialConnector>[];
        final list = v.entries
            .where((kv) => kv.value is Map)
            .map((kv) => IndustrialConnector.fromMap(
                kv.key.toString(), (kv.value as Map)))
            .toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  Future<List<IndustrialConnector>> fetchOnce() async {
    final snap = await _ref.get();
    final v = snap.value;
    if (v is! Map) return [];
    return v.entries
        .where((kv) => kv.value is Map)
        .map((kv) => IndustrialConnector.fromMap(kv.key.toString(), kv.value as Map))
        .toList();
  }

  /// Create a fresh connector id.
  String newId() => _ref.push().key ?? 'c${DateTime.now().millisecondsSinceEpoch}';

  /// Persists non-secret config (preserves worker-owned `runtime` via update).
  Future<void> save(IndustrialConnector c) => _ref.child(c.id).update(c.toMap());

  /// Persists only the provided secret fields.
  Future<void> saveSecret(String id, ConnectorSecret secret) async {
    if (!secret.hasAny) return;
    await _secretRef.child(id).update(secret.toUpdate());
  }

  Future<void> setEnabled(String id, bool enabled) =>
      _ref.child(id).update({'enabled': enabled, 'updatedAt': DateTime.now().toIso8601String()});

  Future<void> delete(String id) async {
    await _ref.child(id).remove();
    await _secretRef.child(id).remove();
  }

  /// Reads back the per-connector ingest key for display. This is the only field
  /// in `connector_secrets` a client may read — the rules expose just
  /// `connector_secrets/{id}/ingestKey` to SuperAdmin (the gateway operator needs
  /// it), while pull tokens/passwords stay worker-only. See `database.rules.json`.
  Future<String?> fetchIngestKey(String id) async {
    final snap = await _secretRef.child(id).child('ingestKey').get();
    final v = snap.value;
    return v?.toString();
  }

  /// A strong per-connector ingest key for edge-push gateways.
  String generateIngestKey() {
    final r = Random.secure();
    final bytes = List<int>.generate(24, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// The exact URL an edge gateway POSTs telemetry to for this connector.
  String ingestUrl(String id) => AppConfig.connectorIngestEndpoint(id);

  Map<String, String> get _authHeaders {
    final secret = AppConfig.clientWorkerKey;
    return {
      'Content-Type': 'application/json',
      if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
    };
  }

  /// The real "Verify link test": for pull/MQTT connectors the worker does a live
  /// handshake (HTTP read of a value, or MQTT CONNECT/CONNACK); for edge-push it
  /// confirms genuine inbound packets are flowing.
  Future<VerifyResult> verify(String id) async {
    try {
      final res = await _http
          .post(
            Uri.parse(AppConfig.connectorVerifyEndpoint),
            headers: _authHeaders,
            body: jsonEncode({'connectorId': id}),
          )
          .timeout(const Duration(seconds: 16));
      if (res.statusCode == 200) {
        return VerifyResult.fromMap(jsonDecode(res.body) as Map);
      }
      String detail = 'HTTP ${res.statusCode}';
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['error'] != null) detail = m['error'].toString();
      } catch (_) {}
      return VerifyResult(false, 'error', 'Verify failed: $detail');
    } catch (e) {
      return VerifyResult(false, 'error', 'Could not reach the ingest worker: $e');
    }
  }

  /// Force an immediate cloud-pull of a connector (otherwise the cron polls it).
  Future<({bool ok, int created, String message})> pollNow(String id) async {
    try {
      final res = await _http
          .post(
            Uri.parse(AppConfig.connectorControlEndpoint),
            headers: _authHeaders,
            body: jsonEncode({'action': 'poll', 'connectorId': id}),
          )
          .timeout(const Duration(seconds: 16));
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map;
        final created = (m['created'] is int) ? m['created'] as int : 0;
        return (ok: true, created: created, message: 'Polled · $created alert(s) raised');
      }
      return (ok: false, created: 0, message: 'Poll failed: HTTP ${res.statusCode}');
    } catch (e) {
      return (ok: false, created: 0, message: 'Poll failed: $e');
    }
  }
}

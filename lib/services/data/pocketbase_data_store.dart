import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/alert_model.dart';
import 'data_store.dart';
import 'onprem_session.dart';

/// [DataStore] backed by a self-hosted PocketBase instance (on-prem path).
/// Pure REST + polling — this file imports no Firebase package and performs
/// no Firebase I/O. Realtime SSE can replace polling later without changing
/// callers; the worker-runner already pushes LAN SSE events for
/// assignment/escalation/new-alert wake-ups.
class PocketBaseDataStore implements DataStore {
  PocketBaseDataStore({
    required String baseUrl,
    String? token,
    Duration pollInterval = const Duration(seconds: 5),
    http.Client? client,
    DateTime Function()? now,
  })  : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _fixedToken = token ?? '',
        _pollInterval = pollInterval,
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final String _base;
  final String _fixedToken;
  final Duration _pollInterval;
  final http.Client _client;
  final DateTime Function() _now;

  @override
  String get backendName => 'pocketbase';

  /// Session token (set by PocketBaseAuthService at sign-in) wins over the
  /// build-time token so per-user PocketBase API rules apply to every call.
  String get _token {
    final session = OnPremSession.instance.token;
    if (session != null && session.isNotEmpty) return session;
    return _fixedToken;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token.isNotEmpty) 'Authorization': _token,
      };

  String _escape(String value) => value.replaceAll("'", r"\'");

  Uri _recordsUri(String collection,
      {String? filter, String? sort, int? limit}) {
    final params = <String, String>{
      'perPage': '${limit ?? 200}',
      if (filter != null) 'filter': filter,
      if (sort != null) 'sort': sort,
    };
    return Uri.parse('$_base/api/collections/$collection/records')
        .replace(queryParameters: params);
  }

  Future<List<AlertModel>> _fetchAlerts(
      {String? filter, int? limit, String sort = '-timestamp'}) async {
    final uri = _recordsUri('alerts', filter: filter, sort: sort, limit: limit);
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) return <AlertModel>[];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List?) ?? const [];
    return items
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((m) => AlertModel.fromMap(m['id'].toString(), m))
        .toList();
  }

  Stream<List<AlertModel>> _poll({String? filter, int? limit}) async* {
    while (true) {
      try {
        yield await _fetchAlerts(filter: filter, limit: limit);
      } catch (_) {
        yield <AlertModel>[];
      }
      await Future<void>.delayed(_pollInterval);
    }
  }

  Future<Map<String, dynamic>> _getRecord(
      String collection, String id) async {
    final uri = Uri.parse('$_base/api/collections/$collection/records/$id');
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('PocketBase GET $collection/$id failed: ${res.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<void> _patch(String alertId, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/api/collections/alerts/records/$alertId');
    final res =
        await _client.patch(uri, headers: _headers, body: jsonEncode(body));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('PocketBase PATCH $alertId failed: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>?> _post(
      String collection, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/api/collections/$collection/records');
    final res =
        await _client.post(uri, headers: _headers, body: jsonEncode(body));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('PocketBase POST $collection failed: ${res.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  // ── Streams / reads ───────────────────────────────────────────────────────

  @override
  Stream<List<AlertModel>> watchAllAlerts({int? limit}) =>
      _poll(limit: limit);

  @override
  Stream<List<AlertModel>> watchAlertsForUsine(String usine, {int? limit}) =>
      _poll(filter: "usine='${_escape(usine)}'", limit: limit);

  @override
  Stream<List<AlertModel>> watchAlertsForSupervisor(String supervisorId,
          {int? limit}) =>
      _poll(
        filter: "superviseurId='${_escape(supervisorId)}'"
            " || assistantId='${_escape(supervisorId)}'",
        limit: limit,
      );

  @override
  Future<List<AlertModel>> fetchOlderAlerts({
    String? usine,
    required DateTime before,
    int limit = 100,
  }) {
    final ts = before.toUtc().toIso8601String();
    final filters = <String>["timestamp<'${_escape(ts)}'"];
    if (usine != null) filters.add("usine='${_escape(usine)}'");
    return _fetchAlerts(filter: filters.join(' && '), limit: limit);
  }

  // ── Alert lifecycle writes ────────────────────────────────────────────────

  @override
  Future<String?> createAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    bool isCritical = false,
  }) async {
    final created = await _post('alerts', {
      'type': type,
      'usine': usine,
      'convoyeur': convoyeur,
      'poste': poste,
      'alertNumber': await _nextAlertNumber(),
      'adresse': '${usine.replaceAll(' ', '_')}_C${convoyeur}_P$poste',
      'source': 'Manual',
      'timestamp': _now().toUtc().toIso8601String(),
      'description': description.trim().isEmpty
          ? 'Alerte $type signalée manuellement'
          : description,
      'status': 'disponible',
      'comments': <String>[],
      'isCritical': isCritical,
    });
    final id = created?['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await writeAudit(
        action: 'alert.create',
        targetType: 'alert',
        targetId: id,
        factoryId: usine,
        detail: 'Created ($type)',
      );
    }
    return id;
  }

  /// Best-effort human-readable counter (max+1). The record id — not this
  /// number — is the identity key, so a rare race producing a duplicate label
  /// is cosmetic; the on-prem worker-runner's ingest path allocates the same
  /// way.
  Future<int> _nextAlertNumber() async {
    try {
      final uri = _recordsUri('alerts', sort: '-alertNumber', limit: 1);
      final res = await _client.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final items = (body['items'] as List?) ?? const [];
        if (items.isNotEmpty) {
          final top = (items.first as Map)['alertNumber'];
          if (top is num) return top.toInt() + 1;
        }
      }
    } catch (_) {/* fall through */}
    return 1;
  }

  @override
  Future<void> claimAlert(
          String alertId, String supervisorId, String supervisorName) =>
      _patch(alertId, {
        'status': 'en_cours',
        'superviseurId': supervisorId,
        'superviseurName': supervisorName,
        'takenAtTimestamp': _now().toUtc().toIso8601String(),
      });

  @override
  Future<void> resolveAlert(
    String alertId,
    String reason,
    int elapsedMinutes, {
    String? assistingSupervisorId,
    String? assistingSupervisorName,
  }) =>
      _patch(alertId, {
        'status': 'validee',
        'resolutionReason': reason,
        'elapsedTime': elapsedMinutes,
        'resolvedAt': _now().toUtc().toIso8601String(),
        if (assistingSupervisorId != null)
          'assistingSupervisorId': assistingSupervisorId,
        if (assistingSupervisorName != null)
          'assistingSupervisorName': assistingSupervisorName,
      });

  @override
  Future<void> returnAlertToQueue(String alertId, {String? reason}) =>
      _patch(alertId, {
        'status': 'disponible',
        'superviseurId': '',
        'superviseurName': '',
        'takenAtTimestamp': '',
        if (reason != null && reason.isNotEmpty) 'suspendReason': reason,
      });

  @override
  Future<void> setCritical(String alertId, bool isCritical,
          {String? note}) =>
      _patch(alertId, {
        'isCritical': isCritical,
        if (note != null) 'criticalNote': note,
      });

  @override
  Future<void> addComment(String alertId, String comment) async {
    final record = await _getRecord('alerts', alertId);
    final raw = record['comments'];
    final comments = raw is List
        ? raw.map((e) => e.toString()).toList()
        : <String>[];
    comments.add(comment);
    await _patch(alertId, {'comments': comments});
  }

  // ── Identity / audit ──────────────────────────────────────────────────────

  @override
  Future<String?> fetchUserRole(String uid) async {
    final uri = Uri.parse('$_base/api/collections/users/records/$uid');
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['role']?.toString();
  }

  @override
  Future<void> writeAudit({
    required String action,
    required String targetType,
    required String targetId,
    String? factoryId,
    String? detail,
  }) async {
    // Audit must never break the primary action.
    try {
      await _post('audit_logs', {
        'at': _now().toUtc().toIso8601String(),
        'action': action,
        'actorId': OnPremSession.instance.userId ?? 'unauthenticated',
        'actorName': OnPremSession.instance.userName ?? '',
        'targetType': targetType,
        'targetId': targetId,
        if (factoryId != null) 'factoryId': factoryId,
        if (detail != null) 'detail': detail,
      });
    } catch (_) {/* swallowed by design */}
  }
}

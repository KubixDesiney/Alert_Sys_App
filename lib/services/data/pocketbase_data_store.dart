import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/alert_model.dart';
import 'data_store.dart';

/// [DataStore] backed by a self-hosted PocketBase instance (air-gapped path).
/// Reads use lightweight polling; writes use the PocketBase REST API. Realtime
/// SSE can replace polling later without changing callers.
class PocketBaseDataStore implements DataStore {
  PocketBaseDataStore({
    required String baseUrl,
    String? token,
    Duration pollInterval = const Duration(seconds: 5),
    http.Client? client,
  })  : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _token = token ?? '',
        _pollInterval = pollInterval,
        _client = client ?? http.Client();

  final String _base;
  final String _token;
  final Duration _pollInterval;
  final http.Client _client;

  @override
  String get backendName => 'pocketbase';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token.isNotEmpty) 'Authorization': _token,
      };

  String _escape(String value) => value.replaceAll("'", r"\'");

  Future<List<AlertModel>> _fetch(String filter) async {
    final uri = Uri.parse(
      '$_base/api/collections/alerts/records?perPage=200'
      '&filter=${Uri.encodeQueryComponent(filter)}',
    );
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) return <AlertModel>[];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List?) ?? const [];
    return items
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((m) => AlertModel.fromMap(m['id'].toString(), m))
        .toList();
  }

  Stream<List<AlertModel>> _poll(String filter) async* {
    while (true) {
      try {
        yield await _fetch(filter);
      } catch (_) {
        yield <AlertModel>[];
      }
      await Future<void>.delayed(_pollInterval);
    }
  }

  Future<void> _patch(String alertId, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/api/collections/alerts/records/$alertId');
    final res = await _client.patch(uri, headers: _headers, body: jsonEncode(body));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('PocketBase PATCH $alertId failed: ${res.statusCode}');
    }
  }

  @override
  Stream<List<AlertModel>> watchAlertsForUsine(String usine, {int? limit}) =>
      _poll("usine='${_escape(usine)}'");

  @override
  Stream<List<AlertModel>> watchAlertsForSupervisor(String supervisorId, {int? limit}) =>
      _poll("superviseurId='${_escape(supervisorId)}'");

  @override
  Future<void> claimAlert(String alertId, String supervisorId, String supervisorName) =>
      _patch(alertId, {
        'status': 'en_cours',
        'superviseurId': supervisorId,
        'superviseurName': supervisorName,
        'takenAtTimestamp': DateTime.now().toUtc().toIso8601String(),
      });

  @override
  Future<void> resolveAlert(String alertId, String reason, int elapsedMinutes) =>
      _patch(alertId, {
        'status': 'validee',
        'resolutionReason': reason,
        'elapsedTime': elapsedMinutes,
        'resolvedAt': DateTime.now().toUtc().toIso8601String(),
      });

  @override
  Future<void> returnAlertToQueue(String alertId, {String? reason}) =>
      _patch(alertId, {
        'status': 'disponible',
        'superviseurId': '',
        'superviseurName': '',
        if (reason != null) 'returnReason': reason,
      });

  @override
  Future<void> setCritical(String alertId, bool isCritical) =>
      _patch(alertId, {'isCritical': isCritical});

  @override
  Future<String?> fetchUserRole(String uid) async {
    final uri = Uri.parse('$_base/api/collections/users/records/$uid');
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['role']?.toString();
  }
}

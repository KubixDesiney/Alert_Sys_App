import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'worker_auth_config.dart';

class WorkerTriggerQueue {
  WorkerTriggerQueue._();

  static final WorkerTriggerQueue instance = WorkerTriggerQueue._();

  static const String _storageKey = 'offline_worker_trigger_queue_v1';
  static const Duration _requestTimeout = Duration(seconds: 8);
  static const Duration _reconnectFlushDelay = Duration(seconds: 2);

  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  bool _started = false;
  bool _flushing = false;
  bool _connected = false;

  void start() {
    if (_started) return;
    _started = true;

    _connectionSubscription = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) {
      final connected = event.snapshot.value == true;
      _connected = connected;
      if (connected) {
        unawaited(Future<void>.delayed(_reconnectFlushDelay, flush));
      }
    }, onError: (Object error) {
      debugPrint('WorkerTriggerQueue connection listener failed: $error');
    });

    unawaited(flush());
  }

  @visibleForTesting
  Future<void> stop() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _started = false;
    _connected = false;
    _flushing = false;
  }

  Future<void> enqueueNotify() {
    return enqueuePost(Uri.parse('${WorkerAuthConfig.baseUrl}/notify'));
  }

  Future<void> enqueueAiRetry() {
    return enqueuePost(Uri.parse('${WorkerAuthConfig.baseUrl}/ai-retry'));
  }

  Future<void> enqueueAlertTrigger(String alertId) {
    return enqueuePost(
      Uri.parse(WorkerAuthConfig.baseUrl),
      headers: const {'Content-Type': 'application/json'},
      jsonBody: {'alertId': alertId},
    );
  }

  Future<void> enqueuePost(
    Uri uri, {
    Map<String, String>? headers,
    Object? jsonBody,
    String? body,
  }) async {
    if (!_started) start();

    final requestBody =
        body ?? (jsonBody == null ? null : jsonEncode(jsonBody));
    final normalizedHeaders = <String, String>{
      if (jsonBody != null) 'Content-Type': 'application/json',
      ...?headers,
    };

    final request = _QueuedWorkerRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: uri.toString(),
      headers: normalizedHeaders,
      body: requestBody,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      attempts: 0,
    );

    final queue = await _loadQueue();
    final alreadyQueued = queue.any((item) =>
        item.url == request.url &&
        item.body == request.body &&
        mapEquals(item.headers, request.headers));

    if (!alreadyQueued) {
      queue.add(request);
      await _saveQueue(queue);
    }

    unawaited(flush());
  }

  Future<void> flush() async {
    if (_flushing || (_started && !_connected)) return;
    _flushing = true;

    try {
      final queue = await _loadQueue();
      if (queue.isEmpty) return;

      final remaining = <_QueuedWorkerRequest>[];
      var networkFailed = false;

      for (final request in queue) {
        if (networkFailed) {
          remaining.add(request);
          continue;
        }

        try {
          final response = await http
              .post(
                Uri.parse(request.url),
                headers: {
                  ...request.headers,
                  ...WorkerAuthConfig.headers(),
                },
                body: request.body,
              )
              .timeout(_requestTimeout);

          if (response.statusCode >= 200 && response.statusCode < 300) {
            continue;
          }

          remaining.add(request.failed('HTTP ${response.statusCode}'));
        } catch (e) {
          networkFailed = true;
          remaining.add(request.failed(e.toString()));
        }
      }

      await _saveQueue(remaining);
    } finally {
      _flushing = false;
    }
  }

  Future<List<_QueuedWorkerRequest>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <_QueuedWorkerRequest>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <_QueuedWorkerRequest>[];
      return decoded
          .whereType<Map>()
          .map((item) =>
              _QueuedWorkerRequest.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      debugPrint('WorkerTriggerQueue could not read saved queue: $e');
      return <_QueuedWorkerRequest>[];
    }
  }

  Future<void> _saveQueue(List<_QueuedWorkerRequest> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(queue.map((request) => request.toJson()).toList()),
    );
  }
}

class _QueuedWorkerRequest {
  const _QueuedWorkerRequest({
    required this.id,
    required this.url,
    required this.headers,
    required this.body,
    required this.createdAt,
    required this.attempts,
    this.lastTriedAt,
    this.lastError,
  });

  final String id;
  final String url;
  final Map<String, String> headers;
  final String? body;
  final String createdAt;
  final int attempts;
  final String? lastTriedAt;
  final String? lastError;

  _QueuedWorkerRequest failed(String error) => _QueuedWorkerRequest(
        id: id,
        url: url,
        headers: headers,
        body: body,
        createdAt: createdAt,
        attempts: attempts + 1,
        lastTriedAt: DateTime.now().toUtc().toIso8601String(),
        lastError: error,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'headers': headers,
        'body': body,
        'createdAt': createdAt,
        'attempts': attempts,
        'lastTriedAt': lastTriedAt,
        'lastError': lastError,
      };

  factory _QueuedWorkerRequest.fromJson(Map<String, dynamic> json) {
    return _QueuedWorkerRequest(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      headers: Map<String, String>.from(json['headers'] as Map? ?? const {}),
      body: json['body']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastTriedAt: json['lastTriedAt']?.toString(),
      lastError: json['lastError']?.toString(),
    );
  }
}

import 'dart:convert';

import 'package:alertsysapp/services/worker_trigger_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkerTriggerQueue queue;
  late List<http.Request> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    queue = WorkerTriggerQueue.instance;
    await queue.resetForTesting();
    requests = <http.Request>[];
  });

  tearDown(() async {
    await queue.resetForTesting();
  });

  MockClient client() {
    return MockClient((request) async {
      requests.add(request);
      return http.Response('{"ok":true}', 200);
    });
  }

  test('deduplicates alert and notification triggers while offline', () async {
    queue.configureForTesting(httpClient: client(), connected: false);

    await queue.enqueueAlertTrigger('alert-1');
    await queue.enqueueAlertTrigger('alert-1');
    await queue.enqueueNotificationTrigger('user-1', 'notif-1');
    await queue.enqueueNotificationTrigger('user-1', 'notif-1');

    expect(await queue.pendingCountForTesting(), 2);
    expect(requests, isEmpty);

    queue.configureForTesting(httpClient: client(), connected: true);
    await queue.flush();

    expect(requests, hasLength(2));
    expect(await queue.pendingCountForTesting(), 0);

    final decodedBodies = requests
        .map((request) => jsonDecode(request.body) as Map<String, dynamic>)
        .toList();
    expect(decodedBodies.any((body) => body['alertId'] == 'alert-1'), isTrue);
    expect(
      decodedBodies.any((body) {
        final notification = body['notification'];
        return notification is Map &&
            notification['uid'] == 'user-1' &&
            notification['notifId'] == 'notif-1';
      }),
      isTrue,
    );
  });

  test('batches notification refs and flushes after reconnect', () async {
    queue.configureForTesting(httpClient: client(), connected: false);

    final refs = const [
      WorkerNotificationRef(uid: 'user-1', notifId: 'notif-1'),
      WorkerNotificationRef(uid: 'user-2', notifId: 'notif-2'),
    ];
    await queue.enqueueNotificationTriggers(refs);
    await queue.enqueueNotificationTriggers(refs);

    expect(await queue.pendingCountForTesting(), 1);
    expect(requests, isEmpty);

    queue.configureForTesting(httpClient: client(), connected: true);
    await queue.flush();

    expect(requests, hasLength(1));
    expect(await queue.pendingCountForTesting(), 0);

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['notifications'], [
      {'uid': 'user-1', 'notifId': 'notif-1'},
      {'uid': 'user-2', 'notifId': 'notif-2'},
    ]);
  });
}

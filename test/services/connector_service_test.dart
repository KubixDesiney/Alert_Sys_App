import 'package:alertsysapp/services/connector_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectorKind', () {
    test('maps wire ids used by the worker', () {
      expect(ConnectorKind.opcua.wireId, 'opcua');
      expect(ConnectorKind.historianPi.wireId, 'historian_pi');
      expect(ConnectorKind.fromWire('historian_ignition'), ConnectorKind.historianIgnition);
      expect(ConnectorKind.fromWire('mqtt'), ConnectorKind.mqtt);
    });

    test('unknown wire id falls back to custom', () {
      expect(ConnectorKind.fromWire('nope'), ConnectorKind.custom);
      expect(ConnectorKind.fromWire(null), ConnectorKind.custom);
    });

    test('mode classification matches the two ingestion paths', () {
      expect(ConnectorKind.historianPi.isPull, true);
      expect(ConnectorKind.rest.isPull, true);
      expect(ConnectorKind.opcua.isPush, true);
      expect(ConnectorKind.modbus.isPush, true);
      expect(ConnectorKind.mqtt.isMqtt, true);
    });
  });

  group('ConnectorThresholds', () {
    test('round-trips and defaults direction to high', () {
      const t = ConnectorThresholds(warn: 70, critical: 90);
      expect(t.direction, 'high');
      final m = t.toMap();
      final back = ConnectorThresholds.fromMap(m);
      expect(back.warn, 70);
      expect(back.critical, 90);
      expect(back.direction, 'high');
    });

    test('coerces numeric strings and keeps low direction', () {
      final t = ConnectorThresholds.fromMap({'warn': '5', 'critical': '3', 'direction': 'low'});
      expect(t.warn, 5);
      expect(t.critical, 3);
      expect(t.direction, 'low');
    });
  });

  group('ConnectorTag', () {
    test('round-trips with thresholds and pull metadata', () {
      const tag = ConnectorTag(
        tag: 'NS=2;S=Bearing',
        metric: 'bearing_temp',
        unit: 'C',
        valuePath: 'Value',
        thresholds: ConnectorThresholds(warn: 70, critical: 90, direction: 'high'),
      );
      final back = ConnectorTag.fromMap(tag.toMap());
      expect(back.tag, 'NS=2;S=Bearing');
      expect(back.metric, 'bearing_temp');
      expect(back.unit, 'C');
      expect(back.valuePath, 'Value');
      expect(back.thresholds.critical, 90);
    });
  });

  group('IndustrialConnector', () {
    IndustrialConnector pi() => const IndustrialConnector(
          id: 'c1',
          name: 'PI · Plant 1',
          kind: ConnectorKind.historianPi,
          factory: 'Plant 1',
          line: 'Line 2',
          station: 'S3',
          endpoint: 'https://pi/piwebapi',
          pollIntervalSec: 30,
          auth: ConnectorAuth(scheme: 'basic', username: 'svc'),
          tags: [
            ConnectorTag(tag: 'tagA', metric: 'temp', webId: 'F1abc', thresholds: ConnectorThresholds(warn: 70, critical: 90)),
          ],
        );

    test('toMap writes the worker wire shape and omits runtime', () {
      final m = pi().toMap();
      expect(m['kind'], 'historian_pi');
      expect(m['mode'], 'pull');
      expect(m['factory'], 'Plant 1');
      expect(m['pollIntervalSec'], 30);
      expect((m['tags'] as List).length, 1);
      expect(m.containsKey('runtime'), false); // worker-owned, never overwritten on save
      expect(m.containsKey('mqtt'), false); // only mqtt kinds carry an mqtt block
    });

    test('mqtt connector carries an mqtt block', () {
      const c = IndustrialConnector(
        id: 'm1',
        name: 'Broker',
        kind: ConnectorKind.mqtt,
        endpoint: 'wss://broker:8084/mqtt',
        mqttTopic: 'plant/#',
        mqttClientId: 'sia',
      );
      final m = c.toMap();
      expect(m['mqtt'], {'topic': 'plant/#', 'clientId': 'sia'});
    });

    test('fromMap reconstructs config + worker runtime', () {
      final m = pi().toMap();
      m['runtime'] = {
        'status': 'linked',
        'eventsIngested': 12,
        'lastValue': 95.4,
        'lastVerifyOk': true,
        'lastIngestAt': '2026-06-21T10:00:00.000Z',
      };
      final back = IndustrialConnector.fromMap('c1', m);
      expect(back.kind, ConnectorKind.historianPi);
      expect(back.line, 'Line 2');
      expect(back.tags.first.webId, 'F1abc');
      expect(back.runtime.status, 'linked');
      expect(back.runtime.eventsIngested, 12);
      expect(back.runtime.lastValue, 95.4);
      expect(back.runtime.lastVerifyOk, true);
    });
  });

  group('ConnectorSecret', () {
    test('toUpdate only carries non-empty fields so edits never wipe secrets', () {
      const s = ConnectorSecret(token: '  abc ', password: '', ingestKey: 'key123');
      final u = s.toUpdate();
      expect(u['token'], 'abc');
      expect(u.containsKey('password'), false);
      expect(u['ingestKey'], 'key123');
      expect(u.containsKey('updatedAt'), true);
    });

    test('hasAny is false for an all-empty bundle', () {
      expect(const ConnectorSecret().hasAny, false);
      expect(const ConnectorSecret(token: '   ').hasAny, false);
      expect(const ConnectorSecret(ingestKey: 'k').hasAny, true);
    });
  });
}

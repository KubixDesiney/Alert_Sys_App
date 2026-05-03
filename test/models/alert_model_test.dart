import 'package:alertsysapp/models/alert_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlertModel.fromMap', () {
    test('parses a minimal alert payload with sensible defaults', () {
      final m = AlertModel.fromMap('a1', {
        'type': 'qualite',
        'usine': 'Usine A',
        'convoyeur': 1,
        'poste': 2,
        'adresse': 'A-1-2',
        'description': 'Quality drift',
        'timestamp': '2026-01-01T10:00:00.000Z',
      });

      expect(m.id, 'a1');
      expect(m.alertNumber, 0);
      expect(m.type, 'qualite');
      expect(m.usine, 'Usine A');
      expect(m.convoyeur, 1);
      expect(m.poste, 2);
      expect(m.description, 'Quality drift');
      expect(m.status, 'disponible');
      expect(m.isCritical, isFalse);
      expect(m.aiAssigned, isFalse);
      expect(m.comments, isEmpty);
    });

    test('parses int and string timestamps', () {
      final ms = DateTime.utc(2026, 1, 1, 12).millisecondsSinceEpoch;

      final fromInt = AlertModel.fromMap('x', {
        'type': 'maintenance',
        'usine': 'Usine A',
        'convoyeur': 1,
        'poste': 1,
        'adresse': 'A-1-1',
        'description': '',
        'timestamp': ms,
      });
      expect(fromInt.timestamp.toUtc(), DateTime.utc(2026, 1, 1, 12));

      final fromStr = AlertModel.fromMap('y', {
        'type': 'maintenance',
        'usine': 'Usine A',
        'convoyeur': 1,
        'poste': 1,
        'adresse': 'A-1-1',
        'description': '',
        'timestamp': '2026-01-01T12:00:00.000Z',
      });
      expect(fromStr.timestamp.toUtc(), DateTime.utc(2026, 1, 1, 12));
    });

    test('handles missing fields with safe defaults', () {
      final m = AlertModel.fromMap('a2', <String, dynamic>{});
      expect(m.type, 'qualite');
      expect(m.usine, 'Usine A');
      expect(m.convoyeur, 1);
      expect(m.poste, 1);
      expect(m.description, '');
      expect(m.status, 'disponible');
      expect(m.alertNumber, 0);
    });

    test('reads asset id from any of the known aliases', () {
      final a = AlertModel.fromMap('a', {'assetId': 'M-7'});
      final b = AlertModel.fromMap('b', {'asset_id': 'M-7'});
      final c = AlertModel.fromMap('c', {'machineId': 'M-7'});
      expect(a.assetId, 'M-7');
      expect(b.assetId, 'M-7');
      expect(c.assetId, 'M-7');
    });

    test('treats blank assetId as null', () {
      final a = AlertModel.fromMap('a', {'assetId': '   '});
      expect(a.assetId, isNull);
    });

    test('parses collaborators list', () {
      final m = AlertModel.fromMap('a', {
        'collaborators': [
          {'id': 'u1', 'name': 'Alice'},
          {'id': 'u2', 'name': 'Bob'},
        ],
      });
      expect(m.collaborators, hasLength(2));
      expect(m.collaborators!.first['name'], 'Alice');
    });

    test('parses AI assignment fields', () {
      final m = AlertModel.fromMap('a', {
        'aiAssigned': true,
        'aiConfidence': 87.5,
        'aiAssignmentReason': 'closest supervisor',
      });
      expect(m.aiAssigned, isTrue);
      expect(m.aiConfidence, closeTo(87.5, 0.001));
      expect(m.aiAssignmentReason, 'closest supervisor');
    });
  });

  group('AlertModel.toMap', () {
    test('round-trips key fields through fromMap/toMap', () {
      final original = AlertModel(
        id: 'a1',
        alertNumber: 1025,
        type: 'maintenance',
        usine: 'Usine A',
        convoyeur: 3,
        poste: 7,
        adresse: 'A-3-7',
        description: 'Conveyor belt slipping',
        timestamp: DateTime.utc(2026, 5, 1, 9),
        isCritical: true,
        criticalNote: 'safety risk',
        status: 'en_cours',
        superviseurId: 'u1',
        superviseurName: 'Alice',
      );

      final map = original.toMap();
      final restored = AlertModel.fromMap('a1', map);

      expect(restored.alertNumber, 1025);
      expect(restored.type, 'maintenance');
      expect(restored.isCritical, isTrue);
      expect(restored.criticalNote, 'safety risk');
      expect(restored.status, 'en_cours');
      expect(restored.superviseurId, 'u1');
      expect(restored.superviseurName, 'Alice');
      expect(restored.timestamp.toUtc(), DateTime.utc(2026, 5, 1, 9));
    });
  });

  group('AlertModel.copyWith', () {
    AlertModel sample() => AlertModel(
          id: 'a1',
          type: 'qualite',
          usine: 'Usine A',
          convoyeur: 1,
          poste: 2,
          adresse: 'A-1-2',
          description: 'desc',
          timestamp: DateTime.utc(2026, 1, 1),
        );

    test('returns a new instance with status changed', () {
      final s = sample();
      final c = s.copyWith(status: 'en_cours');
      expect(c.status, 'en_cours');
      expect(c.id, s.id);
      expect(c.type, s.type);
    });

    test('clearSuperviseur removes supervisor fields', () {
      final s = sample()
        ..superviseurId = 'u1'
        ..superviseurName = 'Alice';
      final c = s.copyWith(clearSuperviseur: true);
      expect(c.superviseurId, isNull);
      expect(c.superviseurName, isNull);
    });

    test('clearTakenAt removes takenAtTimestamp', () {
      final s = sample()..takenAtTimestamp = DateTime.utc(2026, 1, 1);
      final c = s.copyWith(clearTakenAt: true);
      expect(c.takenAtTimestamp, isNull);
    });

    test('preserves AI fields when not overridden', () {
      final s = AlertModel(
        id: 'x',
        type: 'qualite',
        usine: 'A',
        convoyeur: 1,
        poste: 1,
        adresse: 'a',
        description: '',
        timestamp: DateTime.utc(2026),
        aiAssigned: true,
        aiConfidence: 90,
        aiAssignmentReason: 'reason',
      );
      final c = s.copyWith(status: 'en_cours');
      expect(c.aiAssigned, isTrue);
      expect(c.aiConfidence, 90);
      expect(c.aiAssignmentReason, 'reason');
    });

    test('overrides isCritical and criticalNote independently', () {
      final s = sample();
      final c = s.copyWith(isCritical: true, criticalNote: 'urgent');
      expect(c.isCritical, isTrue);
      expect(c.criticalNote, 'urgent');
    });
  });
}

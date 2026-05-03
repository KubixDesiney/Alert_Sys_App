import 'package:alertsysapp/models/collaboration_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CollaborationRequest', () {
    test('fromMap parses required fields', () {
      final r = CollaborationRequest.fromMap('c1', {
        'alertId': 'a1',
        'requesterId': 'u1',
        'requesterName': 'Alice',
        'targetSupervisorIds': ['u2', 'u3'],
        'targetSupervisorNames': ['Bob', 'Carol'],
        'message': 'help',
        'status': 'pending',
        'timestamp': '2026-05-01T10:00:00.000Z',
      });
      expect(r.id, 'c1');
      expect(r.alertId, 'a1');
      expect(r.requesterId, 'u1');
      expect(r.targetSupervisorIds, ['u2', 'u3']);
      expect(r.targetSupervisorNames, ['Bob', 'Carol']);
      expect(r.status, 'pending');
      expect(r.assistantDecision, 'pending');
      expect(r.assistantDecisions, isEmpty);
    });

    test('parses assistantDecisions map', () {
      final r = CollaborationRequest.fromMap('c1', {
        'timestamp': '2026-05-01T10:00:00.000Z',
        'assistantDecisions': {
          'u2': 'accepted',
          'u3': 'refused',
        },
      });
      expect(r.assistantDecisions['u2'], 'accepted');
      expect(r.assistantDecisions['u3'], 'refused');
    });

    test('toMap and fromMap round-trip', () {
      final original = CollaborationRequest(
        id: 'c1',
        alertId: 'a1',
        requesterId: 'u1',
        requesterName: 'Alice',
        targetSupervisorIds: ['u2'],
        targetSupervisorNames: ['Bob'],
        message: 'help',
        status: 'approved',
        timestamp: DateTime.utc(2026, 5, 1, 10),
        approvedBy: 'pm1',
        approvedAt: DateTime.utc(2026, 5, 1, 10, 5),
      );
      final restored =
          CollaborationRequest.fromMap('c1', original.toMap());
      expect(restored.status, 'approved');
      expect(restored.approvedBy, 'pm1');
      expect(restored.approvedAt?.toUtc(), DateTime.utc(2026, 5, 1, 10, 5));
    });
  });

  group('EscalationSettings', () {
    test('defaultSettings has all four alert types', () {
      final s = EscalationSettings.defaultSettings();
      expect(s.thresholds.keys, containsAll([
        'qualite',
        'maintenance',
        'defaut_produit',
        'manque_ressource',
      ]));
    });

    test('round-trips through toMap/fromMap', () {
      final original = EscalationSettings.defaultSettings();
      final restored = EscalationSettings.fromMap(original.toMap());
      expect(restored.thresholds.length, original.thresholds.length);
      expect(restored.thresholds['qualite']?.unclaimedMinutes,
          original.thresholds['qualite']?.unclaimedMinutes);
    });
  });

  group('EscalationThreshold', () {
    test('copyWith updates only requested fields', () {
      final t = EscalationThreshold(
        type: 'qualite',
        unclaimedMinutes: 10,
        claimedMinutes: 30,
      );
      final updated = t.copyWith(unclaimedMinutes: 5);
      expect(updated.unclaimedMinutes, 5);
      expect(updated.claimedMinutes, 30);
      expect(updated.type, 'qualite');
    });

    test('fromMap handles missing fields with zero defaults', () {
      final t = EscalationThreshold.fromMap(<String, dynamic>{});
      expect(t.type, '');
      expect(t.unclaimedMinutes, 0);
      expect(t.claimedMinutes, 0);
    });
  });
}

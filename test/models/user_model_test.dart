import 'package:alertsysapp/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserModel', () {
    test('fromMap parses all fields', () {
      final u = UserModel.fromMap('u1', {
        'firstName': 'Alice',
        'lastName': 'Smith',
        'email': 'alice@example.com',
        'phone': '+1-555-0100',
        'role': 'admin',
        'usine': 'Usine A',
        'status': 'active',
        'hiredDate': '2024-01-15T00:00:00.000Z',
        'lastSeen': '2026-05-01T08:00:00.000Z',
      });

      expect(u.id, 'u1');
      expect(u.firstName, 'Alice');
      expect(u.lastName, 'Smith');
      expect(u.email, 'alice@example.com');
      expect(u.role, 'admin');
      expect(u.usine, 'Usine A');
      expect(u.status, 'active');
      expect(u.fullName, 'Alice Smith');
      expect(u.isAdmin, isTrue);
      expect(u.isActive, isTrue);
      expect(u.hiredDate?.toUtc().year, 2024);
      expect(u.lastSeen?.toUtc().year, 2026);
    });

    test('fromMap fills sane defaults for missing fields', () {
      final u = UserModel.fromMap('u2', <String, dynamic>{});
      expect(u.firstName, '');
      expect(u.lastName, '');
      expect(u.email, '');
      expect(u.phone, '');
      expect(u.role, 'supervisor');
      expect(u.usine, 'Usine A');
      expect(u.status, 'absent');
      expect(u.isAdmin, isFalse);
      expect(u.isActive, isFalse);
    });

    test('fullName joins names with a space even when one is empty', () {
      final u = UserModel(
        id: 'u',
        firstName: 'Alice',
        lastName: '',
        email: '',
        phone: '',
        role: 'supervisor',
        usine: '',
      );
      expect(u.fullName, 'Alice ');
    });

    test('isAdmin is exact match on role', () {
      final supervisor = UserModel(
        id: 'u',
        firstName: '',
        lastName: '',
        email: '',
        phone: '',
        role: 'supervisor',
        usine: '',
      );
      expect(supervisor.isAdmin, isFalse);
    });

    test('toMap serializes round-trip-safe payload', () {
      final u = UserModel(
        id: 'u',
        firstName: 'A',
        lastName: 'B',
        email: 'a@b.com',
        phone: '1',
        role: 'admin',
        usine: 'Usine A',
        status: 'active',
        hiredDate: DateTime.utc(2024),
      );
      final map = u.toMap();
      final round = UserModel.fromMap(u.id, map);
      expect(round.firstName, 'A');
      expect(round.role, 'admin');
      expect(round.hiredDate?.toUtc().year, 2024);
    });

    test('handles malformed dates gracefully', () {
      final u = UserModel.fromMap('u', {'hiredDate': 'not-a-date'});
      expect(u.hiredDate, isNull);
    });
  });
}

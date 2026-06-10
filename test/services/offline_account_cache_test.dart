import 'package:alertsysapp/services/offline_account_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OfflineAccountCache.isValidRole', () {
    test('accepts admin, supervisor and superadmin', () {
      expect(OfflineAccountCache.isValidRole('admin'), isTrue);
      expect(OfflineAccountCache.isValidRole('supervisor'), isTrue);
      expect(OfflineAccountCache.isValidRole('superadmin'), isTrue);
    });

    test('normalizes case so console-typed roles like SuperAdmin work', () {
      expect(OfflineAccountCache.isValidRole('SuperAdmin'), isTrue);
      expect(OfflineAccountCache.normalizeRole('SuperAdmin'), 'superadmin');
      expect(OfflineAccountCache.normalizeRole('Admin'), 'admin');
    });

    test('rejects null, empty, and unknown roles', () {
      expect(OfflineAccountCache.isValidRole(null), isFalse);
      expect(OfflineAccountCache.isValidRole(''), isFalse);
      expect(OfflineAccountCache.isValidRole('operator'), isFalse);
      expect(OfflineAccountCache.normalizeRole('operator'), isNull);
    });
  });

  group('OfflineAccountCache.save / read', () {
    test('persists a valid role and reads it back', () async {
      await OfflineAccountCache.save(uid: 'u1', role: 'admin');
      final role = await OfflineAccountCache.roleFor('u1');
      expect(role, 'admin');
    });

    test('does not persist invalid roles', () async {
      await OfflineAccountCache.save(uid: 'u1', role: 'operator');
      final role = await OfflineAccountCache.roleFor('u1');
      expect(role, isNull);
    });

    test('persists usine and trims whitespace', () async {
      await OfflineAccountCache.save(uid: 'u1', usine: '  Usine A  ');
      final usine = await OfflineAccountCache.usineFor('u1');
      expect(usine, 'Usine A');
    });

    test('does not persist blank usine', () async {
      await OfflineAccountCache.save(uid: 'u1', usine: '   ');
      final usine = await OfflineAccountCache.usineFor('u1');
      expect(usine, isNull);
    });

    test('returns null for unknown uid', () async {
      final role = await OfflineAccountCache.roleFor('does-not-exist');
      final usine = await OfflineAccountCache.usineFor('does-not-exist');
      expect(role, isNull);
      expect(usine, isNull);
    });

    test('keeps role and usine cache per-uid (no cross-contamination)',
        () async {
      await OfflineAccountCache.save(
          uid: 'u1', role: 'admin', usine: 'Usine A');
      await OfflineAccountCache.save(
          uid: 'u2', role: 'supervisor', usine: 'Usine B');
      expect(await OfflineAccountCache.roleFor('u1'), 'admin');
      expect(await OfflineAccountCache.roleFor('u2'), 'supervisor');
      expect(await OfflineAccountCache.usineFor('u1'), 'Usine A');
      expect(await OfflineAccountCache.usineFor('u2'), 'Usine B');
    });

    test('persists SuperAdmin in canonical lowercase form', () async {
      await OfflineAccountCache.save(uid: 'u3', role: 'SuperAdmin');
      expect(await OfflineAccountCache.roleFor('u3'), 'superadmin');
    });
  });
}

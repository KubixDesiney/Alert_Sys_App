import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';
import 'audit_service.dart';

/// Account administration for the SuperAdmin console.
///
/// Production Manager accounts are created through a secondary Firebase app
/// instance so the SuperAdmin's own session is never replaced by the freshly
/// created user (createUserWithEmailAndPassword signs in the new account on
/// whichever auth instance runs it).
class SuperAdminService {
  final DatabaseReference _db;

  SuperAdminService({DatabaseReference? database})
      : _db = database ?? FirebaseDatabase.instance.ref();

  /// Streams every Production Manager (role == admin) account.
  Stream<List<Map<String, dynamic>>> productionManagersStream() {
    return _db
        .child('users')
        .orderByChild('role')
        .equalTo('admin')
        .onValue
        .asyncMap((event) async {
      final value = event.snapshot.value;
      if (value is! Map) return <Map<String, dynamic>>[];
      // Merge access-scoped PII (email/phone) from users_private. SuperAdmin is
      // authorized to read it; a failure degrades to name-only entries.
      Map private = const {};
      try {
        final ps = await _db.child('users_private').get();
        if (ps.value is Map) private = ps.value as Map;
      } catch (_) {}
      final list = value.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['uid'] = e.key.toString();
        final p = private[e.key];
        if (p is Map) {
          if (p['email'] != null) m['email'] = p['email'];
          if (p['phone'] != null) m['phone'] = p['phone'];
        }
        return m;
      }).toList()
        ..sort((a, b) => (a['fullName'] ?? a['email'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo(
                (b['fullName'] ?? b['email'] ?? '').toString().toLowerCase()));
      return list;
    });
  }

  /// Creates a Production Manager account. Returns null on success or an
  /// error message.
  Future<String?> createProductionManager({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    String? usine,
  }) async {
    FirebaseApp? secondary;
    try {
      secondary = await Firebase.initializeApp(
        name: 'superadmin_worker',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException {
      secondary = Firebase.app('superadmin_worker');
    }
    try {
      final auth = FirebaseAuth.instanceFor(app: secondary);
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;
      await auth.signOut();

      // The users/{uid} record is written with the SuperAdmin's own session,
      // which database rules authorize explicitly.
      await _db.child('users/$uid').set({
        'firstName': firstName,
        'lastName': lastName,
        'fullName': '$firstName $lastName',
        'role': 'admin',
        if (usine != null && usine.isNotEmpty) 'usine': usine,
        'status': 'active',
        'createdAt': DateTime.now().toIso8601String(),
        'createdBy': 'superadmin',
      });
      // Sensitive PII lives in the access-scoped users_private node.
      await _db.child('users_private/$uid').set({
        'email': email,
        'phone': phone,
      });
      await AuditService.instance.log(
        action: AuditAction.accountProvision,
        targetType: 'user',
        targetId: uid,
        factoryId: usine,
        detail: 'Provisioned Production Manager $email',
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  /// Removes the database record (the Auth account remains but loses all
  /// role-based access, matching how supervisor removal works today).
  Future<void> deleteProductionManager(String uid) async {
    await _db.child('users/$uid').remove();
    await AuditService.instance.log(
      action: AuditAction.accountRevoke,
      targetType: 'user',
      targetId: uid,
      detail: 'Revoked Production Manager access',
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    await AuditService.instance.log(
      action: AuditAction.passwordReset,
      targetType: 'user',
      detail: 'Sent password reset to $email',
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';

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
        .map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <Map<String, dynamic>>[];
      final list = value.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['uid'] = e.key.toString();
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
        'email': email,
        'phone': phone,
        'role': 'admin',
        if (usine != null && usine.isNotEmpty) 'usine': usine,
        'status': 'active',
        'createdAt': DateTime.now().toIso8601String(),
        'createdBy': 'superadmin',
      });
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
  }

  Future<void> sendPasswordReset(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class UserService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref('users');
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String?> getUserRole(String uid) async {
    final snapshot = await _db.child(uid).child('role').get();
    return snapshot.value as String?;
  }

  Future<void> setUserRole(String uid, String role) async {
    await _db.child(uid).update({'role': role});
  }

  Future<List<Map<String, dynamic>>> getAllSupervisors() async {
    final snapshot = await _db.orderByChild('role').equalTo('supervisor').get();
    if (!snapshot.exists) return [];
    final data = Map<String, dynamic>.from(snapshot.value as Map);
    return data.entries.map((e) => {
      'uid': e.key,
      ...Map<String, dynamic>.from(e.value),
    }).toList();
  }

  Future<void> removeSupervisor(String uid) async {
    // Remove from Realtime Database only (Auth account remains but without role)
    await _db.child(uid).remove();
  }

  // Add logout method
  Future<void> logout() async {
    await _auth.signOut();
  }
}
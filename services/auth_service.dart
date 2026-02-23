import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get currently logged in user
  User? get currentUser => _auth.currentUser;

  // Stream that listens for login/logout changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Login with email and password
  Future<String?> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null; // null means success
    } on FirebaseAuthException catch (e) {
      // Return a readable error message
      if (e.code == 'user-not-found') return 'Utilisateur introuvable.';
      if (e.code == 'wrong-password') return 'Mot de passe incorrect.';
      return 'Erreur de connexion.';
    }
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }
}
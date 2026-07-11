/// Identity of the signed-in user when the app runs against an on-prem
/// backend (PocketBase). Firebase mode keeps using FirebaseAuth directly —
/// this exists so the alert lifecycle can resolve "who am I" without touching
/// Firebase when `SIAS_BACKEND=pocketbase`.
///
/// Populated by [PocketBaseAuthService] on sign-in and cleared on sign-out.
class OnPremSession {
  OnPremSession._();

  static final OnPremSession instance = OnPremSession._();

  String? userId;
  String? userName;
  String? role;
  String? token;
  DateTime? tokenExpiresAt;

  bool get isSignedIn =>
      userId != null &&
      userId!.isNotEmpty &&
      (tokenExpiresAt == null || DateTime.now().isBefore(tokenExpiresAt!));

  void update({
    required String userId,
    required String userName,
    required String role,
    required String token,
    DateTime? tokenExpiresAt,
  }) {
    this.userId = userId;
    this.userName = userName;
    this.role = role;
    this.token = token;
    this.tokenExpiresAt = tokenExpiresAt;
  }

  void clear() {
    userId = null;
    userName = null;
    role = null;
    token = null;
    tokenExpiresAt = null;
  }
}

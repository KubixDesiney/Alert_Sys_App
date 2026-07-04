class UserModel {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String role;
  final String usine;
  final String status;
  final DateTime? hiredDate;
  final DateTime? lastSeen;

  UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.role,
    required this.usine,
    this.status = 'absent',
    this.hiredDate,
    this.lastSeen,
  });

  String get fullName => '$firstName $lastName';
  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';

  factory UserModel.fromMap(String id, Map<String, dynamic> d) {
    return UserModel(
      id: id,
      firstName: d['firstName']?.toString() ?? '',
      lastName: d['lastName']?.toString() ?? '',
      email: d['email']?.toString() ?? '',
      phone: d['phone']?.toString() ?? '',
      role: d['role']?.toString() ?? 'supervisor',
      usine: d['usine']?.toString() ?? 'Usine A',
      status: d['status']?.toString() ?? 'absent',
      hiredDate: d['hiredDate'] != null ? DateTime.tryParse(d['hiredDate'].toString()) : null,
      lastSeen: d['lastSeen'] != null ? DateTime.tryParse(d['lastSeen'].toString()) : null,
    );
  }

  /// Serializes the broadly-readable `users/*` record. Deliberately excludes
  /// `email` and `phone`: PII lives only in the access-scoped `users_private`
  /// node (enforced by database rules) — use [toPrivateMap] for that write.
  Map<String, dynamic> toMap() => {
    'firstName': firstName,
    'lastName': lastName,
    'role': role,
    'usine': usine,
    'status': status,
    'hiredDate': hiredDate?.toIso8601String(),
    'lastSeen': lastSeen?.toIso8601String(),
  };

  /// The access-scoped PII payload for `users_private/{uid}`.
  Map<String, dynamic> toPrivateMap() => {
    'email': email,
    'phone': phone,
  };
}

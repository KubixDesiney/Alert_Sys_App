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

  Map<String, dynamic> toMap() => {
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phone': phone,
    'role': role,
    'usine': usine,
    'status': status,
    'hiredDate': hiredDate?.toIso8601String(),
    'lastSeen': lastSeen?.toIso8601String(),
  };
}

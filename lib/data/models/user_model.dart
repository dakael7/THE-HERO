class UserModel {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? rut;
  final String? phone;
  final String role;
  final String? createdAt;

  UserModel({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.rut,
    this.phone,
    required this.role,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      rut: json['rut'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String,
      createdAt: json['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'rut': rut,
      'phone': phone,
      'role': role,
      'createdAt': createdAt,
    };
  }
}

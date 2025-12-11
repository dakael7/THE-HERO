class User {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? rut;
  final String? phone;
  final UserRole role;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.rut,
    this.phone,
    required this.role,
    this.createdAt,
  });

  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return firstName ?? lastName ?? email;
  }

  bool get isHero => role == UserRole.hero;
  bool get isRider => role == UserRole.rider;
}

enum UserRole { hero, rider }

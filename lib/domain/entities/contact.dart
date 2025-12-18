/// Entidad que representa la información de contacto de un usuario
class Contact {
  final String email;
  final String phoneNumber;
  final bool emailVerified;

  Contact({
    required this.email,
    required this.phoneNumber,
    this.emailVerified = false,
  });

  Contact copyWith({
    String? email,
    String? phoneNumber,
    bool? emailVerified,
  }) {
    return Contact(
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }
}

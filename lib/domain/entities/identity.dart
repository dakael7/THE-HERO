/// Entidad que representa la identidad de un usuario
class Identity {
  final String firstName;
  final String lastName;
  final String documentId; 

  Identity({
    required this.firstName,
    required this.lastName,
    required this.documentId,
  });

  String get fullName => '$firstName $lastName';

  Identity copyWith({
    String? firstName,
    String? lastName,
    String? documentId,
  }) {
    return Identity(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      documentId: documentId ?? this.documentId,
    );
  }
}

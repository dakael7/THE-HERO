class Identity {
  final String firstName;
  final String lastName;
  final String documentType;
  final String documentId; 

  Identity({
    required this.firstName,
    required this.lastName,
    this.documentType = 'rut',
    required this.documentId,
  });

  String get fullName => '$firstName $lastName';

  Identity copyWith({
    String? firstName,
    String? lastName,
    String? documentType,
    String? documentId,
  }) {
    return Identity(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      documentType: documentType ?? this.documentType,
      documentId: documentId ?? this.documentId,
    );
  }
}

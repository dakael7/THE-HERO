import '../../domain/entities/identity.dart';

class IdentityModel {
  final String firstName;
  final String lastName;
  final String documentType;
  final String documentId;

  IdentityModel({
    required this.firstName,
    required this.lastName,
    this.documentType = 'rut',
    required this.documentId,
  });

  factory IdentityModel.fromJson(Map<String, dynamic> json) {
    return IdentityModel(
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      documentType: json['documentType'] as String? ?? 'rut',
      documentId: json['documentId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'documentType': documentType,
      'documentId': documentId,
    };
  }

  Identity toEntity() {
    return Identity(
      firstName: firstName,
      lastName: lastName,
      documentType: documentType,
      documentId: documentId,
    );
  }

  factory IdentityModel.fromEntity(Identity entity) {
    return IdentityModel(
      firstName: entity.firstName,
      lastName: entity.lastName,
      documentType: entity.documentType,
      documentId: entity.documentId,
    );
  }
}

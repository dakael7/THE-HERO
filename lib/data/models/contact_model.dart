import '../../domain/entities/contact.dart';

class ContactModel {
  final String email;
  final String phoneNumber;
  final bool emailVerified;

  ContactModel({
    required this.email,
    required this.phoneNumber,
    this.emailVerified = false,
  });

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      email: json['email'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      emailVerified: json['emailVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'phoneNumber': phoneNumber,
      'emailVerified': emailVerified,
    };
  }

  Contact toEntity() {
    return Contact(
      email: email,
      phoneNumber: phoneNumber,
      emailVerified: emailVerified,
    );
  }

  factory ContactModel.fromEntity(Contact entity) {
    return ContactModel(
      email: entity.email,
      phoneNumber: entity.phoneNumber,
      emailVerified: entity.emailVerified,
    );
  }
}

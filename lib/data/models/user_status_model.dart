import '../../domain/entities/user_status.dart';

class UserStatusModel {
  final bool termsAccepted;
  final String createdAt;
  final String lastUpdated;

  UserStatusModel({
    required this.termsAccepted,
    required this.createdAt,
    required this.lastUpdated,
  });

  factory UserStatusModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toIso8601String();
    return UserStatusModel(
      termsAccepted: json['termsAccepted'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? now,
      lastUpdated: json['lastUpdated'] as String? ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'termsAccepted': termsAccepted,
      'createdAt': createdAt,
      'lastUpdated': lastUpdated,
    };
  }

  UserStatus toEntity() {
    return UserStatus(
      termsAccepted: termsAccepted,
      createdAt: DateTime.parse(createdAt),
      lastUpdated: DateTime.parse(lastUpdated),
    );
  }

  factory UserStatusModel.fromEntity(UserStatus entity) {
    return UserStatusModel(
      termsAccepted: entity.termsAccepted,
      createdAt: entity.createdAt.toIso8601String(),
      lastUpdated: entity.lastUpdated.toIso8601String(),
    );
  }
}

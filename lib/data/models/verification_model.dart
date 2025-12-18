import '../../domain/entities/verification.dart';

class VerificationModel {
  final String apiRefId;
  final String lastCheck;

  VerificationModel({
    required this.apiRefId,
    required this.lastCheck,
  });

  factory VerificationModel.fromJson(Map<String, dynamic> json) {
    return VerificationModel(
      apiRefId: json['apiRefId'] as String? ?? '',
      lastCheck: json['lastCheck'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiRefId': apiRefId,
      'lastCheck': lastCheck,
    };
  }

  Verification toEntity() {
    return Verification(
      apiRefId: apiRefId,
      lastCheck: DateTime.parse(lastCheck),
    );
  }

  factory VerificationModel.fromEntity(Verification entity) {
    return VerificationModel(
      apiRefId: entity.apiRefId,
      lastCheck: entity.lastCheck.toIso8601String(),
    );
  }
}

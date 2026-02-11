import '../../domain/entities/payment_preference.dart';

/// Model for PaymentPreference entity with JSON serialization
class PaymentPreferenceModel {
  final String preferenceId;
  final String initPoint;
  final String sandboxInitPoint;
  final String orderId;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const PaymentPreferenceModel({
    required this.preferenceId,
    required this.initPoint,
    required this.sandboxInitPoint,
    required this.orderId,
    required this.createdAt,
    this.expiresAt,
  });

  /// Convert from domain entity
  factory PaymentPreferenceModel.fromEntity(PaymentPreference preference) {
    return PaymentPreferenceModel(
      preferenceId: preference.preferenceId,
      initPoint: preference.initPoint,
      sandboxInitPoint: preference.sandboxInitPoint,
      orderId: preference.orderId,
      createdAt: preference.createdAt,
      expiresAt: preference.expiresAt,
    );
  }

  /// Convert to domain entity
  PaymentPreference toEntity() {
    return PaymentPreference(
      preferenceId: preferenceId,
      initPoint: initPoint,
      sandboxInitPoint: sandboxInitPoint,
      orderId: orderId,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  /// Convert from JSON (Firebase Functions response)
  factory PaymentPreferenceModel.fromJson(Map<String, dynamic> json) {
    return PaymentPreferenceModel(
      preferenceId: json['preferenceId'] as String? ?? json['id'] as String,
      initPoint: json['initPoint'] as String? ?? json['init_point'] as String,
      sandboxInitPoint:
          json['sandboxInitPoint'] as String? ??
          json['sandbox_init_point'] as String,
      orderId: json['orderId'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'preferenceId': preferenceId,
      'initPoint': initPoint,
      'sandboxInitPoint': sandboxInitPoint,
      'orderId': orderId,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }
}

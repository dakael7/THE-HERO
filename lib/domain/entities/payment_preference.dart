/// Represents a MercadoPago payment preference
/// This is created before redirecting the user to the payment page
class PaymentPreference {
  final String preferenceId;
  final String initPoint; // URL to redirect user for payment
  final String sandboxInitPoint; // URL for sandbox/test environment
  final String orderId;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const PaymentPreference({
    required this.preferenceId,
    required this.initPoint,
    required this.sandboxInitPoint,
    required this.orderId,
    required this.createdAt,
    this.expiresAt,
  });

  PaymentPreference copyWith({
    String? preferenceId,
    String? initPoint,
    String? sandboxInitPoint,
    String? orderId,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return PaymentPreference(
      preferenceId: preferenceId ?? this.preferenceId,
      initPoint: initPoint ?? this.initPoint,
      sandboxInitPoint: sandboxInitPoint ?? this.sandboxInitPoint,
      orderId: orderId ?? this.orderId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }
}

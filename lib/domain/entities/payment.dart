/// Represents a payment transaction in the system
class Payment {
  final String id;
  final String orderId;
  final String preferenceId;
  final String? paymentId; // MercadoPago payment ID
  final PaymentStatus status;
  final double amount;
  final String currency;
  final PaymentMethod? paymentMethod;
  final String? paymentMethodId; // e.g., "visa", "master", etc.
  final String? statusDetail; // Detailed status from MercadoPago
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? metadata; // Additional payment info

  const Payment({
    required this.id,
    required this.orderId,
    required this.preferenceId,
    this.paymentId,
    required this.status,
    required this.amount,
    required this.currency,
    this.paymentMethod,
    this.paymentMethodId,
    this.statusDetail,
    required this.createdAt,
    this.approvedAt,
    this.updatedAt,
    this.metadata,
  });

  Payment copyWith({
    String? id,
    String? orderId,
    String? preferenceId,
    String? paymentId,
    PaymentStatus? status,
    double? amount,
    String? currency,
    PaymentMethod? paymentMethod,
    String? paymentMethodId,
    String? statusDetail,
    DateTime? createdAt,
    DateTime? approvedAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return Payment(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      preferenceId: preferenceId ?? this.preferenceId,
      paymentId: paymentId ?? this.paymentId,
      status: status ?? this.status,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      statusDetail: statusDetail ?? this.statusDetail,
      createdAt: createdAt ?? this.createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isApproved => status == PaymentStatus.approved;
  bool get isPending =>
      status == PaymentStatus.pending || status == PaymentStatus.inProcess;
  bool get isRejected => status == PaymentStatus.rejected;
  bool get isCancelled => status == PaymentStatus.cancelled;
}

/// Payment status enum matching MercadoPago statuses
enum PaymentStatus {
  pending, // Payment is pending
  approved, // Payment was approved
  authorized, // Payment was authorized but not captured
  inProcess, // Payment is being processed
  inMediation, // Payment is in dispute
  rejected, // Payment was rejected
  cancelled, // Payment was cancelled
  refunded, // Payment was refunded
  chargedBack, // Payment was charged back
}

/// Payment method types
enum PaymentMethod {
  creditCard,
  debitCard,
  mercadoPago,
  bankTransfer,
  cash,
  pix,
  other,
}

// Extension to convert string to PaymentStatus
extension PaymentStatusExtension on PaymentStatus {
  String toMercadoPagoString() {
    switch (this) {
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.approved:
        return 'approved';
      case PaymentStatus.authorized:
        return 'authorized';
      case PaymentStatus.inProcess:
        return 'in_process';
      case PaymentStatus.inMediation:
        return 'in_mediation';
      case PaymentStatus.rejected:
        return 'rejected';
      case PaymentStatus.cancelled:
        return 'cancelled';
      case PaymentStatus.refunded:
        return 'refunded';
      case PaymentStatus.chargedBack:
        return 'charged_back';
    }
  }

  static PaymentStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return PaymentStatus.pending;
      case 'approved':
        return PaymentStatus.approved;
      case 'authorized':
        return PaymentStatus.authorized;
      case 'in_process':
        return PaymentStatus.inProcess;
      case 'in_mediation':
        return PaymentStatus.inMediation;
      case 'rejected':
        return PaymentStatus.rejected;
      case 'cancelled':
        return PaymentStatus.cancelled;
      case 'refunded':
        return PaymentStatus.refunded;
      case 'charged_back':
        return PaymentStatus.chargedBack;
      default:
        return PaymentStatus.pending;
    }
  }
}

// Extension to convert string to PaymentMethod
extension PaymentMethodExtension on PaymentMethod {
  String toMercadoPagoString() {
    switch (this) {
      case PaymentMethod.creditCard:
        return 'credit_card';
      case PaymentMethod.debitCard:
        return 'debit_card';
      case PaymentMethod.mercadoPago:
        return 'account_money';
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
      case PaymentMethod.cash:
        return 'ticket';
      case PaymentMethod.pix:
        return 'pix';
      case PaymentMethod.other:
        return 'other';
    }
  }

  static PaymentMethod fromString(String method) {
    switch (method.toLowerCase()) {
      case 'credit_card':
        return PaymentMethod.creditCard;
      case 'debit_card':
        return PaymentMethod.debitCard;
      case 'account_money':
        return PaymentMethod.mercadoPago;
      case 'bank_transfer':
        return PaymentMethod.bankTransfer;
      case 'ticket':
        return PaymentMethod.cash;
      case 'pix':
        return PaymentMethod.pix;
      default:
        return PaymentMethod.other;
    }
  }
}

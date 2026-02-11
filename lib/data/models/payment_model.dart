import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/payment.dart';

/// Model for Payment entity with Firestore serialization
class PaymentModel {
  final String id;
  final String orderId;
  final String preferenceId;
  final String? paymentId;
  final PaymentStatus status;
  final double amount;
  final String currency;
  final PaymentMethod? paymentMethod;
  final String? paymentMethodId;
  final String? statusDetail;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? metadata;

  const PaymentModel({
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

  /// Convert from domain entity
  factory PaymentModel.fromEntity(Payment payment) {
    return PaymentModel(
      id: payment.id,
      orderId: payment.orderId,
      preferenceId: payment.preferenceId,
      paymentId: payment.paymentId,
      status: payment.status,
      amount: payment.amount,
      currency: payment.currency,
      paymentMethod: payment.paymentMethod,
      paymentMethodId: payment.paymentMethodId,
      statusDetail: payment.statusDetail,
      createdAt: payment.createdAt,
      approvedAt: payment.approvedAt,
      updatedAt: payment.updatedAt,
      metadata: payment.metadata,
    );
  }

  /// Convert to domain entity
  Payment toEntity() {
    return Payment(
      id: id,
      orderId: orderId,
      preferenceId: preferenceId,
      paymentId: paymentId,
      status: status,
      amount: amount,
      currency: currency,
      paymentMethod: paymentMethod,
      paymentMethodId: paymentMethodId,
      statusDetail: statusDetail,
      createdAt: createdAt,
      approvedAt: approvedAt,
      updatedAt: updatedAt,
      metadata: metadata,
    );
  }

  /// Convert from Firestore document
  factory PaymentModel.fromFirestore(Map<String, dynamic> data, String id) {
    return PaymentModel(
      id: id,
      orderId: data['orderId'] as String,
      preferenceId: data['preferenceId'] as String,
      paymentId: data['paymentId'] as String?,
      status: PaymentStatusExtension.fromString(data['status'] as String),
      amount: (data['amount'] as num).toDouble(),
      currency: data['currency'] as String? ?? 'CLP',
      paymentMethod: data['paymentMethod'] != null
          ? PaymentMethodExtension.fromString(data['paymentMethod'] as String)
          : null,
      paymentMethodId: data['paymentMethodId'] as String?,
      statusDetail: data['statusDetail'] as String?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      approvedAt: data['approvedAt'] != null
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'orderId': orderId,
      'preferenceId': preferenceId,
      'paymentId': paymentId,
      'status': status.toMercadoPagoString(),
      'amount': amount,
      'currency': currency,
      'paymentMethod': paymentMethod?.toMercadoPagoString(),
      'paymentMethodId': paymentMethodId,
      'statusDetail': statusDetail,
      'createdAt': Timestamp.fromDate(createdAt),
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
      'metadata': metadata,
    };
  }

  /// Convert from JSON (for API responses)
  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] as String,
      orderId: json['orderId'] as String,
      preferenceId: json['preferenceId'] as String,
      paymentId: json['paymentId'] as String?,
      status: PaymentStatusExtension.fromString(json['status'] as String),
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'CLP',
      paymentMethod: json['paymentMethod'] != null
          ? PaymentMethodExtension.fromString(json['paymentMethod'] as String)
          : null,
      paymentMethodId: json['paymentMethodId'] as String?,
      statusDetail: json['statusDetail'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      approvedAt: json['approvedAt'] != null
          ? DateTime.parse(json['approvedAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'preferenceId': preferenceId,
      'paymentId': paymentId,
      'status': status.toMercadoPagoString(),
      'amount': amount,
      'currency': currency,
      'paymentMethod': paymentMethod?.toMercadoPagoString(),
      'paymentMethodId': paymentMethodId,
      'statusDetail': statusDetail,
      'createdAt': createdAt.toIso8601String(),
      'approvedAt': approvedAt?.toIso8601String(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      'metadata': metadata,
    };
  }
}

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
    final orderId = data['orderId']?.toString() ?? '';
    final preferenceId = (data['preferenceId']?.toString().trim().isNotEmpty ?? false)
        ? data['preferenceId']!.toString().trim()
        : id;

    final statusRaw = data['status']?.toString();
    final status = statusRaw != null && statusRaw.isNotEmpty
        ? PaymentStatusExtension.fromString(statusRaw)
        : PaymentStatus.pending;

    final amountNum = data['amount'];
    final amount = amountNum is num ? amountNum.toDouble() : 0.0;

    final createdAtRaw = data['createdAt'];
    final createdAt = createdAtRaw is Timestamp
        ? createdAtRaw.toDate()
        : DateTime.now();

    return PaymentModel(
      id: id,
      orderId: orderId,
      preferenceId: preferenceId,
      paymentId: data['paymentId']?.toString(),
      status: status,
      amount: amount,
      currency: data['currency'] as String? ?? 'CLP',
      paymentMethod: data['paymentMethod'] != null
          ? PaymentMethodExtension.fromString(data['paymentMethod'].toString())
          : null,
      paymentMethodId: data['paymentMethodId']?.toString(),
      statusDetail: data['statusDetail']?.toString(),
      createdAt: createdAt,
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
    final id = json['id']?.toString() ?? '';
    final orderId = json['orderId']?.toString() ?? '';
    final preferenceId = (json['preferenceId']?.toString().trim().isNotEmpty ?? false)
        ? json['preferenceId']!.toString().trim()
        : id;

    final statusRaw = json['status']?.toString();
    final status = statusRaw != null && statusRaw.isNotEmpty
        ? PaymentStatusExtension.fromString(statusRaw)
        : PaymentStatus.pending;

    final amountRaw = json['amount'];
    final amount = amountRaw is num ? amountRaw.toDouble() : 0.0;

    final createdAtRaw = json['createdAt']?.toString();
    final createdAt = createdAtRaw != null && createdAtRaw.isNotEmpty
        ? DateTime.parse(createdAtRaw)
        : DateTime.now();

    return PaymentModel(
      id: id,
      orderId: orderId,
      preferenceId: preferenceId,
      paymentId: json['paymentId']?.toString(),
      status: status,
      amount: amount,
      currency: json['currency'] as String? ?? 'CLP',
      paymentMethod: json['paymentMethod'] != null
          ? PaymentMethodExtension.fromString(json['paymentMethod'].toString())
          : null,
      paymentMethodId: json['paymentMethodId']?.toString(),
      statusDetail: json['statusDetail']?.toString(),
      createdAt: createdAt,
      approvedAt: json['approvedAt'] != null
          ? DateTime.parse(json['approvedAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'].toString())
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

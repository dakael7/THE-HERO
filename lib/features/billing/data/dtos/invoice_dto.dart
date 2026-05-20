import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/invoice_entity.dart';

class InvoiceDto {
  final String invoiceId;
  final String orderId;
  final String payerUserId;
  final String? sellerUserId;
  final String documentType;
  final String status;
  final String? provider;
  final String? providerDocumentId;
  final String? providerTrackId;
  final String? pdfPath;
  final String? pdfUrl;
  final String? xmlPath;
  final String? xmlUrl;
  final String? errorCode;
  final String? errorMessage;
  final int retryCount;
  final DateTime? issuedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InvoiceDto({
    required this.invoiceId,
    required this.orderId,
    required this.payerUserId,
    this.sellerUserId,
    required this.documentType,
    required this.status,
    this.provider,
    this.providerDocumentId,
    this.providerTrackId,
    this.pdfPath,
    this.pdfUrl,
    this.xmlPath,
    this.xmlUrl,
    this.errorCode,
    this.errorMessage,
    this.retryCount = 0,
    this.issuedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory InvoiceDto.fromFirestore(
    Map<String, dynamic> json, {
    required String docId,
  }) {
    String? readString(dynamic raw) {
      if (raw == null) return null;
      if (raw is! String) return null;
      final value = raw.trim();
      return value.isEmpty ? null : value;
    }

    int readInt(dynamic raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return 0;
    }

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      if (raw is int) {
        try {
          return DateTime.fromMillisecondsSinceEpoch(raw);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return InvoiceDto(
      invoiceId: readString(json['invoiceId']) ?? docId,
      orderId: readString(json['orderId']) ?? '',
      payerUserId: readString(json['payerUserId']) ?? '',
      sellerUserId: readString(json['sellerUserId']),
      documentType: readString(json['documentType']) ?? 'factura',
      status: readString(json['status']) ?? 'unknown',
      provider: readString(json['provider']),
      providerDocumentId: readString(json['providerDocumentId']),
      providerTrackId: readString(json['providerTrackId']),
      pdfPath: readString(json['pdfPath']),
      pdfUrl: readString(json['pdfUrl']),
      xmlPath: readString(json['xmlPath']),
      xmlUrl: readString(json['xmlUrl']),
      errorCode: readString(json['errorCode']),
      errorMessage: readString(json['errorMessage']),
      retryCount: readInt(json['retryCount']),
      issuedAt: parseDate(json['issuedAt']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  BillingInvoiceEntity toEntity() {
    return BillingInvoiceEntity(
      invoiceId: invoiceId,
      orderId: orderId,
      payerUserId: payerUserId,
      sellerUserId: sellerUserId,
      documentType: documentType,
      status: billingInvoiceStatusFromString(status),
      provider: provider,
      providerDocumentId: providerDocumentId,
      providerTrackId: providerTrackId,
      pdfPath: pdfPath,
      pdfUrl: pdfUrl,
      xmlPath: xmlPath,
      xmlUrl: xmlUrl,
      errorCode: errorCode,
      errorMessage: errorMessage,
      retryCount: retryCount,
      issuedAt: issuedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class BillingInvoiceEntity {
  final String invoiceId;
  final String orderId;
  final String payerUserId;
  final String? sellerUserId;
  final String documentType;
  final BillingInvoiceStatus status;
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

  const BillingInvoiceEntity({
    required this.invoiceId,
    required this.orderId,
    required this.payerUserId,
    this.sellerUserId,
    this.documentType = 'factura',
    this.status = BillingInvoiceStatus.unknown,
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

  bool get isIssued => status == BillingInvoiceStatus.issued;
  bool get hasPdf {
    final hasPath = (pdfPath ?? '').trim().isNotEmpty;
    final hasUrl = (pdfUrl ?? '').trim().isNotEmpty;
    return hasPath || hasUrl;
  }
}

enum BillingInvoiceStatus {
  pending,
  issued,
  failed,
  canceled,
  unknown,
}

BillingInvoiceStatus billingInvoiceStatusFromString(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  switch (value) {
    case 'pending':
      return BillingInvoiceStatus.pending;
    case 'issued':
      return BillingInvoiceStatus.issued;
    case 'failed':
      return BillingInvoiceStatus.failed;
    case 'canceled':
    case 'cancelled':
      return BillingInvoiceStatus.canceled;
    default:
      return BillingInvoiceStatus.unknown;
  }
}

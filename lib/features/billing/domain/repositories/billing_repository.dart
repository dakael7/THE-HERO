import '../entities/invoice_entity.dart';

abstract class BillingRepository {
  Stream<BillingInvoiceEntity?> watchInvoiceByOrderId(String orderId);
  Future<BillingInvoiceEntity?> getInvoiceByOrderId(String orderId);
  Future<String> getInvoiceDownloadLink(String invoiceId);
  Future<void> retryInvoiceEmission(String invoiceId);
}

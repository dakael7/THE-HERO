import '../entities/invoice.dart';

abstract class InvoicesRepository {
  Future<Invoice> createInvoice(Invoice invoice);
  Future<void> updateStatus({required String invoiceId, required InvoiceStatus status});
  Future<Invoice?> getById(String invoiceId);
  Future<Invoice?> getByNumber(String number);
  Stream<List<Invoice>> getByCustomer(String customerId, {int limit = 50});
  Stream<List<Invoice>> getByRider(String riderId, {int limit = 50});
  Stream<List<Invoice>> getRecent({int limit = 50});
}

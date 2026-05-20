import '../repositories/billing_repository.dart';

class GetInvoicePdfUrlUseCase {
  final BillingRepository _repository;

  GetInvoicePdfUrlUseCase(this._repository);

  Future<String> execute(String invoiceId) async {
    if (invoiceId.trim().isEmpty) {
      throw Exception('invoiceId es requerido');
    }
    return _repository.getInvoiceDownloadLink(invoiceId);
  }
}

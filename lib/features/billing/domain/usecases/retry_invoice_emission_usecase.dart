import '../repositories/billing_repository.dart';

class RetryInvoiceEmissionUseCase {
  final BillingRepository _repository;

  RetryInvoiceEmissionUseCase(this._repository);

  Future<void> execute(String invoiceId) async {
    if (invoiceId.trim().isEmpty) {
      throw Exception('invoiceId es requerido');
    }
    await _repository.retryInvoiceEmission(invoiceId);
  }
}

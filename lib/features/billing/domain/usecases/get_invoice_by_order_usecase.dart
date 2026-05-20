import '../entities/invoice_entity.dart';
import '../repositories/billing_repository.dart';

class GetInvoiceByOrderUseCase {
  final BillingRepository _repository;

  GetInvoiceByOrderUseCase(this._repository);

  Stream<BillingInvoiceEntity?> watch(String orderId) {
    if (orderId.trim().isEmpty) {
      return Stream.value(null);
    }
    return _repository.watchInvoiceByOrderId(orderId);
  }

  Future<BillingInvoiceEntity?> execute(String orderId) async {
    if (orderId.trim().isEmpty) return null;
    return _repository.getInvoiceByOrderId(orderId);
  }
}

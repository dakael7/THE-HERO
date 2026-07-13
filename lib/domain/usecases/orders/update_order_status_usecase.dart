import '../../repositories/orders_repository.dart';

class UpdateOrderStatusUseCase {
  final OrdersRepository _repository;

  UpdateOrderStatusUseCase({required OrdersRepository repository})
    : _repository = repository;

  Future<void> execute(
    String orderId,
    String status, {
    double riderServiceFeeCLP = 0.0,
    double riderTaxPercentage = 0.07,
  }) async {
    await _repository.updateOrderStatus(
      orderId,
      status,
      riderServiceFeeCLP: riderServiceFeeCLP,
      riderTaxPercentage: riderTaxPercentage,
    );
  }
}

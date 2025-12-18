import '../../repositories/orders_repository.dart';

class UpdateOrderStatusUseCase {
  final OrdersRepository _repository;

  UpdateOrderStatusUseCase({required OrdersRepository repository})
      : _repository = repository;

  Future<void> execute(String orderId, String status) async {
    await _repository.updateOrderStatus(orderId, status);
  }
}

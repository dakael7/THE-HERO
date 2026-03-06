import '../../repositories/orders_repository.dart';

class UnassignRiderAndRequeueUseCase {
  final OrdersRepository _repository;

  UnassignRiderAndRequeueUseCase({required OrdersRepository repository})
      : _repository = repository;

  Future<void> execute({
    required String orderId,
    required String riderId,
  }) async {
    await _repository.unassignRiderAndRequeue(orderId, riderId);
  }
}

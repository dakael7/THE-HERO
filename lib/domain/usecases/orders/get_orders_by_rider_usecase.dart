import '../../entities/order.dart';
import '../../repositories/orders_repository.dart';

class GetOrdersByRiderUseCase {
  final OrdersRepository _repository;

  GetOrdersByRiderUseCase({required OrdersRepository repository})
      : _repository = repository;

  Stream<List<Order>> execute(String riderId) {
    return _repository.getOrdersByRider(riderId);
  }
}

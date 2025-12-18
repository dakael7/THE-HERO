import '../../entities/order.dart';
import '../../repositories/orders_repository.dart';

class GetOrdersByHeroUseCase {
  final OrdersRepository _repository;

  GetOrdersByHeroUseCase({required OrdersRepository repository})
      : _repository = repository;

  Stream<List<Order>> execute(String heroId) {
    return _repository.getOrdersByHero(heroId);
  }
}

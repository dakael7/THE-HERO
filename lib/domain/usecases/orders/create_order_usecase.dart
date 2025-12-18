import '../../entities/order.dart';
import '../../repositories/orders_repository.dart';
import '../../repositories/offers_repository.dart';

class CreateOrderUseCase {
  final OrdersRepository _ordersRepository;
  final OffersRepository _offersRepository;

  CreateOrderUseCase({
    required OrdersRepository ordersRepository,
    required OffersRepository offersRepository,
  })  : _ordersRepository = ordersRepository,
        _offersRepository = offersRepository;

  Future<Order> execute(Order order) async {
    final createdOrder = await _ordersRepository.createOrder(order);

    for (final item in order.items) {
      await _offersRepository.decrementStock(item.offerId, item.qty);
    }

    return createdOrder;
  }
}

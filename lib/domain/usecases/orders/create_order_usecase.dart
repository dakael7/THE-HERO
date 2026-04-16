import '../../entities/order.dart';
import '../../entities/order_status.dart';
import '../../entities/user.dart';
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

  Future<Order> execute(Order order, {required User currentUser}) async {
    if (currentUser.isBanned) {
      throw Exception('Tu cuenta está baneada.');
    }
    if (currentUser.isSuspended) {
      throw Exception('Tu cuenta está suspendida. No puedes realizar esta acción.');
    }

    final createdOrder = await _ordersRepository.createOrder(order);

    // Only decrement stock immediately for orders that are already operational.
    // For MercadoPago orders (pending payment), stock is decremented server-side
    // after payment approval.
    if (order.status != OrderStatus.pendingPayment) {
      for (final item in order.items) {
        await _offersRepository.decrementStock(item.offerId, item.qty);
      }
    }

    return createdOrder;
  }
}

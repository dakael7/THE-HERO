import '../../entities/order.dart';
import '../../entities/user.dart';
import '../../repositories/orders_repository.dart';

class CreateOrderUseCase {
  final OrdersRepository _ordersRepository;

  CreateOrderUseCase({required OrdersRepository ordersRepository})
    : _ordersRepository = ordersRepository;

  Future<Order> execute(Order order, {required User currentUser}) async {
    if (currentUser.isBanned) {
      throw Exception('Tu cuenta está baneada.');
    }
    if (currentUser.isSuspended) {
      throw Exception(
        'Tu cuenta está suspendida. No puedes realizar esta acción.',
      );
    }

    return _ordersRepository.createOrder(order);
  }
}

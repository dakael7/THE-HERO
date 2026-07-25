import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/providers/repository_providers.dart';
import '../usecases/orders/create_order_usecase.dart';
import '../usecases/orders/get_orders_by_hero_usecase.dart';
import '../usecases/orders/get_orders_by_rider_usecase.dart';
import '../usecases/orders/get_available_orders_usecase.dart';
import '../usecases/orders/claim_order_usecase.dart';
import '../usecases/orders/unassign_rider_and_requeue_usecase.dart';
import '../usecases/orders/update_order_status_usecase.dart';

part 'orders_usecase_providers.g.dart';

@Riverpod(keepAlive: true)
CreateOrderUseCase createOrderUseCase(Ref ref) {
  final ordersRepository = ref.read(ordersRepositoryProvider);
  return CreateOrderUseCase(ordersRepository: ordersRepository);
}

@Riverpod(keepAlive: true)
GetOrdersByHeroUseCase getOrdersByHeroUseCase(Ref ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return GetOrdersByHeroUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
GetOrdersByRiderUseCase getOrdersByRiderUseCase(Ref ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return GetOrdersByRiderUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
GetAvailableOrdersUseCase getAvailableOrdersUseCase(Ref ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return GetAvailableOrdersUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
ClaimOrderUseCase claimOrderUseCase(Ref ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return ClaimOrderUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
UpdateOrderStatusUseCase updateOrderStatusUseCase(Ref ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return UpdateOrderStatusUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
UnassignRiderAndRequeueUseCase unassignRiderAndRequeueUseCase(Ref ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return UnassignRiderAndRequeueUseCase(repository: repository);
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/repository_providers.dart';
import '../usecases/orders/create_order_usecase.dart';
import '../usecases/orders/get_orders_by_hero_usecase.dart';
import '../usecases/orders/get_orders_by_rider_usecase.dart';
import '../usecases/orders/get_available_orders_usecase.dart';
import '../usecases/orders/claim_order_usecase.dart';
import '../usecases/orders/update_order_status_usecase.dart';

final createOrderUseCaseProvider = Provider<CreateOrderUseCase>((ref) {
  final ordersRepository = ref.read(ordersRepositoryProvider);
  final offersRepository = ref.read(offersRepositoryProvider);
  return CreateOrderUseCase(
    ordersRepository: ordersRepository,
    offersRepository: offersRepository,
  );
});

final getOrdersByHeroUseCaseProvider = Provider<GetOrdersByHeroUseCase>((ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return GetOrdersByHeroUseCase(repository: repository);
});

final getOrdersByRiderUseCaseProvider = Provider<GetOrdersByRiderUseCase>((ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return GetOrdersByRiderUseCase(repository: repository);
});

final getAvailableOrdersUseCaseProvider = Provider<GetAvailableOrdersUseCase>((ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return GetAvailableOrdersUseCase(repository: repository);
});

final claimOrderUseCaseProvider = Provider<ClaimOrderUseCase>((ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return ClaimOrderUseCase(repository: repository);
});

final updateOrderStatusUseCaseProvider = Provider<UpdateOrderStatusUseCase>((ref) {
  final repository = ref.read(ordersRepositoryProvider);
  return UpdateOrderStatusUseCase(repository: repository);
});

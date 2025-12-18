import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../../domain/providers/orders_usecase_providers.dart';

final myOrdersProvider = StreamProvider.family<List<Order>, String>((ref, heroId) {
  final useCase = ref.read(getOrdersByHeroUseCaseProvider);
  return useCase.execute(heroId);
});

final riderOrdersProvider = StreamProvider.family<List<Order>, String>((ref, riderId) {
  final useCase = ref.read(getOrdersByRiderUseCaseProvider);
  return useCase.execute(riderId);
});

final availableOrdersProvider = StreamProvider.autoDispose
    .family<List<Order>, VehicleType>((ref, riderVehicleType) {
  final useCase = ref.read(getAvailableOrdersUseCaseProvider);
  return useCase.execute(riderVehicleType: riderVehicleType);
});

class OrderNotifier extends Notifier<AsyncValue<Order?>> {
  @override
  AsyncValue<Order?> build() {
    return const AsyncValue.data(null);
  }

  Future<void> createOrder(Order order) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(createOrderUseCaseProvider);
      final createdOrder = await useCase.execute(order);
      state = AsyncValue.data(createdOrder);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> claimOrder({
    required String orderId,
    required String riderId,
    required VehicleType riderVehicleType,
    required String riderName,
    required String riderPhone,
    required Order order,
  }) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(claimOrderUseCaseProvider);
      await useCase.execute(
        orderId: orderId,
        riderId: riderId,
        riderVehicleType: riderVehicleType,
        riderName: riderName,
        riderPhone: riderPhone,
        order: order,
      );
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> updateStatus(String orderId, String status) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(updateOrderStatusUseCaseProvider);
      await useCase.execute(orderId, status);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

final orderNotifierProvider =
    NotifierProvider<OrderNotifier, AsyncValue<Order?>>(() {
  return OrderNotifier();
});

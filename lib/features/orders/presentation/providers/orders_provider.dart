import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../../domain/providers/orders_usecase_providers.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../data/models/order_model.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

final myOrdersProvider = StreamProvider.family<List<Order>, String>((
  ref,
  heroId,
) {
  final auth = ref.watch(firebaseAuthProvider);
  final currentUid = auth.currentUser?.uid;
  if (currentUid == null || currentUid != heroId) {
    return Stream.value(const []);
  }

  final useCase = ref.read(getOrdersByHeroUseCaseProvider);
  return useCase.execute(heroId);
});

final riderOrdersProvider = StreamProvider.autoDispose.family<List<Order>, String>((
  ref,
  riderId,
) {
  final auth = ref.watch(firebaseAuthProvider);
  final currentUid = auth.currentUser?.uid;
  if (currentUid == null || currentUid != riderId) {
    return Stream.value(const []);
  }

  final useCase = ref.read(getOrdersByRiderUseCaseProvider);
  return useCase.execute(riderId);
});

final orderByIdProvider = StreamProvider.autoDispose.family<Order?, String>((ref, orderId) {
  final auth = ref.watch(firebaseAuthProvider);
  final currentUid = auth.currentUser?.uid;
  if (currentUid == null) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore.collection('orders').doc(orderId).snapshots().map((doc) {
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;

    final order = OrderModel.fromJson(data).toEntity();
    return order;
  });
});

final availableOrdersProvider = StreamProvider.autoDispose
    .family<List<Order>, VehicleType>((ref, riderVehicleType) {
      final auth = ref.watch(firebaseAuthProvider);
      if (auth.currentUser == null) {
        print('⚠️ [AvailableOrders] No authenticated user');
        return Stream.value(const []);
      }

      print(
        '🔍 [AvailableOrders] Fetching orders for vehicle type: ${riderVehicleType.name}',
      );
      final useCase = ref.read(getAvailableOrdersUseCaseProvider);
      return useCase.execute(riderVehicleType: riderVehicleType).map((orders) {
        print(
          '📦 [AvailableOrders] Received ${orders.length} orders from stream',
        );
        for (var order in orders) {
          print(
            '   - Order ${order.orderId}: status=${order.status.name}, vehicle=${order.requirements.requiredVehicle.name}',
          );
        }
        return orders;
      });
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
      final profile = await ref.read(profileProvider.future);
      final riderProfile = profile?.riderProfile;
      if (riderProfile == null) {
        throw Exception('Debes completar tu perfil de rider.');
      }

      final isActive = riderProfile.isActive == true;
      final isVerified = riderProfile.isVerified == true;

      // Business rule: bicycle riders can accept without full verification flow.
      if (riderVehicleType == VehicleType.bicycle) {
        if (!isActive) {
          throw Exception(
            'Debes activar tu perfil de rider para aceptar pedidos',
          );
        }
      } else {
        if (!isActive) {
          throw Exception(
            'Debes activar tu perfil de rider para aceptar pedidos',
          );
        }

        if (!isVerified) {
          throw Exception('Rider no verificado para aceptar pedidos');
        }
      }

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
      rethrow;
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

  Future<void> confirmDeliveryAndRate({
    required String orderId,
    required double rating,
    String? comment,
  }) async {
    state = const AsyncValue.loading();
    try {
      final firestore = ref.read(firebaseFirestoreProvider);

      // Get the order to find the rider ID
      final orderDoc = await firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) {
        throw Exception('Order not found');
      }

      final orderData = orderDoc.data();
      if (orderData == null) {
        throw Exception('Order data is null');
      }

      final riderData = orderData['rider'] as Map<String, dynamic>?;
      final riderId = riderData?['assignedRiderId'] as String?;

      if (riderId == null || riderId.isEmpty) {
        throw Exception('No rider assigned to this order');
      }

      // Update order with confirmation and rating
      await firestore.collection('orders').doc(orderId).update({
        'confirmedByHero': true,
        'heroRating': rating,
        'heroRatingComment': comment,
        'updatedAt': DateTime.now(),
      });

      // Update rider's rating statistics
      final riderDoc = await firestore.collection('users').doc(riderId).get();
      if (riderDoc.exists) {
        final userData = riderDoc.data();
        final riderProfile = userData?['riderProfile'] as Map<String, dynamic>?;

        if (riderProfile != null) {
          final currentRating =
              (riderProfile['rating'] as num?)?.toDouble() ?? 0.0;
          final currentTotalRatings =
              (riderProfile['totalRatings'] as int?) ?? 0;

          // Calculate new average rating
          final newTotalRatings = currentTotalRatings + 1;
          final newAverageRating =
              ((currentRating * currentTotalRatings) + rating) /
              newTotalRatings;

          // Update rider profile with new rating
          await firestore.collection('users').doc(riderId).update({
            'riderProfile.rating': newAverageRating,
            'riderProfile.totalRatings': newTotalRatings,
          });
        }
      }

      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
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

// Alias for easier access to order actions
final orderActionsProvider = orderNotifierProvider.notifier;

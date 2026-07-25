import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../../domain/providers/orders_usecase_providers.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../../data/models/order_model.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../../domain/config/pricing_config_provider.dart';
import '../../../../core/utils/stream_first_event_timeout.dart';
import '../../../../core/config/env.dart';

String? _riderCountryCode(dynamic profile) {
  final primaryAddress = profile?.primaryAddressSlot == null
      ? null
      : profile?.addressSlots[profile.primaryAddressSlot];
  return (primaryAddress?.countryCode ?? profile?.address?.countryCode)
      ?.trim()
      .toUpperCase();
}

final myOrdersProvider = StreamProvider.family<List<Order>, String>((
  ref,
  heroId,
) {
  final currentUid = ref.watch(currentUserIdProvider);
  if (currentUid == null || currentUid != heroId) {
    return Stream.value(const []);
  }

  final useCase = ref.read(getOrdersByHeroUseCaseProvider);
  return withFirstEventTimeout(
    useCase.execute(heroId),
    message:
        'No pudimos cargar tus pedidos a tiempo. Revisa tu conexion e intentalo nuevamente.',
  );
});

final myDonationOrdersProvider = StreamProvider.family<List<Order>, String>((
  ref,
  heroId,
) {
  final currentUid = ref.watch(currentUserIdProvider);
  if (currentUid == null || currentUid != heroId) {
    return Stream.value(const []);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  final stream = firestore
      .collection('orders')
      .where('sellerHeroIds', arrayContains: heroId)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs
            .map<Order?>((doc) {
              final data = doc.data();
              final orderId = (data['orderId'] as String?)?.trim();
              final normalizedData = (orderId != null && orderId.isNotEmpty)
                  ? data
                  : <String, dynamic>{...data, 'orderId': doc.id};
              final order = OrderModel.fromJson(normalizedData).toEntity();

              // Seller should only see orders that have been paid
              // and are actionable/traceable.
              if (order.isFulfillmentBlocked) {
                return null;
              }

              final isVisibleForSeller = switch (order.status) {
                OrderStatus.queued ||
                OrderStatus.assigned ||
                OrderStatus.pickedUp ||
                OrderStatus.inTransit ||
                OrderStatus.delivered ||
                OrderStatus.paid => true,
                OrderStatus.created ||
                OrderStatus.pendingPayment ||
                OrderStatus.canceled ||
                OrderStatus.failed => false,
              };

              if (!isVisibleForSeller) {
                return null;
              }

              return order;
            })
            .whereType<Order>()
            .toList();
      });
  return withFirstEventTimeout(
    stream,
    message:
        'No pudimos cargar los pedidos recibidos a tiempo. Revisa tu conexion e intentalo nuevamente.',
  );
});

final riderOrdersProvider = StreamProvider.autoDispose
    .family<List<Order>, String>((ref, riderId) {
      final currentUid = ref.watch(currentUserIdProvider);
      if (currentUid == null || currentUid != riderId) {
        return Stream.value(const []);
      }

      final useCase = ref.read(getOrdersByRiderUseCaseProvider);
      return useCase.execute(riderId);
    });

final orderByIdProvider = StreamProvider.autoDispose.family<Order?, String>((
  ref,
  orderId,
) {
  final currentUid = ref.watch(currentUserIdProvider);
  if (currentUid == null) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore.collection('orders').doc(orderId).snapshots().map((doc) {
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;

    final storedOrderId = data['orderId']?.toString().trim() ?? '';
    final normalizedData = storedOrderId.isNotEmpty
        ? data
        : <String, dynamic>{...data, 'orderId': doc.id};
    final order = OrderModel.fromJson(normalizedData).toEntity();
    return order;
  });
});

final orderByIdFutureProvider = FutureProvider.autoDispose
    .family<Order?, String>((ref, orderId) async {
      final currentUid = ref.watch(currentUserIdProvider);
      if (currentUid == null) {
        return null;
      }

      final repository = ref.read(ordersRepositoryProvider);
      return repository.getOrderById(orderId);
    });

final availableOrdersProvider = StreamProvider.autoDispose
    .family<List<Order>, VehicleType>((ref, riderVehicleType) {
      final currentUid = ref.watch(currentUserIdProvider);
      if (currentUid == null) {
        debugPrint('⚠️ [AvailableOrders] No authenticated user');
        return Stream.value(const []);
      }

      debugPrint(
        '🔍 [AvailableOrders] Fetching orders for vehicle type: ${riderVehicleType.name}',
      );
      final profile = ref.watch(profileStreamProvider).value;
      final countryCode = _riderCountryCode(profile);
      if (countryCode == null || countryCode.isEmpty) {
        debugPrint('[AvailableOrders] Rider has no country configured');
        return Stream.value(const []);
      }

      final useCase = ref.read(getAvailableOrdersUseCaseProvider);
      return useCase
          .execute(
            riderVehicleType: riderVehicleType,
            countryCode: countryCode,
            limit: 20,
          )
          .map((orders) {
            final filtered = orders.where((o) => !o.inPersonPickup).toList();
            debugPrint(
              '📦 [AvailableOrders] Received ${filtered.length} orders from stream',
            );
            for (var order in filtered) {
              debugPrint(
                '   - Order ${order.orderId}: status=${order.status.name}, vehicle=${order.requirements.requiredVehicle.name}',
              );
            }
            return filtered;
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
      final user = await ref.read(profileProvider.future);
      if (user == null) {
        throw Exception('Debes iniciar sesión para crear una orden.');
      }
      final useCase = ref.read(createOrderUseCaseProvider);
      final createdOrder = await useCase.execute(order, currentUser: user);
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
      final devCheckoutBypass = Env.devCheckoutBypass;
      if (!devCheckoutBypass && riderProfile == null) {
        throw Exception('Debes completar tu perfil de rider.');
      }

      final riderCountry = _riderCountryCode(profile);
      final orderCountry = order.countryCode?.trim().toUpperCase();
      if (riderCountry == null ||
          riderCountry.isEmpty ||
          orderCountry == null ||
          orderCountry.isEmpty ||
          riderCountry != orderCountry) {
        throw Exception('Este pedido no esta disponible en tu pais.');
      }

      final isActive = riderProfile?.isActive == true;
      final isActiveVehicleVerified =
          riderProfile?.isActiveVehicleVerified == true;

      // Business rule: bicycle riders can accept without full verification flow.
      if (!devCheckoutBypass && riderVehicleType == VehicleType.bicycle) {
        if (!isActive) {
          throw Exception(
            'Debes activar tu perfil de rider para aceptar pedidos',
          );
        }
      } else if (!devCheckoutBypass) {
        if (!isActive) {
          throw Exception(
            'Debes activar tu perfil de rider para aceptar pedidos',
          );
        }

        if (!isActiveVehicleVerified) {
          throw Exception(
            'Tu vehículo activo no está verificado para aceptar este pedido',
          );
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

  Future<void> confirmInPersonPickupReceived({required String orderId}) async {
    state = const AsyncValue.loading();
    try {
      final firestore = ref.read(firebaseFirestoreProvider);
      await firestore.collection('orders').doc(orderId).update({
        'confirmedByHero': true,
        'updatedAt': DateTime.now(),
      });
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> confirmInPersonPickupAndRateSeller({
    required String orderId,
    required String sellerHeroId,
    required double sellerRating,
    String? sellerComment,
  }) async {
    state = const AsyncValue.loading();
    try {
      final sellerId = sellerHeroId.trim();
      if (sellerId.isEmpty) {
        throw Exception('No se pudo identificar al donador.');
      }

      final firestore = ref.read(firebaseFirestoreProvider);
      final now = DateTime.now();
      await firestore.collection('orders').doc(orderId).update({
        'confirmedByHero': true,
        'sellerRating': sellerRating,
        'sellerRatingHeroId': sellerId,
        'sellerRatingComment': sellerComment,
        'updatedAt': now,
      });
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> rateBuyerForInPersonPickup({
    required String orderId,
    required String sellerId,
    required double buyerRating,
    String? buyerComment,
  }) async {
    state = const AsyncValue.loading();
    try {
      final normalizedSellerId = sellerId.trim();
      if (normalizedSellerId.isEmpty) {
        throw Exception('No se pudo identificar al donador.');
      }

      final firestore = ref.read(firebaseFirestoreProvider);
      final orderRef = firestore.collection('orders').doc(orderId);
      final orderDoc = await orderRef.get();
      if (!orderDoc.exists) {
        throw Exception('Pedido no encontrado.');
      }

      final data = orderDoc.data();
      if (data == null) {
        throw Exception('Pedido sin datos.');
      }

      final isInPersonPickup = data['inPersonPickup'] == true;
      if (!isInPersonPickup) {
        throw Exception('Este pedido no es de retiro en persona.');
      }

      final sellerIds =
          (data['sellerHeroIds'] as List<dynamic>?)
              ?.map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet() ??
          const <String>{};
      final itemSellerIds =
          (data['items'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((item) => item['sellerHeroIdSnapshot']?.toString().trim())
              .whereType<String>()
              .where((value) => value.isNotEmpty)
              .toSet() ??
          const <String>{};
      final canRate =
          sellerIds.contains(normalizedSellerId) ||
          itemSellerIds.contains(normalizedSellerId);
      if (!canRate) {
        throw Exception('Este donador no pertenece al pedido.');
      }

      final now = DateTime.now();
      await orderRef.update({
        'buyerRating': buyerRating,
        'buyerRatingComment': buyerComment,
        'buyerRatingBySellerId': normalizedSellerId,
        'buyerRatingAt': now,
        'updatedAt': now,
      });
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
      final commissionConfig = ref.read(riderCommissionConfigProvider);
      await useCase.execute(
        orderId,
        status,
        riderServiceFeeCLP: commissionConfig.serviceFeeCLP,
        riderTaxPercentage: commissionConfig.taxPercentage,
      );
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> unassignRiderAndRequeue({
    required String orderId,
    required String riderId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(unassignRiderAndRequeueUseCaseProvider);
      await useCase.execute(orderId: orderId, riderId: riderId);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> confirmDeliveryAndRate({
    required String orderId,
    required double rating,
    String? comment,
    double? sellerRating,
    String? sellerHeroId,
    String? sellerComment,
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

      final updatePayload = <String, dynamic>{
        'confirmedByHero': true,
        'heroRating': rating,
        'heroRatingComment': comment,
        'updatedAt': DateTime.now(),
      };
      if (sellerRating != null) {
        updatePayload['sellerRating'] = sellerRating;
      }
      if (sellerHeroId != null && sellerHeroId.trim().isNotEmpty) {
        updatePayload['sellerRatingHeroId'] = sellerHeroId.trim();
      }
      if (sellerComment != null) {
        updatePayload['sellerRatingComment'] = sellerComment;
      }

      // Update order with confirmation and rating
      await firestore.collection('orders').doc(orderId).update(updatePayload);

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

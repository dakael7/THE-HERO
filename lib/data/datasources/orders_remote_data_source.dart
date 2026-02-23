import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';

abstract class OrdersRemoteDataSource {
  Future<OrderModel> createOrder(OrderModel order);
  Future<OrderModel> updateOrder(OrderModel order);
  Future<OrderModel?> getOrderById(String orderId);
  Stream<List<OrderModel>> getOrdersByHero(String heroId);
  Stream<List<OrderModel>> getOrdersByRider(String riderId);
  Stream<List<OrderModel>> getAvailableOrders({
    required List<String> requiredVehicles,
    int limit = 50,
  });
  Future<void> updateOrderStatus(String orderId, String status);
  Future<void> assignRider(
    String orderId,
    String riderId,
    String vehicleType,
    String riderName,
    String riderPhone,
  );
  Future<void> cancelOrder(String orderId, String reason, String canceledBy);
}

class OrdersRemoteDataSourceImpl implements OrdersRemoteDataSource {
  final FirebaseFirestore _firestore;

  OrdersRemoteDataSourceImpl({required FirebaseFirestore firestore})
    : _firestore = firestore;

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    int attempt = 0;
    int delayMs = 300;
    while (true) {
      try {
        return await action();
      } on FirebaseException catch (e) {
        final code = e.code.toLowerCase();
        final isTransient =
            code == 'unavailable' || code == 'aborted' || code == 'deadline-exceeded';

        if (!isTransient || attempt >= 3) rethrow;

        await Future.delayed(Duration(milliseconds: delayMs));
        attempt++;
        delayMs = (delayMs * 2).clamp(300, 3000);
      }
    }
  }

  Map<String, dynamic> _withOrderId(Map<String, dynamic> data, String docId) {
    final orderId = (data['orderId'] as String?)?.trim() ?? '';
    if (orderId.isNotEmpty) return data;

    final copy = Map<String, dynamic>.from(data);
    copy['orderId'] = docId;
    return copy;
  }

  @override
  Future<OrderModel> createOrder(OrderModel order) async {
    try {
      final hasPreGeneratedId = order.orderId.isNotEmpty;

      if (hasPreGeneratedId) {
        final docRef = _firestore.collection('orders').doc(order.orderId);
        final createdOrder = order.toJson();
        createdOrder['orderId'] = docRef.id;
        await docRef.set(createdOrder);
        return OrderModel.fromJson(createdOrder);
      }

      final docRef = await _firestore.collection('orders').add(order.toJson());
      final createdOrder = order.toJson();
      createdOrder['orderId'] = docRef.id;
      await docRef.update({'orderId': docRef.id});
      return OrderModel.fromJson(createdOrder);
    } catch (e) {
      throw Exception('Error al crear pedido: $e');
    }
  }

  @override
  Future<OrderModel> updateOrder(OrderModel order) async {
    try {
      if (order.orderId.trim().isEmpty) {
        throw Exception('orderId inválido');
      }
      await _firestore
          .collection('orders')
          .doc(order.orderId)
          .update(order.toJson());
      return order;
    } catch (e) {
      throw Exception('Error al actualizar pedido: $e');
    }
  }

  @override
  Future<OrderModel?> getOrderById(String orderId) async {
    try {
      if (orderId.trim().isEmpty) {
        throw Exception('orderId inválido');
      }
      final doc = await _firestore.collection('orders').doc(orderId).get();
      if (!doc.exists) return null;
      final data = _withOrderId(doc.data()!, doc.id);
      return OrderModel.fromJson(data);
    } catch (e) {
      throw Exception('Error al obtener pedido: $e');
    }
  }

  @override
  Stream<List<OrderModel>> getOrdersByHero(String heroId) {
    try {
      if (heroId.trim().isEmpty) {
        throw Exception('heroId inválido');
      }
      return _firestore
          .collection('orders')
          .where('heroId', isEqualTo: heroId)
          .orderBy('timestamps.createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => OrderModel.fromJson(_withOrderId(doc.data(), doc.id)))
                .toList(),
          );
    } catch (e) {
      throw Exception('Error al obtener pedidos del hero: $e');
    }
  }

  @override
  Stream<List<OrderModel>> getOrdersByRider(String riderId) {
    try {
      if (riderId.trim().isEmpty) {
        throw Exception('riderId inválido');
      }
      return _firestore
          .collection('orders')
          .where('rider.assignedRiderId', isEqualTo: riderId)
          .orderBy('timestamps.assignedAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => OrderModel.fromJson(_withOrderId(doc.data(), doc.id)))
                .toList(),
          );
    } catch (e) {
      throw Exception('Error al obtener pedidos del rider: $e');
    }
  }

  @override
  Stream<List<OrderModel>> getAvailableOrders({
    required List<String> requiredVehicles,
    int limit = 50,
  }) {
    try {
      return _firestore
          .collection('orders')
          .where('status', isEqualTo: 'queued')
          .where('requirements.requiredVehicle', whereIn: requiredVehicles)
          .orderBy('timestamps.queuedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => OrderModel.fromJson(_withOrderId(doc.data(), doc.id)))
                .toList(),
          );
    } catch (e) {
      throw Exception('Error al obtener pedidos disponibles: $e');
    }
  }

  @override
  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      if (orderId.trim().isEmpty) {
        throw Exception('orderId inválido');
      }
      final updateData = {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      switch (status) {
        case 'paid':
          updateData['timestamps.paidAt'] = FieldValue.serverTimestamp();
          break;
        case 'queued':
          updateData['timestamps.queuedAt'] = FieldValue.serverTimestamp();
          break;
        case 'picked_up':
          updateData['timestamps.pickedUpAt'] = FieldValue.serverTimestamp();
          break;
        case 'in_transit':
          break;
        case 'delivered':
          updateData['timestamps.deliveredAt'] = FieldValue.serverTimestamp();
          break;
      }

      await _firestore.collection('orders').doc(orderId).update(updateData);
    } catch (e) {
      throw Exception('Error al actualizar estado del pedido: $e');
    }
  }

  @override
  Future<void> assignRider(
    String orderId,
    String riderId,
    String vehicleType,
    String riderName,
    String riderPhone,
  ) async {
    try {
      if (orderId.trim().isEmpty) {
        throw Exception('orderId inválido');
      }
      if (riderId.trim().isEmpty) {
        throw Exception('riderId inválido');
      }
      await _withRetry(() async {
        await _firestore.runTransaction((transaction) async {
          final orderRef = _firestore.collection('orders').doc(orderId);
          final orderDoc = await transaction.get(orderRef);

          if (!orderDoc.exists) {
            throw Exception('Pedido no encontrado');
          }

          final orderData = orderDoc.data()!;
          if (orderData['status'] != 'queued') {
            throw Exception('Pedido ya no está disponible');
          }

          if (orderData['rider']['assignedRiderId'] != null) {
            throw Exception('Pedido ya tiene rider asignado');
          }

          final riderUpdate = {
            'assignedRiderId': riderId,
            'assignedAt': FieldValue.serverTimestamp(),
            'vehicleTypeSnapshot': vehicleType,
            'riderNameSnapshot': riderName,
            'riderPhoneSnapshot': riderPhone,
          };

          transaction.update(orderRef, {
            'status': 'assigned',
            'rider': riderUpdate,
            'timestamps.assignedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      });
    } catch (e) {
      throw Exception('Error al asignar rider: $e');
    }
  }

  @override
  Future<void> cancelOrder(
    String orderId,
    String reason,
    String canceledBy,
  ) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final orderRef = _firestore.collection('orders').doc(orderId);
        final orderSnap = await transaction.get(orderRef);

        if (!orderSnap.exists) {
          throw Exception('Pedido no encontrado');
        }

        final data = orderSnap.data() ?? <String, dynamic>{};
        final currentStatus = (data['status'] as String?) ?? '';
        final alreadyRestored = data['stockRestored'] == true;

        final shouldTryReleaseReservation =
            currentStatus == 'pending_payment' ||
            currentStatus == 'pendingPayment' ||
            currentStatus == 'pendingpayment';

        if (!alreadyRestored) {
          if (shouldTryReleaseReservation) {
            final reservationRef = _firestore
                .collection('stockReservations')
                .doc(orderId);
            final reservationSnap = await transaction.get(reservationRef);
            if (reservationSnap.exists) {
              final reservation = reservationSnap.data() ?? <String, dynamic>{};
              final reservationStatus = reservation['status'] as String?;
              final itemsRaw = reservation['items'] as List<dynamic>?;

              if (reservationStatus == 'reserved' && itemsRaw != null) {
                for (final raw in itemsRaw) {
                  if (raw is! Map) continue;
                  final offerId = raw['offerId'] as String?;
                  final qty = raw['qty'] as int?;
                  if (offerId == null || offerId.isEmpty) continue;
                  final qtyInt = (qty == null || qty <= 0) ? 1 : qty;

                  final offerRef =
                      _firestore.collection('offers').doc(offerId);
                  final offerSnap = await transaction.get(offerRef);
                  if (!offerSnap.exists) continue;
                  final offerData = offerSnap.data() ?? <String, dynamic>{};
                  final currentQty = (offerData['availableQty'] as int?) ?? 0;
                  final newQty = currentQty + qtyInt;

                  final update = <String, Object?>{
                    'availableQty': newQty,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  final offerStatus = offerData['status'] as String?;
                  if (offerStatus == 'sold_out' && newQty > 0) {
                    update['status'] = 'active';
                  }

                  transaction.update(offerRef, update);
                }

                transaction.update(reservationRef, {
                  'status': 'released',
                  'releasedAt': FieldValue.serverTimestamp(),
                });
              }
            }
          } else {
            final itemsRaw = data['items'] as List<dynamic>?;
            if (itemsRaw != null) {
              for (final raw in itemsRaw) {
                if (raw is! Map) continue;
                final offerId = raw['offerId'] as String?;
                final qty = raw['qty'] as int?;
                if (offerId == null || offerId.isEmpty) continue;
                final qtyInt = (qty == null || qty <= 0) ? 1 : qty;

                final offerRef = _firestore.collection('offers').doc(offerId);
                final offerSnap = await transaction.get(offerRef);
                if (!offerSnap.exists) continue;
                final offerData = offerSnap.data() ?? <String, dynamic>{};
                final currentQty = (offerData['availableQty'] as int?) ?? 0;
                final newQty = currentQty + qtyInt;

                final update = <String, Object?>{
                  'availableQty': newQty,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                final offerStatus = offerData['status'] as String?;
                if (offerStatus == 'sold_out' && newQty > 0) {
                  update['status'] = 'active';
                }

                transaction.update(offerRef, update);
              }
            }
          }
        }

        transaction.update(orderRef, {
          'status': 'canceled',
          'cancelReason': reason,
          'canceledBy': canceledBy,
          'timestamps.canceledAt': FieldValue.serverTimestamp(),
          'stockRestored': true,
          'stockRestoredAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      throw Exception('Error al cancelar pedido: $e');
    }
  }
}

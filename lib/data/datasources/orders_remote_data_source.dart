import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';

abstract class OrdersRemoteDataSource {
  Future<OrderModel> createOrder(OrderModel order);
  Future<OrderModel> updateOrder(OrderModel order);
  Future<OrderModel?> getOrderById(String orderId);
  Stream<List<OrderModel>> getOrdersByHero(String heroId);
  Stream<List<OrderModel>> getOrdersByRider(String riderId);
  Stream<List<OrderModel>> getAvailableOrders({
    required String requiredVehicle,
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

  @override
  Future<OrderModel> createOrder(OrderModel order) async {
    try {
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
      final doc = await _firestore.collection('orders').doc(orderId).get();
      if (!doc.exists) return null;
      return OrderModel.fromJson(doc.data()!);
    } catch (e) {
      throw Exception('Error al obtener pedido: $e');
    }
  }

  @override
  Stream<List<OrderModel>> getOrdersByHero(String heroId) {
    try {
      return _firestore
          .collection('orders')
          .where('heroId', isEqualTo: heroId)
          .orderBy('timestamps.createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => OrderModel.fromJson(doc.data()))
              .toList());
    } catch (e) {
      throw Exception('Error al obtener pedidos del hero: $e');
    }
  }

  @override
  Stream<List<OrderModel>> getOrdersByRider(String riderId) {
    try {
      return _firestore
          .collection('orders')
          .where('rider.assignedRiderId', isEqualTo: riderId)
          .orderBy('timestamps.assignedAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => OrderModel.fromJson(doc.data()))
              .toList());
    } catch (e) {
      throw Exception('Error al obtener pedidos del rider: $e');
    }
  }

  @override
  Stream<List<OrderModel>> getAvailableOrders({
    required String requiredVehicle,
    int limit = 50,
  }) {
    try {
      return _firestore
          .collection('orders')
          .where('status', isEqualTo: 'queued')
          .where('requirements.requiredVehicle', isEqualTo: requiredVehicle)
          .orderBy('timestamps.queuedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => OrderModel.fromJson(doc.data()))
              .toList());
    } catch (e) {
      throw Exception('Error al obtener pedidos disponibles: $e');
    }
  }

  @override
  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
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

        transaction.update(orderRef, {
          'status': 'assigned',
          'rider.assignedRiderId': riderId,
          'rider.assignedAt': FieldValue.serverTimestamp(),
          'rider.vehicleTypeSnapshot': vehicleType,
          'rider.riderNameSnapshot': riderName,
          'rider.riderPhoneSnapshot': riderPhone,
          'timestamps.assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      throw Exception('Error al asignar rider: $e');
    }
  }

  @override
  Future<void> cancelOrder(String orderId, String reason, String canceledBy) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'status': 'canceled',
        'cancelReason': reason,
        'canceledBy': canceledBy,
        'timestamps.canceledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al cancelar pedido: $e');
    }
  }
}

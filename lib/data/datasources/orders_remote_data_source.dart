import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';
import '../../domain/services/rider_commission_calculator.dart';

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
  Future<void> updateOrderStatus(
    String orderId,
    String status, {
    double riderServiceFeeCLP,
    double riderTaxPercentage,
  });
  Future<void> assignRider(
    String orderId,
    String riderId,
    String vehicleType,
    String riderName,
    String riderPhone,
  );
  Future<void> unassignRiderAndRequeue(String orderId, String riderId);
  Future<void> cancelOrder(String orderId, String reason, String canceledBy);
}

class OrdersRemoteDataSourceImpl implements OrdersRemoteDataSource {
  final FirebaseFirestore _firestore;

  OrdersRemoteDataSourceImpl({required FirebaseFirestore firestore})
    : _firestore = firestore;

  bool _isVehicleCompatible({
    required String riderVehicleType,
    required String requiredVehicle,
  }) {
    final rider = riderVehicleType.toLowerCase().trim();
    final required = requiredVehicle.toLowerCase().trim();

    if (rider == 'car') {
      return required == 'car' ||
          required == 'motorcycle' ||
          required == 'bicycle';
    }
    if (rider == 'truck') {
      return required == 'truck' ||
          required == 'car' ||
          required == 'motorcycle' ||
          required == 'bicycle';
    }
    if (rider == 'motorcycle') {
      return required == 'motorcycle' || required == 'bicycle';
    }
    if (rider == 'bicycle') {
      return required == 'bicycle';
    }

    return false;
  }

  bool _isCashPaymentDoc(Map<String, dynamic> paymentData) {
    final methodId = paymentData['paymentMethodId']?.toString().toLowerCase();
    final statusDetail = paymentData['statusDetail']?.toString().toLowerCase();
    final method = paymentData['paymentMethod']?.toString().toLowerCase();

    return methodId == 'cash' ||
        statusDetail == 'cash_on_delivery' ||
        statusDetail == 'cash_collected' ||
        method == 'cash';
  }

  double _cashAmountToCollectFromOrder(Map<String, dynamic> orderData) {
    final total = (orderData['amountTotal'] as num?)?.toDouble() ?? 0.0;
    return total.clamp(0.0, double.infinity); // incluye propina — el rider cobra el total completo
  }

  int _toCents(num value) {
    return (value.toDouble() * 100).round();
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    int attempt = 0;
    int delayMs = 300;
    while (true) {
      try {
        return await action();
      } on FirebaseException catch (e) {
        final code = e.code.toLowerCase();
        final isTransient =
            code == 'unavailable' ||
            code == 'aborted' ||
            code == 'deadline-exceeded';

        if (!isTransient || attempt >= 3) rethrow;

        await Future.delayed(Duration(milliseconds: delayMs));
        attempt++;
        delayMs = (delayMs * 2).clamp(300, 3000);
      }
    }
  }

  @override
  Future<void> unassignRiderAndRequeue(String orderId, String riderId) async {
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

          final data = orderDoc.data()!;
          if (data['status'] != 'assigned') {
            throw Exception('Solo puedes cancelar antes de recoger');
          }

          final riderMap = (data['rider'] is Map)
              ? (data['rider'] as Map)
              : null;
          final assignedId = (riderMap?['assignedRiderId'] as String?) ?? '';
          if (assignedId.isEmpty || assignedId != riderId) {
            throw Exception('Pedido no asignado a este rider');
          }

          final timestamps = (data['timestamps'] is Map)
              ? (data['timestamps'] as Map)
              : null;
          if (timestamps != null && timestamps['pickedUpAt'] != null) {
            throw Exception('No puedes cancelar: ya marcaste recogido');
          }

          final paymentRef = _firestore
              .collection('payments')
              .doc('cash-$orderId');
          final paymentSnap = await transaction.get(paymentRef);
          final isCashOrder =
              paymentSnap.exists &&
              _isCashPaymentDoc(paymentSnap.data() ?? <String, dynamic>{});

          final riderRef = _firestore.collection('users').doc(riderId);
          final cancelEventRef = riderRef.collection('riderTripEvents').doc();
          transaction.set(cancelEventRef, {
            'type': 'canceled_trip',
            'orderId': orderId,
            'createdAt': Timestamp.now(),
          });

          final holdAlreadyReleased = data['cashHoldReleased'] == true;
          if (isCashOrder && !holdAlreadyReleased) {
            final holdRaw = riderMap?['cashHoldAmount'];
            final holdAmount = (holdRaw is num)
                ? holdRaw.toDouble()
                : _cashAmountToCollectFromOrder(data);
            final holdCents = _toCents(holdAmount);
            transaction.update(riderRef, {
              'riderWallet.cashOnHold': FieldValue.increment(-holdAmount),
              'riderWallet.cashOnHoldCents': FieldValue.increment(-holdCents),
            });

            final txRef = riderRef.collection('riderWalletTransactions').doc();
            transaction.set(txRef, {
              'type': 'cash_hold_release',
              'orderId': orderId,
              'amount': -holdAmount,
              'amountCents': -holdCents,
              'currency': data['currency']?.toString() ?? 'CLP',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          transaction.update(orderRef, {
            'status': 'queued',
            'rider': <String, dynamic>{},
            'pickupProgress': FieldValue.delete(),
            'timestamps.assignedAt': FieldValue.delete(),
            'timestamps.pickedUpAt': FieldValue.delete(),
            'timestamps.deliveredAt': FieldValue.delete(),
            if (isCashOrder && !holdAlreadyReleased) 'cashHoldReleased': true,
            'timestamps.queuedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      });
    } catch (e) {
      throw Exception('Error al cancelar pedido como rider: $e');
    }
  }

  Map<String, dynamic> _withOrderId(Map<String, dynamic> data, String docId) {
    final orderId = (data['orderId'] as String?)?.trim() ?? '';
    if (orderId.isNotEmpty) return data;

    final copy = Map<String, dynamic>.from(data);
    copy['orderId'] = docId;
    return copy;
  }

  Future<void> _writeUserOrdersIndex({
    required WriteBatch batch,
    required Map<String, dynamic> createdOrder,
  }) async {
    final orderId = (createdOrder['orderId'] as String?)?.trim() ?? '';
    final buyerId = (createdOrder['heroId'] as String?)?.trim() ?? '';

    if (orderId.isEmpty || buyerId.isEmpty) return;

    final buyerIndexRef = _firestore
        .collection('user_orders')
        .doc(buyerId)
        .collection('orders')
        .doc(orderId);
    batch.set(buyerIndexRef, {...createdOrder, 'role': 'buyer'});

    final sellerIdsRaw = createdOrder['sellerHeroIds'];
    if (sellerIdsRaw is! List) return;

    final sellerIds = sellerIdsRaw
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    for (final sellerId in sellerIds) {
      final sellerIndexRef = _firestore
          .collection('user_orders')
          .doc(sellerId)
          .collection('orders')
          .doc(orderId);
      batch.set(sellerIndexRef, {...createdOrder, 'role': 'seller'});
    }
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

        final indexBatch = _firestore.batch();
        await _writeUserOrdersIndex(
          batch: indexBatch,
          createdOrder: createdOrder,
        );
        await indexBatch.commit();
        return OrderModel.fromJson(createdOrder);
      }

      final docRef = _firestore.collection('orders').doc();
      final createdOrder = order.toJson();
      createdOrder['orderId'] = docRef.id;
      await docRef.set(createdOrder);

      final indexBatch = _firestore.batch();
      await _writeUserOrdersIndex(
        batch: indexBatch,
        createdOrder: createdOrder,
      );
      await indexBatch.commit();
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
                .map(
                  (doc) =>
                      OrderModel.fromJson(_withOrderId(doc.data(), doc.id)),
                )
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
                .map(
                  (doc) =>
                      OrderModel.fromJson(_withOrderId(doc.data(), doc.id)),
                )
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
                .map(
                  (doc) =>
                      OrderModel.fromJson(_withOrderId(doc.data(), doc.id)),
                )
                .toList(),
          );
    } catch (e) {
      throw Exception('Error al obtener pedidos disponibles: $e');
    }
  }

  @override
  Future<void> updateOrderStatus(
    String orderId,
    String status, {
    double riderServiceFeeCLP = RiderCommissionCalculator.serviceFeeCLP,
    double riderTaxPercentage = RiderCommissionCalculator.taxPercentage,
  }) async {
    try {
      if (orderId.trim().isEmpty) {
        throw Exception('orderId inválido');
      }

      await _withRetry(() async {
        await _firestore.runTransaction((transaction) async {
          final orderRef = _firestore.collection('orders').doc(orderId);
          final orderSnap = await transaction.get(orderRef);
          if (!orderSnap.exists) {
            throw Exception('Pedido no encontrado');
          }

          final data = orderSnap.data() ?? <String, dynamic>{};
          final updateData = <String, Object?>{
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
              updateData['timestamps.pickedUpAt'] =
                  FieldValue.serverTimestamp();
              break;
            case 'in_transit':
              break;
            case 'delivered':
              updateData['timestamps.deliveredAt'] =
                  FieldValue.serverTimestamp();
              break;
          }

          if (status == 'delivered') {
            final riderMap = (data['rider'] is Map)
                ? (data['rider'] as Map)
                : null;
            final riderId = riderMap?['assignedRiderId']?.toString() ?? '';
            final alreadyProcessed = data['riderEarningsProcessed'] == true;
            if (riderId.isNotEmpty && !alreadyProcessed) {
              final deliveryFee =
                  (data['deliveryFee'] as num?)?.toDouble() ?? 0.0;
              final tip = (data['tip'] as num?)?.toDouble() ?? 0.0;
              final earnings =
                  RiderCommissionCalculator.calculateCommissionWith(
                    deliveryFee: deliveryFee,
                    serviceFeeCLP: riderServiceFeeCLP,
                    taxPercentage: riderTaxPercentage,
                  );

              final paymentRef = _firestore
                  .collection('payments')
                  .doc('cash-$orderId');
              final paymentSnap = await transaction.get(paymentRef);
              final isCash =
                  paymentSnap.exists &&
                  _isCashPaymentDoc(paymentSnap.data() ?? <String, dynamic>{});


              final riderRef = _firestore.collection('users').doc(riderId);
              final riderSnap = await transaction.get(riderRef);
              if (!riderSnap.exists) {
                throw Exception('Rider no encontrado');
              }

              final riderData = riderSnap.data() ?? <String, dynamic>{};
              final wallet = (riderData['riderWallet'] is Map)
                  ? (riderData['riderWallet'] as Map)
                  : const <String, dynamic>{};
              final cashBalance =
                  (wallet['cashBalance'] as num?)?.toDouble() ?? 0.0;
              final cashOnHold =
                  (wallet['cashOnHold'] as num?)?.toDouble() ?? 0.0;

              final txCollection = riderRef.collection(
                'riderWalletTransactions',
              );

              if (!isCash) {
                // ── PAGO ONLINE: acreditar netEarnings + propina al saldo ──
                final earningsAmount = earnings.netEarnings + tip;
                final earningsCents = _toCents(earningsAmount);

                final earningsTxRef = txCollection.doc();
                transaction.set(earningsTxRef, {
                  'type': 'delivery_earnings',
                  'orderId': orderId,
                  'amount': earningsAmount,
                  'amountCents': earningsCents,
                  'currency': data['currency']?.toString() ?? 'CLP',
                  'createdAt': FieldValue.serverTimestamp(),
                  'meta': {
                    'deliveryFee': deliveryFee,
                    'tip': tip,
                    'tipCents': _toCents(tip),
                    'breakdown': earnings.breakdown,
                    'isCashOrder': false,
                  },
                });

                transaction.update(riderRef, {
                  'riderWallet.earningsBalance': FieldValue.increment(earningsAmount),
                  'riderWallet.earningsBalanceCents': FieldValue.increment(earningsCents),
                  'riderWallet.totalEarnings': FieldValue.increment(earningsAmount),
                  'riderWallet.totalEarningsCents': FieldValue.increment(earningsCents),
                });
              } else {
                // ── PAGO EFECTIVO: el rider ya cobró en mano ──
                // Solo descontar el monto cobrado del saldo (balance = lo que la plataforma le debe).
                // No se acredita delivery_earnings porque el rider ya tiene el efectivo.
                final cashSettlementProcessed =
                    data['cashSettlementProcessed'] == true;
                if (!cashSettlementProcessed) {
                  final holdRaw = riderMap?['cashHoldAmount'];
                  final cashAmount = (holdRaw is num)
                      ? holdRaw.toDouble()
                      : _cashAmountToCollectFromOrder(data);
                  final cashCents = _toCents(cashAmount);

                  final settlementTxRef = txCollection.doc();
                  transaction.set(settlementTxRef, {
                    'type': 'cash_settlement',
                    'orderId': orderId,
                    'amount': -cashAmount,
                    'amountCents': -cashCents,
                    'currency': data['currency']?.toString() ?? 'CLP',
                    'createdAt': FieldValue.serverTimestamp(),
                    'meta': {
                      'deliveryFee': deliveryFee,
                      'netEarnings': earnings.netEarnings,
                      'isCashOrder': true,
                    },
                  });

                  transaction.update(riderRef, {
                    // Liberar el hold y descontar del saldo en una sola operación
                    'riderWallet.cashOnHold': FieldValue.increment(-cashAmount),
                    'riderWallet.cashOnHoldCents': FieldValue.increment(-_toCents(cashAmount)),
                    'riderWallet.earningsBalance': FieldValue.increment(-cashAmount),
                    'riderWallet.earningsBalanceCents': FieldValue.increment(-cashCents),
                    // totalEarnings para estadísticas (netEarnings del envío, sin registrar en balance)
                    'riderWallet.totalEarnings': FieldValue.increment(earnings.netEarnings),
                    'riderWallet.totalEarningsCents': FieldValue.increment(_toCents(earnings.netEarnings)),
                  });

                  updateData['cashSettlementProcessed'] = true;
                }
              }

              updateData['riderEarningsProcessed'] = true;
              updateData['riderEarningsProcessedAt'] =
                  FieldValue.serverTimestamp();
              updateData['riderEarningsSnapshot'] = {
                'deliveryFee': deliveryFee,
                'tip': tip,
                'netEarnings': earnings.netEarnings,
                'serviceFee': earnings.serviceFee,
                'taxDeduction': earnings.taxDeduction,
              };

              if (isCash) {
                updateData['riderCashSnapshot'] = {
                  'cashBalanceBefore': cashBalance,
                  'cashOnHoldBefore': cashOnHold,
                };
              }
            }
          }

          transaction.update(orderRef, updateData);
        });
      });
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

          final requirements = orderData['requirements'];
          final requiredVehicle = requirements is Map
              ? (requirements['requiredVehicle']?.toString() ?? '')
              : '';
          if (requiredVehicle.isEmpty) {
            throw Exception('Pedido inválido: falta vehículo requerido');
          }

          if (!_isVehicleCompatible(
            riderVehicleType: vehicleType,
            requiredVehicle: requiredVehicle,
          )) {
            throw Exception(
              'Tu vehículo ($vehicleType) no es compatible con este pedido (requiere $requiredVehicle)',
            );
          }

          final paymentRef = _firestore
              .collection('payments')
              .doc('cash-$orderId');
          final paymentSnap = await transaction.get(paymentRef);
          final isCashOrder =
              paymentSnap.exists &&
              _isCashPaymentDoc(paymentSnap.data() ?? <String, dynamic>{});

          double? cashHoldAmount;
          if (isCashOrder) {
            final holdAmount = _cashAmountToCollectFromOrder(orderData);
            final holdCents = _toCents(holdAmount);
            final riderRef = _firestore.collection('users').doc(riderId);
            final riderSnap = await transaction.get(riderRef);
            if (!riderSnap.exists) {
              throw Exception('Rider no encontrado');
            }

            final riderData = riderSnap.data() ?? <String, dynamic>{};
            final wallet = (riderData['riderWallet'] is Map)
                ? (riderData['riderWallet'] as Map)
                : const <String, dynamic>{};

            final earningsBalanceCents =
                (wallet['earningsBalanceCents'] as num?)?.toInt();
            final earningsBalance = earningsBalanceCents != null
                ? (earningsBalanceCents / 100.0)
                : (wallet['earningsBalance'] as num?)?.toDouble() ?? 0.0;

            final cashOnHoldCents = (wallet['cashOnHoldCents'] as num?)
                ?.toInt();
            final cashOnHold = cashOnHoldCents != null
                ? (cashOnHoldCents / 100.0)
                : (wallet['cashOnHold'] as num?)?.toDouble() ?? 0.0;

            final available = (earningsBalance - cashOnHold).clamp(
              0.0,
              double.infinity,
            );

            if (available < holdAmount) {
              throw Exception(
                'Este pedido requiere pago en efectivo (\$${holdAmount.toStringAsFixed(0)}). '
                'Tu pendiente por pagar (\$${available.toStringAsFixed(0)}) no alcanza para tomarlo. '
                'Debes tener al menos \$${holdAmount.toStringAsFixed(0)} pendiente por pagar disponible.',
              );
            }

            transaction.update(riderRef, {
              'riderWallet.cashOnHold': FieldValue.increment(holdAmount),
              'riderWallet.cashOnHoldCents': FieldValue.increment(holdCents),
            });

            final txRef = riderRef.collection('riderWalletTransactions').doc();
            transaction.set(txRef, {
              'type': 'cash_hold',
              'orderId': orderId,
              'amount': holdAmount,
              'amountCents': holdCents,
              'currency': orderData['currency']?.toString() ?? 'CLP',
              'createdAt': FieldValue.serverTimestamp(),
            });

            cashHoldAmount = holdAmount;
          }

          final riderUpdate = {
            'assignedRiderId': riderId,
            'assignedAt': FieldValue.serverTimestamp(),
            'vehicleTypeSnapshot': vehicleType,
            'riderNameSnapshot': riderName,
            'riderPhoneSnapshot': riderPhone,
            if (cashHoldAmount != null) 'cashHoldAmount': cashHoldAmount,
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

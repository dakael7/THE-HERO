import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final FirebaseFunctions _functions;

  OrdersRemoteDataSourceImpl({
    required FirebaseFirestore firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

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

  Future<void> _ensureFreshAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesion para continuar');
    }
    await user.getIdToken(true);
  }

  dynamic _deepStringKeyed(dynamic value) {
    if (value is Map) {
      return value.map((key, nested) {
        return MapEntry(key.toString(), _deepStringKeyed(nested));
      });
    }
    if (value is List) {
      return value.map(_deepStringKeyed).toList();
    }
    return value;
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

          final riderRef = _firestore.collection('users').doc(riderId);
          final cancelEventRef = riderRef.collection('riderTripEvents').doc();
          transaction.set(cancelEventRef, {
            'type': 'canceled_trip',
            'orderId': orderId,
            'createdAt': Timestamp.now(),
          });

          final holdAlreadyReleased = data['cashHoldReleased'] == true;
          final holdRaw = riderMap?['cashHoldAmount'];
          final holdAmount = (holdRaw is num) ? holdRaw.toDouble() : 0.0;
          final isCashOrder = holdAmount > 0;
          if (isCashOrder && !holdAlreadyReleased) {
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

  @override
  Future<OrderModel> createOrder(OrderModel order) async {
    try {
      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('createOrder');
      final result = await callable.call(order.toJson());
      return OrderModel.fromJson(
        (_deepStringKeyed(result.data) as Map).cast<String, dynamic>(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo crear el pedido');
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
        throw Exception('orderId invalido');
      }

      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('updateOrderStatus');
      await callable.call(<String, dynamic>{
        'orderId': orderId,
        'newStatus': status,
        'riderServiceFeeCLP': riderServiceFeeCLP,
        'riderTaxPercentage': riderTaxPercentage,
      });
      return;

      // ignore: dead_code
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
              final holdRaw = riderMap?['cashHoldAmount'];
              final cashHoldAmount = (holdRaw is num)
                  ? holdRaw.toDouble()
                  : 0.0;
              final isCash = cashHoldAmount > 0;

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
                  'riderWallet.earningsBalance': FieldValue.increment(
                    earningsAmount,
                  ),
                  'riderWallet.earningsBalanceCents': FieldValue.increment(
                    earningsCents,
                  ),
                  'riderWallet.totalEarnings': FieldValue.increment(
                    earningsAmount,
                  ),
                  'riderWallet.totalEarningsCents': FieldValue.increment(
                    earningsCents,
                  ),
                });
              } else {
                // ── PAGO EFECTIVO: el rider ya cobró en mano ──
                // Solo descontar el monto cobrado del saldo (balance = lo que la plataforma le debe).
                // No se acredita delivery_earnings porque el rider ya tiene el efectivo.
                final cashSettlementProcessed =
                    data['cashSettlementProcessed'] == true;
                if (!cashSettlementProcessed) {
                  final cashAmount = cashHoldAmount;
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
                    'riderWallet.cashOnHoldCents': FieldValue.increment(
                      -_toCents(cashAmount),
                    ),
                    'riderWallet.earningsBalance': FieldValue.increment(
                      -cashAmount,
                    ),
                    'riderWallet.earningsBalanceCents': FieldValue.increment(
                      -cashCents,
                    ),
                    // totalEarnings para estadísticas (netEarnings del envío, sin registrar en balance)
                    'riderWallet.totalEarnings': FieldValue.increment(
                      earnings.netEarnings,
                    ),
                    'riderWallet.totalEarningsCents': FieldValue.increment(
                      _toCents(earnings.netEarnings),
                    ),
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
      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('claimOrder');
      await callable.call(<String, dynamic>{'orderId': orderId});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo aceptar el pedido');
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
      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('cancelOrder');
      await callable.call(<String, dynamic>{
        'orderId': orderId,
        'reason': reason,
        'canceledBy': canceledBy,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo cancelar el pedido');
    } catch (e) {
      throw Exception('Error al cancelar pedido: $e');
    }
  }
}

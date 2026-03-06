import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../../domain/entities/payment.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/payment_processing_screen.dart';
import '../../../payment/providers/payment_providers.dart';
import 'order_receipt_screen.dart';
import 'hero_order_status_screen.dart';

class HeroOrdersScreen extends ConsumerWidget {
  const HeroOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Mis pedidos',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (err, _) => _EmptyState(
          icon: Icons.error_outline,
          title: 'No pudimos cargar tu perfil',
          message: err.toString(),
        ),
        data: (user) {
          if (user == null) {
            return const _EmptyState(
              icon: Icons.login,
              title: 'Inicia sesión',
              message: 'Necesitas iniciar sesión para ver tus pedidos.',
            );
          }

          final ordersAsync = ref.watch(myOrdersProvider(user.id));
          return ordersAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
            error: (err, _) => _EmptyState(
              icon: Icons.error_outline,
              title: 'No pudimos cargar tus pedidos',
              message: err.toString(),
            ),
            data: (orders) {
              if (orders.isEmpty) {
                return const _EmptyState(
                  icon: Icons.receipt_long,
                  title: 'Aún no tienes pedidos',
                  message: 'Cuando compres, podrás seguirlos desde aquí.',
                );
              }

              final sorted = [...orders]
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

              final active = sorted
                  .where((o) => !o.status.isCompleted)
                  .toList();
              final completed = sorted
                  .where((o) => o.status.isCompleted)
                  .toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (active.isNotEmpty) ...[
                    const Text(
                      'Activos',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...active.map((o) => _OrderTile(order: o)),
                    const SizedBox(height: 18),
                  ],
                  if (completed.isNotEmpty) ...[
                    const Text(
                      'Completados',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...completed.map((o) => _OrderTile(order: o)),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  final Order order;

  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentAsync = ref.watch(watchPaymentByOrderIdProvider(order.orderId));
    final payment = paymentAsync.asData?.value;
    final isPaymentApproved = payment?.status == PaymentStatus.approved;
    final isCashPayment = payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');

    final statusColor = _statusColor(order.status);
    final statusBg = _statusBg(order.status);
    final shortId = order.orderId.length > 8
        ? order.orderId.substring(0, 8)
        : order.orderId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HeroOrderStatusScreen(orderId: order.orderId),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Colored header band ─────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _statusIcon(order.status),
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.status.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                          ),
                        ),
                        Text(
                          'HRO-$shortId',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${order.amountTotal.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            // ── Body: address + items + rider ──────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.delivery.addressSnapshot.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: textGray600.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.delivery.addressSnapshot,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textGray600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (order.delivery.addressSnapshot.isNotEmpty)
                    const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 14,
                        color: textGray600.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${order.totalItems} producto${order.totalItems == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textGray600,
                        ),
                      ),
                      if (order.rider.isAssigned &&
                          (order.rider.riderNameSnapshot?.isNotEmpty ??
                              false)) ...[
                        const SizedBox(width: 10),
                        Icon(
                          Icons.delivery_dining,
                          size: 14,
                          color: primaryOrange.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.rider.riderNameSnapshot!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: primaryOrange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Show payment and delete buttons for pending payment orders
                  if (order.status == OrderStatus.pendingPayment) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                // Create payment preference
                                final paymentNotifier = ref.read(
                                  paymentNotifierProvider.notifier,
                                );
                                await paymentNotifier.createPreference(order);

                                final paymentState = ref.read(
                                  paymentNotifierProvider,
                                );

                                if (paymentState.error != null) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error: ${paymentState.error}',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                if (paymentState.initPoint != null &&
                                    context.mounted) {
                                  // Navigate to payment processing screen
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PaymentProcessingScreen(
                                        initPoint: paymentState.initPoint!,
                                        orderId: order.orderId,
                                        preferenceId:
                                            paymentState.preferenceId ?? '',
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error al procesar pago: $e',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.payment, size: 18),
                            label: const Text(
                              'Pagar',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              // Show confirmation dialog
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  icon: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.red,
                                    size: 48,
                                  ),
                                  title: const Text(
                                    'Eliminar orden',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  content: const Text(
                                    '¿Eliminar esta orden pendiente? Esta acción no se puede deshacer.',
                                    textAlign: TextAlign.center,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text(
                                        'Eliminar',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true && context.mounted) {
                                try {
                                  // Restore stock for all items in the order
                                  // Delete order from Firestore
                                  final db =
                                      firestore.FirebaseFirestore.instance;

                                  await db.runTransaction((tx) async {
                                    final orderRef = db
                                        .collection('orders')
                                        .doc(order.orderId);
                                    final reservationRef = db
                                        .collection('stockReservations')
                                        .doc(order.orderId);

                                    // 1. READ: Get reservation
                                    final reservationSnap = await tx.get(
                                      reservationRef,
                                    );

                                    // Map to store offer snapshots: offerId -> DocumentSnapshot
                                    final offerSnaps =
                                        <String, firestore.DocumentSnapshot>{};
                                    List<dynamic>? itemsRaw;

                                    if (reservationSnap.exists) {
                                      final data = reservationSnap.data();
                                      final status = data?['status'] as String?;
                                      itemsRaw =
                                          data?['items'] as List<dynamic>?;

                                      if (status == 'reserved' &&
                                          itemsRaw != null) {
                                        // 2. READ: Get all offers related to this reservation
                                        for (final raw in itemsRaw) {
                                          if (raw is! Map) continue;
                                          final offerId =
                                              raw['offerId'] as String?;
                                          if (offerId == null ||
                                              offerId.isEmpty) {
                                            continue;
                                          }

                                          // Avoid reading the same doc twice
                                          if (!offerSnaps.containsKey(
                                            offerId,
                                          )) {
                                            final offerRef = db
                                                .collection('offers')
                                                .doc(offerId);
                                            final offerSnap = await tx.get(
                                              offerRef,
                                            );
                                            offerSnaps[offerId] = offerSnap;
                                          }
                                        }
                                      }
                                    }

                                    // 3. WRITE: Perform all updates
                                    if (reservationSnap.exists &&
                                        itemsRaw != null) {
                                      final data = reservationSnap.data();
                                      final status = data?['status'] as String?;

                                      if (status == 'reserved') {
                                        for (final raw in itemsRaw) {
                                          if (raw is! Map) continue;
                                          final offerId =
                                              raw['offerId'] as String?;
                                          final qty = raw['qty'] as int?;

                                          if (offerId == null ||
                                              !offerSnaps.containsKey(
                                                offerId,
                                              )) {
                                            continue;
                                          }

                                          final qtyInt =
                                              (qty == null || qty <= 0)
                                              ? 1
                                              : qty;
                                          final offerSnap =
                                              offerSnaps[offerId]!;

                                          if (!offerSnap.exists) continue;

                                          final offerData =
                                              offerSnap.data()
                                                  as Map<String, dynamic>?;
                                          final currentQty =
                                              (offerData?['availableQty']
                                                  as int?) ??
                                              0;
                                          final newQty = currentQty + qtyInt;
                                          final currentStatus =
                                              offerData?['status'] as String?;

                                          final update = <String, Object?>{
                                            'availableQty': newQty,
                                            'updatedAt': firestore
                                                .FieldValue.serverTimestamp(),
                                          };

                                          if (currentStatus == 'sold_out' &&
                                              newQty > 0) {
                                            update['status'] = 'active';
                                          }

                                          tx.update(
                                            offerSnap.reference,
                                            update,
                                          );
                                        }

                                        tx.update(reservationRef, {
                                          'status': 'released',
                                          'releasedAt': firestore
                                              .FieldValue.serverTimestamp(),
                                        });
                                      }
                                    }

                                    // 4. WRITE: Delete order
                                    tx.delete(orderRef);
                                  });

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Orden eliminada'),
                                        backgroundColor: categoryTextGreen,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text(
                              'Eliminar',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (order.status != OrderStatus.pendingPayment &&
                      (isPaymentApproved || isCashPayment)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrderReceiptScreen(orderId: order.orderId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text(
                          'Ver boleta',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryOrange,
                          side: const BorderSide(color: primaryOrange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.queued:
      case OrderStatus.pendingPayment:
      case OrderStatus.paid:
        return Icons.schedule;
      case OrderStatus.assigned:
        return Icons.check_circle_outline;
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return Icons.local_shipping_outlined;
      case OrderStatus.delivered:
        return Icons.task_alt;
      case OrderStatus.canceled:
        return Icons.cancel_outlined;
      case OrderStatus.failed:
        return Icons.error_outline;
    }
  }

  static Color _statusBg(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return const Color(0xFFD1FAE5);
      case OrderStatus.canceled:
      case OrderStatus.failed:
        return const Color(0xFFFEE2E2);
      case OrderStatus.assigned:
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return const Color(0xFFFFEDD5);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return categoryTextGreen;
      case OrderStatus.canceled:
      case OrderStatus.failed:
        return const Color(0xFFDC2626);
      case OrderStatus.assigned:
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return primaryOrange;
      default:
        return textGray600;
    }
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 34, color: primaryOrange),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textGray600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

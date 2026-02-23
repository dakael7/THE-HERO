import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/payment_processing_screen.dart';
import '../../../payment/providers/payment_providers.dart';
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
    final title = 'Pedido HRO-${order.orderId}';

    final statusColor = _statusColor(order.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_statusIcon(order.status), color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.delivery.addressSnapshot,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textGray600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          order.status.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '\$${order.amountTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textGray900,
                        ),
                      ),
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

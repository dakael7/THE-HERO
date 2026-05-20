import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../billing/domain/entities/invoice_entity.dart';
import '../../../../billing/presentation/providers/billing_providers.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/payment_processing_screen.dart';
import '../../../payment/providers/payment_providers.dart';
import '../../../presentation/views/hero_home_screen.dart';
import 'order_receipt_screen.dart';
import 'hero_order_status_screen.dart';

class HeroOrdersScreen extends ConsumerWidget {
  const HeroOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Mis pedidos',
        icon: Icons.receipt_long_rounded,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HeroHomeScreen()),
            (route) => false,
          );
        },
      ),
      body: userId == null
          ? const _EmptyState(
              icon: Icons.login,
              title: 'Inicia sesión',
              message: 'Necesitas iniciar sesión para ver tus pedidos.',
            )
          : Builder(
              builder: (context) {
                final uid = userId!;
                final ordersAsync = ref.watch(myOrdersProvider(uid));
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
                      ..sort(
                        (a, b) {
                          final byDate = b.timestamps.createdAt.compareTo(
                            a.timestamps.createdAt,
                          );
                          if (byDate != 0) return byDate;
                          return b.orderId.compareTo(a.orderId);
                        },
                      );

                    return RefreshIndicator(
                      color: primaryOrange,
                      onRefresh: () async {
                        ref.invalidate(myOrdersProvider(uid));
                        await Future<void>.delayed(
                          const Duration(milliseconds: 250),
                        );
                      },
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          return _OrderTile(order: sorted[index]);
                        },
                      ),
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
    final paymentState = ref.watch(paymentNotifierProvider);
    final isPayingOrder = paymentState.isProcessing;
    final isFactura = order.isFactura;
    final canShowReceipt = order.status != OrderStatus.created &&
        order.status != OrderStatus.pendingPayment &&
        order.status != OrderStatus.canceled &&
        order.status != OrderStatus.failed;

    final statusColor = _statusColor(order.status);
    final statusBg = _statusBg(order.status);
    final shortId = order.orderId.length > 8
        ? order.orderId.substring(0, 8)
        : order.orderId;
    final createdAtText = _formatCreatedAt(order.timestamps.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
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
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TileHeader(
              order: order,
              statusBg: statusBg,
              statusColor: statusColor,
              shortId: shortId,
            ),
            Container(
              height: 1,
              color: borderGray100,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    iconColor: textGray600,
                    text: 'Fecha: $createdAtText',
                  ),
                  const SizedBox(height: 6),
                  if (order.delivery.addressSnapshot.isNotEmpty) ...[
                    _InfoRow(
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFF2563EB),
                      text: order.delivery.addressSnapshot,
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      _InfoRow(
                        icon: Icons.shopping_bag_outlined,
                        iconColor: textGray600,
                        text:
                            '${order.totalItems} producto${order.totalItems == 1 ? '' : 's'}',
                      ),
                      if (order.rider.isAssigned &&
                          (order.rider.riderNameSnapshot?.isNotEmpty ??
                              false)) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _InfoRow(
                            icon: Icons.delivery_dining_rounded,
                            iconColor: primaryOrange,
                            text: '${order.rider.riderNameSnapshot!} (Rider)',
                            textColor: primaryOrange,
                            fontWeight: FontWeight.w700,
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
                            onPressed: isPayingOrder ? null : () async {
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
                                  final errorCode =
                                      (paymentState.errorCode ?? '').toLowerCase();
                                  final raw = paymentState.error ?? '';
                                  final message = raw.toLowerCase();
                                  String userMessage = 'Error: $raw';

                                  if (errorCode == 'resource-exhausted') {
                                    userMessage =
                                        'Hay mucha demanda en este momento. Espera 30 segundos y vuelve a intentar.';
                                  } else if (message.contains('stock insuficiente') ||
                                      message.contains('failed-precondition')) {
                                    userMessage =
                                        'Este servicio ya no está disponible. Intenta con otro.';
                                  }

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(userMessage),
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
                                } else if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No se pudo obtener el link de pago',
                                      ),
                                      backgroundColor: Colors.red,
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
                            label: Text(
                              isPayingOrder ? 'Procesando...' : 'Pagar',
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

                  if (canShowReceipt && !isFactura) ...[
                    const SizedBox(height: 12),
                    _ReceiptButton(orderId: order.orderId),
                  ],
                  if (canShowReceipt && isFactura) ...[
                    const SizedBox(height: 12),
                    _InvoiceAction(order: order),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCreatedAt(DateTime createdAt) {
    final local = createdAt.toLocal();
    return DateFormat('dd/MM/yyyy HH:mm').format(local);
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

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: textGray900,
            fontSize: 16,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _TileHeader extends StatelessWidget {
  final Order order;
  final Color statusBg;
  final Color statusColor;
  final String shortId;

  const _TileHeader({
    required this.order,
    required this.statusBg,
    required this.statusColor,
    required this.shortId,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            color: statusBg,
          ),
          Positioned(
            top: -4,
            right: 10,
            child: Text(
              'HERO',
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
                height: 1,
                color: statusColor.withValues(alpha: 0.08),
                fontFamily: 'Arial',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _OrderTile._statusIcon(order.status),
                    color: statusColor,
                    size: 22,
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
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'HRO-$shortId',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: statusColor.withValues(alpha: 0.75),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _PriceTag(
                  amount: order.amountTotal,
                  statusColor: statusColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final double amount;
  final Color statusColor;

  const _PriceTag({
    required this.amount,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '\$${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: statusColor,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
        Text(
          'CLP',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: statusColor.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color? textColor;
  final FontWeight? fontWeight;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.textColor,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 12, color: iconColor),
        ),
        const SizedBox(width: 6),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: fontWeight ?? FontWeight.w600,
              color: textColor ?? textGray600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptButton extends StatelessWidget {
  final String orderId;
  const _ReceiptButton({required this.orderId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderReceiptScreen(orderId: orderId),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: backgroundGray50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryOrange.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_rounded, size: 15, color: primaryOrange),
            SizedBox(width: 7),
            Text(
              'Ver boleta',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: primaryOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceAction extends ConsumerWidget {
  final Order order;

  const _InvoiceAction({required this.order});

  String _statusLabel(BillingInvoiceStatus status) {
    switch (status) {
      case BillingInvoiceStatus.pending:
        return 'Factura en proceso';
      case BillingInvoiceStatus.issued:
        return 'Factura emitida';
      case BillingInvoiceStatus.failed:
        return 'Error al emitir factura';
      case BillingInvoiceStatus.canceled:
        return 'Factura anulada';
      case BillingInvoiceStatus.unknown:
        return 'Factura pendiente';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByOrderIdProvider(order.orderId));

    return invoiceAsync.when(
      loading: () => const _InfoInvoiceBanner(
        icon: Icons.hourglass_top_rounded,
        text: 'Buscando factura de este pedido...',
      ),
      error: (_, _) => const _InfoInvoiceBanner(
        icon: Icons.receipt_long_rounded,
        text: 'Factura pendiente de emisión',
      ),
      data: (invoice) {
        if (invoice == null) {
          return const _InfoInvoiceBanner(
            icon: Icons.receipt_long_rounded,
            text: 'Factura pendiente de emisión',
          );
        }

        if (!invoice.isIssued || !invoice.hasPdf) {
          final banner = _InfoInvoiceBanner(
            icon: invoice.status == BillingInvoiceStatus.failed
                ? Icons.error_outline_rounded
                : Icons.receipt_long_rounded,
            text: _statusLabel(invoice.status),
            color: invoice.status == BillingInvoiceStatus.failed
                ? const Color(0xFFB91C1C)
                : textGray700,
          );

          if (invoice.status == BillingInvoiceStatus.failed) {
            return Column(
              children: [
                banner,
                const SizedBox(height: 8),
                _RetryInvoiceButton(invoiceId: invoice.invoiceId),
              ],
            );
          }

          return banner;
        }

        return _InvoiceButton(invoiceId: invoice.invoiceId);
      },
    );
  }
}

class _InfoInvoiceBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoInvoiceBanner({
    required this.icon,
    required this.text,
    this.color = textGray700,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundGray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderGray100),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceButton extends ConsumerStatefulWidget {
  final String invoiceId;

  const _InvoiceButton({required this.invoiceId});

  @override
  ConsumerState<_InvoiceButton> createState() => _InvoiceButtonState();
}

class _InvoiceButtonState extends ConsumerState<_InvoiceButton> {
  bool _isLoading = false;

  Future<void> _openInvoice() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    String? url;
    String? errorMessage;
    try {
      final useCase = ref.read(getInvoicePdfUrlUseCaseProvider);
      url = await useCase.execute(widget.invoiceId);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    if (!mounted) return;
    if (url == null || url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage?.trim().isNotEmpty == true
                ? 'No se pudo abrir la factura: $errorMessage'
                : 'No se pudo abrir la factura',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL de factura invalida'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el PDF de factura'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isLoading;

    return GestureDetector(
      onTap: isLoading ? null : _openInvoice,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: backgroundGray50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryOrange.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              const Icon(
                Icons.picture_as_pdf_rounded,
                size: 15,
                color: primaryOrange,
              ),
              const SizedBox(width: 7),
            ],
            Text(
              isLoading ? 'Abriendo factura...' : 'Ver factura',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: primaryOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryInvoiceButton extends ConsumerStatefulWidget {
  final String invoiceId;

  const _RetryInvoiceButton({required this.invoiceId});

  @override
  ConsumerState<_RetryInvoiceButton> createState() => _RetryInvoiceButtonState();
}

class _RetryInvoiceButtonState extends ConsumerState<_RetryInvoiceButton> {
  bool _isRetrying = false;

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);

    String? errorMessage;
    try {
      final useCase = ref.read(retryInvoiceEmissionUseCaseProvider);
      await useCase.execute(widget.invoiceId);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }

    if (!mounted) return;
    if (errorMessage != null && errorMessage.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo reintentar: $errorMessage'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reintento solicitado. Estamos generando la factura.'),
        backgroundColor: categoryTextGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isRetrying ? null : _retry,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isRetrying) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              const Icon(
                Icons.refresh_rounded,
                size: 15,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              _isRetrying ? 'Reintentando...' : 'Reintentar generar',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFFB45309),
              ),
            ),
          ],
        ),
      ),
    );
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

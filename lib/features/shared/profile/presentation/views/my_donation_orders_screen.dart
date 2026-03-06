import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../../domain/entities/payment.dart';
import '../providers/profile_provider.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../hero/orders/presentation/views/seller_order_status_screen.dart';
import '../../../../hero/orders/presentation/views/order_receipt_screen.dart';
import '../../../../hero/payment/providers/payment_providers.dart';

class MyDonationOrdersScreen extends ConsumerWidget {
  const MyDonationOrdersScreen({super.key});

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
          'Pedidos de mis donaciones',
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
              message: 'Necesitas iniciar sesión para ver los pedidos.',
            );
          }

          final ordersAsync = ref.watch(myDonationOrdersProvider(user.id));
          return ordersAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
            error: (err, _) => _EmptyState(
              icon: Icons.error_outline,
              title: 'No pudimos cargar los pedidos',
              message: err.toString(),
            ),
            data: (orders) {
              final filtered = orders
                  .map((o) => _filterOrderItemsForSeller(o, user.id))
                  .where((o) => o.items.isNotEmpty)
                  .toList();

              if (filtered.isEmpty) {
                return const _EmptyState(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Aún no tienes pedidos',
                  message:
                      'Cuando alguien pida uno de tus artículos publicados, aparecerá aquí.',
                );
              }

              final sorted = [...filtered]
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
                    ...active.map(
                      (o) => _DonationOrderTile(order: o, sellerId: user.id),
                    ),
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
                    ...completed.map(
                      (o) => _DonationOrderTile(order: o, sellerId: user.id),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  static Order _filterOrderItemsForSeller(Order order, String sellerId) {
    final myItems = order.items
        .where((i) => i.sellerHeroIdSnapshot.trim() == sellerId)
        .toList();

    return order.copyWith(items: myItems);
  }
}

class _DonationOrderTile extends ConsumerWidget {
  final Order order;
  final String sellerId;

  const _DonationOrderTile({required this.order, required this.sellerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentAsync = ref.watch(watchPaymentByOrderIdProvider(order.orderId));
    final payment = paymentAsync.asData?.value;
    final isPaymentApproved = payment?.status == PaymentStatus.approved;

    final liveOrderAsync = ref.watch(orderByIdProvider(order.orderId));
    final baseOrder = liveOrderAsync.maybeWhen(
      data: (o) => o,
      orElse: () => null,
    );

    final effectiveOrder = baseOrder ?? order;

    final sellerItems = effectiveOrder.items
        .where((i) => i.sellerHeroIdSnapshot.trim() == sellerId)
        .toList();

    final statusColor = _statusColor(effectiveOrder.status);
    final statusBg = _statusBg(effectiveOrder.status);
    final shortId = effectiveOrder.orderId.length > 8
        ? effectiveOrder.orderId.substring(0, 8)
        : effectiveOrder.orderId;

    final buyerAsync = ref.watch(userByIdProvider(effectiveOrder.heroId));
    final buyerName = buyerAsync.maybeWhen(
      data: (u) => u?.fullName.trim().isNotEmpty == true ? u!.fullName : 'Hero',
      orElse: () => 'Hero',
    );

    final myItemsCount = sellerItems.fold<int>(
      0,
      (sum, item) => sum + item.qty,
    );
    final myAmount = sellerItems.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );

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
              builder: (_) => SellerOrderStatusScreen(
                orderId: order.orderId,
                sellerId: sellerId,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          effectiveOrder.status.displayName,
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
                    '\$${myAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 14,
                        color: textGray600.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Solicitado por: $buyerName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textGray600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: textGray600,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (effectiveOrder.delivery.addressSnapshot.isNotEmpty)
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
                            effectiveOrder.delivery.addressSnapshot,
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
                  if (effectiveOrder.delivery.addressSnapshot.isNotEmpty)
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
                        '$myItemsCount producto${myItemsCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textGray600,
                        ),
                      ),
                      if (effectiveOrder.rider.isAssigned &&
                          (effectiveOrder.rider.riderNameSnapshot?.isNotEmpty ??
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
                            effectiveOrder.rider.riderNameSnapshot!,
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

                  if (effectiveOrder.status != OrderStatus.pendingPayment &&
                      isPaymentApproved) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OrderReceiptScreen(
                                orderId: effectiveOrder.orderId,
                              ),
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

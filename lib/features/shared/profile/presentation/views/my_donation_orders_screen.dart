import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../providers/profile_provider.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../hero/orders/presentation/views/seller_order_status_screen.dart';
import '../../../../hero/orders/presentation/views/order_receipt_screen.dart';

// 
//  ROOT SCREEN
// 

class MyDonationOrdersScreen extends ConsumerWidget {
  const MyDonationOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: const HeroHeaderAppBar(
        title: 'Pedidos recibidos',
        icon: Icons.volunteer_activism_rounded,
      ),
      body: userId == null
          ? const _EmptyState(
              icon: Icons.login_rounded,
              title: 'Inicia sesión',
              message: 'Necesitas iniciar sesión para ver los pedidos.',
            )
          : Builder(
              builder: (context) {
                final uid = userId!;
                final ordersAsync = ref.watch(myDonationOrdersProvider(uid));
                return ordersAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: primaryOrange),
                  ),
                  error: (err, _) => _EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'No pudimos cargar los pedidos',
                    message: err.toString(),
                  ),
                  data: (orders) {
                    final filtered = orders
                        .map((o) => _filterOrderItemsForSeller(o, uid))
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
                        ref.invalidate(myDonationOrdersProvider(uid));
                        await Future<void>.delayed(
                          const Duration(milliseconds: 250),
                        );
                      },
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          return _DonationOrderTile(
                            order: sorted[index],
                            sellerId: uid,
                          );
                        },
                      ),
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

// 
//  SECTION HEADER
// 

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
        // Orange accent bar
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
          style: TextStyle(
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

// 
//  DONATION ORDER TILE
// 

class _DonationOrderTile extends StatelessWidget {
  final Order order;
  final String sellerId;

  const _DonationOrderTile({required this.order, required this.sellerId});

  @override
  Widget build(BuildContext context) {
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

    final buyerName = 'Hero';

    final myItemsCount = order.items.fold<int>(0, (sum, item) => sum + item.qty);
    final myAmount =
        order.items.fold<double>(0, (sum, item) => sum + item.totalPrice);

    final hasRider = order.rider.isAssigned &&
        (order.rider.riderNameSnapshot?.isNotEmpty ?? false);

    final hasAddress = order.delivery.addressSnapshot.isNotEmpty;

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
              builder: (_) => SellerOrderStatusScreen(
                orderId: order.orderId,
                sellerId: sellerId,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //  Colored header 
            _TileHeader(
              effectiveOrder: order,
              statusBg: statusBg,
              statusColor: statusColor,
              shortId: shortId,
              myAmount: myAmount,
              hasBuyerPhoto: false,
              buyerPhotoUrl: null,
            ),

            Container(
              height: 1,
              color: borderGray100,
            ),

            //  Body 
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
                  // Buyer row
                  _InfoRow(
                    icon: Icons.person_rounded,
                    iconColor: textGray600,
                    text: 'Solicitado por: $buyerName',
                    trailing: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: backgroundGray50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: textGray600,
                        size: 18,
                      ),
                    ),
                  ),

                  // Address row
                  if (hasAddress) ...[
                    const SizedBox(height: 6),
                    _InfoRow(
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFF2563EB),
                      text: order.delivery.addressSnapshot,
                    ),
                  ],

                  const SizedBox(height: 6),

                  // Items + rider row
                  Row(
                    children: [
                      _InfoRow(
                        icon: Icons.shopping_bag_outlined,
                        iconColor: textGray600,
                        text:
                            '$myItemsCount producto${myItemsCount == 1 ? '' : 's'}',
                      ),
                      if (hasRider) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _InfoRow(
                            icon: Icons.delivery_dining_rounded,
                            iconColor: primaryOrange,
                            text: order.rider.riderNameSnapshot!,
                            textColor: primaryOrange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Receipt button
                  if (canShowReceipt) ...[
                    const SizedBox(height: 12),
                    _ReceiptButton(orderId: order.orderId),
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

// 
//  TILE HEADER  (colored top band with decorative HERO text)
// 

class _TileHeader extends StatelessWidget {
  final Order effectiveOrder;
  final Color statusBg;
  final Color statusColor;
  final String shortId;
  final double myAmount;
  final bool hasBuyerPhoto;
  final String? buyerPhotoUrl;

  const _TileHeader({
    required this.effectiveOrder,
    required this.statusBg,
    required this.statusColor,
    required this.shortId,
    required this.myAmount,
    required this.hasBuyerPhoto,
    required this.buyerPhotoUrl,
  });

  static IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.queued:
      case OrderStatus.pendingPayment:
      case OrderStatus.paid:
        return Icons.schedule_rounded;
      case OrderStatus.assigned:
        return Icons.check_circle_outline_rounded;
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return Icons.local_shipping_rounded;
      case OrderStatus.delivered:
        return Icons.task_alt_rounded;
      case OrderStatus.canceled:
        return Icons.cancel_rounded;
      case OrderStatus.failed:
        return Icons.error_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(22)),
      child: Stack(
        children: [
          // Background
          Container(
            width: double.infinity,
            color: statusBg,
          ),

          //  Decorative "HERO" watermark  top-right 
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

          //  Actual content 
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                // Status icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _statusIcon(effectiveOrder.status),
                    color: statusColor,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 10),

                // Buyer avatar
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasBuyerPhoto
                      ? Image.network(
                          buyerPhotoUrl!.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.person_rounded,
                              color: primaryOrange,
                              size: 19,
                            );
                          },
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: primaryOrange,
                          size: 19,
                        ),
                ),

                const SizedBox(width: 10),

                // Status label + order ID
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
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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

                // â”€â”€ Price + HERO decorative text â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                _PriceWithHero(
                  amount: myAmount,
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  PRICE WIDGET with "HERO" decorative text behind it
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PriceWithHero extends StatelessWidget {
  final double amount;
  final Color statusColor;

  const _PriceWithHero({
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

// 
//  INFO ROW  â€” icon + text utility
// 

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color? textColor;
  final FontWeight? fontWeight;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.textColor,
    this.fontWeight,
    this.trailing,
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
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing!,
        ],
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  RECEIPT BUTTON
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  EMPTY STATE
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 36, color: primaryOrange),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: textGray900,
                letterSpacing: -0.2,
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
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

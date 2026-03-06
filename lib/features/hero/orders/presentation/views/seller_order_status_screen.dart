import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/config/env.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_type.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_item.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../../domain/entities/payment.dart';
import '../../../../../data/providers/network_providers.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../../shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/providers/payment_providers.dart';
import 'order_receipt_screen.dart';

class SellerOrderStatusScreen extends ConsumerWidget {
  final String orderId;
  final String sellerId;

  const SellerOrderStatusScreen({
    super.key,
    required this.orderId,
    required this.sellerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderByIdProvider(orderId));

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Detalle del pedido',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: orderAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (err, _) => _StatusMessage(
          title: 'No pudimos obtener el pedido',
          subtitle: err.toString(),
        ),
        data: (order) {
          if (order == null) {
            return const _StatusMessage(
              title: 'Buscando el pedido…',
              subtitle:
                  'Espera unos segundos mientras sincronizamos el estado.',
            );
          }

          final myItems = order.items
              .where((i) => i.sellerHeroIdSnapshot.trim() == sellerId)
              .toList();

          return _SellerOrderContent(
            order: order,
            myItems: myItems,
            sellerId: sellerId,
          );
        },
      ),
    );
  }
}

class _SellerOrderContent extends ConsumerWidget {
  final Order order;
  final List<OrderItem> myItems;
  final String sellerId;

  const _SellerOrderContent({
    required this.order,
    required this.myItems,
    required this.sellerId,
  });

  static _StatusConfig _config(Order order) {
    final status = order.status;

    if (order.inPersonPickup) {
      switch (status) {
        case OrderStatus.created:
        case OrderStatus.queued:
        case OrderStatus.pendingPayment:
        case OrderStatus.paid:
          return _StatusConfig(
            color: const Color(0xFFD97706),
            bg: const Color(0xFFFEF3C7),
            icon: Icons.store_rounded,
            label: 'Coordinando retiro',
          );
        case OrderStatus.assigned:
          return _StatusConfig(
            color: primaryOrange,
            bg: const Color(0xFFFFEDD5),
            icon: Icons.handshake_outlined,
            label: 'Retiro coordinado',
          );
        case OrderStatus.pickedUp:
        case OrderStatus.inTransit:
          return _StatusConfig(
            color: primaryOrange,
            bg: const Color(0xFFFFEDD5),
            icon: Icons.inventory_2_rounded,
            label: 'Pedido listo para retiro',
          );
        case OrderStatus.delivered:
          return _StatusConfig(
            color: categoryTextGreen,
            bg: const Color(0xFFD1FAE5),
            icon: Icons.check_circle_rounded,
            label: '¡Retiro completado!',
          );
        case OrderStatus.canceled:
          return _StatusConfig(
            color: const Color(0xFFDC2626),
            bg: const Color(0xFFFEE2E2),
            icon: Icons.cancel_rounded,
            label: 'Pedido cancelado',
          );
        case OrderStatus.failed:
          return _StatusConfig(
            color: const Color(0xFFDC2626),
            bg: const Color(0xFFFEE2E2),
            icon: Icons.error_rounded,
            label: 'Pedido fallido',
          );
      }
    }

    switch (status) {
      case OrderStatus.created:
      case OrderStatus.queued:
      case OrderStatus.pendingPayment:
      case OrderStatus.paid:
        return _StatusConfig(
          color: const Color(0xFFD97706),
          bg: const Color(0xFFFEF3C7),
          icon: Icons.hourglass_top_rounded,
          label: 'Esperando rider',
        );
      case OrderStatus.assigned:
        return _StatusConfig(
          color: primaryOrange,
          bg: const Color(0xFFFFEDD5),
          icon: Icons.delivery_dining,
          label: 'Rider asignado',
        );
      case OrderStatus.pickedUp:
        return _StatusConfig(
          color: primaryOrange,
          bg: const Color(0xFFFFEDD5),
          icon: Icons.inventory_2_rounded,
          label: 'Pedido recogido',
        );
      case OrderStatus.inTransit:
        return _StatusConfig(
          color: const Color(0xFF2563EB),
          bg: const Color(0xFFDBEAFE),
          icon: Icons.local_shipping_rounded,
          label: 'En camino',
        );
      case OrderStatus.delivered:
        return _StatusConfig(
          color: categoryTextGreen,
          bg: const Color(0xFFD1FAE5),
          icon: Icons.check_circle_rounded,
          label: '¡Pedido entregado!',
        );
      case OrderStatus.canceled:
        return _StatusConfig(
          color: const Color(0xFFDC2626),
          bg: const Color(0xFFFEE2E2),
          icon: Icons.cancel_rounded,
          label: 'Pedido cancelado',
        );
      case OrderStatus.failed:
        return _StatusConfig(
          color: const Color(0xFFDC2626),
          bg: const Color(0xFFFEE2E2),
          icon: Icons.error_rounded,
          label: 'Pedido fallido',
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = order.status;
    final cfg = _config(order);
    final hasRider =
        order.rider.isAssigned &&
        (order.rider.riderNameSnapshot?.isNotEmpty ?? false);

    final canMarkReadyForPickup =
        order.inPersonPickup &&
        status != OrderStatus.delivered &&
        status != OrderStatus.canceled &&
        status != OrderStatus.failed &&
        status != OrderStatus.pickedUp &&
        status != OrderStatus.inTransit;

    final canMarkDelivered =
        order.inPersonPickup &&
        status != OrderStatus.delivered &&
        status != OrderStatus.canceled &&
        status != OrderStatus.failed &&
        (status == OrderStatus.pickedUp || status == OrderStatus.inTransit);

    final paymentAsync = ref.watch(watchPaymentByOrderIdProvider(order.orderId));
    final payment = paymentAsync.asData?.value;
    final isPaymentApproved = payment?.status == PaymentStatus.approved;
    final isCashPayment = payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final canShowReceipt =
        status != OrderStatus.pendingPayment && (isPaymentApproved || isCashPayment);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cfg.color.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: cfg.bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: cfg.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(cfg.icon, color: cfg.color, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cfg.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: cfg.color,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'HRO-${order.orderId.length > 8 ? order.orderId.substring(0, 8) : order.orderId}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cfg.color.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SellerChatActions(order: order, sellerId: sellerId),
                    if (canShowReceipt) ...[
                      const SizedBox(height: 10),
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
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
              // Timeline
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: _OrderStatusTimeline(
                  status: status,
                  inPersonPickup: order.inPersonPickup,
                ),
              ),

              if (canMarkReadyForPickup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await ref
                              .read(orderNotifierProvider.notifier)
                              .updateStatus(order.orderId, 'picked_up');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Marcado como listo para retiro'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No se pudo actualizar: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.inventory_2_rounded, size: 18),
                      label: const Text(
                        'Marcar listo para retiro',
                        style: TextStyle(fontWeight: FontWeight.w900),
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
                ),

              if (canMarkDelivered)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await ref
                              .read(orderNotifierProvider.notifier)
                              .updateStatus(order.orderId, 'delivered');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Pedido marcado como entregado'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No se pudo actualizar: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'Marcar como entregado',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: categoryTextGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              // Rider pill (if assigned)
              if (hasRider && !order.inPersonPickup)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: primaryOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primaryOrange.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.delivery_dining,
                          color: primaryOrange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            order.rider.riderNameSnapshot ?? 'Rider',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: primaryOrange,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Details
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    _iconRow(
                      Icons.payments_rounded,
                      categoryTextGreen,
                      'Mis artículos',
                      '\$${myItems.fold(0.0, (s, i) => s + i.totalPrice).toStringAsFixed(0)}',
                    ),
                    const SizedBox(height: 10),
                    if (!order.inPersonPickup) ...[
                      _iconRow(
                        Icons.location_on_rounded,
                        const Color(0xFF2563EB),
                        'Entrega',
                        order.delivery.addressSnapshot.isNotEmpty
                            ? order.delivery.addressSnapshot
                            : 'Sin dirección',
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 42),
                        child: _PlusCodeText(
                          snapshot: order.delivery.addressSnapshot,
                          geo: order.delivery.geo,
                          style: const TextStyle(
                            fontSize: 11,
                            color: textGray600,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── My items card ───────────────────────────────────────────────
        _MyItemsCard(myItems: myItems),
      ],
    );
  }

  Widget _iconRow(IconData icon, Color iconColor, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textGray600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My items card (filtered to seller's items only)
// ─────────────────────────────────────────────────────────────────────────────

class _MyItemsCard extends StatelessWidget {
  final List<OrderItem> myItems;
  const _MyItemsCard({required this.myItems});

  @override
  Widget build(BuildContext context) {
    if (myItems.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.volunteer_activism_outlined,
                    color: primaryOrange,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Mis artículos (${myItems.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: textGray900,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: borderGray100),
          ...myItems.map((item) => _ItemRow(item: item)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final OrderItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: borderGray100, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.volunteer_activism_outlined,
              color: primaryOrange,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.titleSnapshot,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
                if (item.qty > 1)
                  Text(
                    'x${item.qty}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textGray600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${item.totalPrice.toStringAsFixed(0)}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: textGray900,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat actions for seller: rider chip + buyer chip
// ─────────────────────────────────────────────────────────────────────────────

class _SellerChatActions extends ConsumerWidget {
  final Order order;
  final String sellerId;

  const _SellerChatActions({required this.order, required this.sellerId});

  Widget _buildChipWithUnread({
    required WidgetRef ref,
    required String chatId,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final currentUserId = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final chatAsync = ref.watch(chatByIdProvider(chatId));

    final badgeCount = chatAsync.maybeWhen(
      data: (chat) {
        if (chat == null) return 0;
        if (currentUserId == null) return 0;
        if (chat.unreadCount <= 0) return 0;
        if ((chat.lastMessageSenderId ?? '').trim() == currentUserId) return 0;
        return chat.unreadCount;
      },
      orElse: () => 0,
    );

    return _ChatChipButton(
      icon: icon,
      label: label,
      badgeCount: badgeCount,
      onTap: onTap,
    );
  }

  Future<void> _openRiderChat(NavigatorState navigator, WidgetRef ref) async {
    if (!order.rider.isAssigned) return;
    final riderId = order.rider.assignedRiderId;
    if (riderId == null || riderId.isEmpty) return;

    final seller = ref.read(profileProvider).value;
    if (seller == null) return;

    // Await both names to guarantee real data
    final riderUser = await ref.read(userByIdProvider(riderId).future);
    final riderName = (riderUser?.fullName.trim().isNotEmpty ?? false)
        ? riderUser!.fullName
        : (order.rider.riderNameSnapshot ?? 'Rider');

    final newChatId = Chat.generateChatId(
      type: ChatType.heroRider,
      buyerId: sellerId,
      riderId: riderId,
      orderId: order.orderId,
    );

    final chatId = newChatId;
    final chat = Chat(
      chatId: chatId,
      type: ChatType.heroRider,
      buyerId: sellerId,
      buyerName: seller.fullName,
      riderId: riderId,
      riderName: riderName,
      orderId: order.orderId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(chatActionsProvider).ensureChatExists(chat);
    if (!navigator.mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
    );
  }

  Future<void> _openBuyerChat(
    NavigatorState navigator,
    WidgetRef ref,
    String buyerNameFallback,
  ) async {
    final seller = ref.read(profileProvider).value;
    if (seller == null) return;

    // Find any offer from this seller to use as offerId
    final myOffer = order.items.firstWhere(
      (i) => i.sellerHeroIdSnapshot.trim() == sellerId,
      orElse: () => order.items.first,
    );

    final chatId = Chat.generateChatId(
      type: ChatType.heroSeller,
      buyerId: order.heroId,
      sellerId: sellerId,
      offerId: myOffer.offerId,
    );

    String resolvedBuyerName = buyerNameFallback;
    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get();
      if (chatDoc.exists) {
        final stored = chatDoc.data()?['buyerName'] as String?;
        const genericNames = {'Hero', 'Comprador', 'Cliente', ''};
        if (stored != null && !genericNames.contains(stored.trim())) {
          resolvedBuyerName = stored;
        }
      }
    } catch (_) {
      final buyerUser = await ref
          .read(userByIdProvider(order.heroId).future)
          .catchError((_) => null);
      if (buyerUser?.fullName.trim().isNotEmpty == true) {
        resolvedBuyerName = buyerUser!.fullName;
      }
    }

    final chat = Chat(
      chatId: chatId,
      type: ChatType.heroSeller,
      buyerId: order.heroId,
      buyerName: resolvedBuyerName,
      sellerId: sellerId,
      orderId: order.orderId,
      offerId: myOffer.offerId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(chatActionsProvider).ensureChatExists(chat);
    if (!navigator.mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRider =
        order.rider.isAssigned &&
        (order.rider.assignedRiderId?.isNotEmpty ?? false);
    final riderName = order.rider.riderNameSnapshot ?? 'Rider';

    final currentUserId = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final sellerChatsAsync = ref.watch(userChatsProvider);
    final buyerBadgeCount = sellerChatsAsync.maybeWhen(
      data: (chats) {
        if (currentUserId == null) return 0;
        final matching = chats.where(
          (c) =>
              c.type == ChatType.heroSeller &&
              (c.orderId ?? '').trim() == order.orderId.trim() &&
              (c.sellerId ?? '').trim() == sellerId.trim(),
        );

        var maxUnread = 0;
        for (final c in matching) {
          if (c.unreadCount <= 0) continue;
          if ((c.lastMessageSenderId ?? '').trim() == currentUserId) continue;
          if (c.unreadCount > maxUnread) maxUnread = c.unreadCount;
        }
        return maxUnread;
      },
      orElse: () => 0,
    );

    // Resolve buyer name
    final buyerAsync = ref.watch(userByIdProvider(order.heroId));
    final buyerName = buyerAsync.maybeWhen(
      data: (u) => u?.fullName ?? 'Comprador',
      orElse: () => 'Comprador',
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasRider) ...[
          _buildChipWithUnread(
            ref: ref,
            chatId: Chat.generateChatId(
              type: ChatType.heroRider,
              buyerId: sellerId,
              riderId: order.rider.assignedRiderId,
              orderId: order.orderId,
            ),
            icon: Icons.delivery_dining,
            label: riderName,
            onTap: () => _openRiderChat(Navigator.of(context), ref),
          ),
          const SizedBox(width: 6),
        ],
        _ChatChipButton(
          icon: Icons.person_rounded,
          label: buyerName,
          badgeCount: buyerBadgeCount,
          onTap: () => _openBuyerChat(Navigator.of(context), ref, buyerName),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: chip button
// ─────────────────────────────────────────────────────────────────────────────

class _ChatChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;

  const _ChatChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = badgeCount > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBadge) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 16),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(icon, size: 14, color: primaryOrange),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textGray900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline (same as buyer's — reused)
// ─────────────────────────────────────────────────────────────────────────────

class _OrderStatusTimeline extends StatelessWidget {
  final OrderStatus status;
  final bool inPersonPickup;
  const _OrderStatusTimeline({
    required this.status,
    required this.inPersonPickup,
  });

  int _activeIndex() {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.queued:
      case OrderStatus.pendingPayment:
      case OrderStatus.paid:
        return 0;
      case OrderStatus.assigned:
        return 1;
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return 2;
      case OrderStatus.delivered:
        return 3;
      case OrderStatus.canceled:
      case OrderStatus.failed:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex();

    if (inPersonPickup) {
      return Column(
        children: [
          _step(
            title: 'En espera',
            subtitle: 'Coordina el retiro por chat',
            index: 0,
            activeIndex: active,
          ),
          _connector(active >= 1),
          _step(
            title: 'Coordinado',
            subtitle: 'Retiro coordinado con el comprador',
            index: 1,
            activeIndex: active,
          ),
          _connector(active >= 2),
          _step(
            title: 'Listo',
            subtitle: 'Deja listo el pedido para retiro',
            index: 2,
            activeIndex: active,
          ),
          _connector(active >= 3),
          _step(
            title: 'Retirado',
            subtitle: 'Pedido completado',
            index: 3,
            activeIndex: active,
          ),
        ],
      );
    }

    return Column(
      children: [
        _step(
          title: 'En espera',
          subtitle: 'Buscando repartidor',
          index: 0,
          activeIndex: active,
        ),
        _connector(active >= 1),
        _step(
          title: 'Aceptado',
          subtitle: 'Un rider tomó el pedido',
          index: 1,
          activeIndex: active,
        ),
        _connector(active >= 2),
        _step(
          title: 'Recogido',
          subtitle: 'Rider en camino al destino',
          index: 2,
          activeIndex: active,
        ),
        _connector(active >= 3),
        _step(
          title: 'Entregado',
          subtitle: 'Pedido completado',
          index: 3,
          activeIndex: active,
        ),
      ],
    );
  }

  Widget _connector(bool active) {
    return Row(
      children: [
        const SizedBox(width: 17),
        Container(
          width: 2,
          height: 18,
          decoration: BoxDecoration(
            color: active
                ? categoryTextGreen.withValues(alpha: 0.5)
                : borderGray100,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }

  Widget _step({
    required String title,
    required String subtitle,
    required int index,
    required int activeIndex,
  }) {
    final done = index < activeIndex || (index == activeIndex && status == OrderStatus.delivered);
    final current = index == activeIndex;

    final Color textColor;
    final Color subtitleColor;

    if (done) {
      textColor = categoryTextGreen;
      subtitleColor = textGray600;
    } else if (current) {
      textColor = textGray900;
      subtitleColor = textGray700;
    } else {
      textColor = textGray600;
      subtitleColor = textGray600;
    }

    return Container(
      padding: current
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: current
          ? BoxDecoration(
              color: primaryOrange.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primaryOrange.withValues(alpha: 0.15)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: done
                  ? categoryTextGreen.withValues(alpha: 0.12)
                  : current
                  ? primaryOrange.withValues(alpha: 0.12)
                  : borderGray100,
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    color: categoryTextGreen,
                    size: 18,
                  )
                : current
                ? const Icon(Icons.circle, color: primaryOrange, size: 10)
                : Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: textGray600.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: subtitleColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plus code resolver (geocoding for delivery address — same as buyer screen)
// ─────────────────────────────────────────────────────────────────────────────

class _PlusCodeText extends StatefulWidget {
  final String snapshot;
  final GeoPoint geo;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;

  const _PlusCodeText({
    required this.snapshot,
    required this.geo,
    required this.style,
    required this.maxLines,
    required this.overflow,
  });

  @override
  State<_PlusCodeText> createState() => _PlusCodeTextState();
}

class _PlusCodeTextState extends State<_PlusCodeText> {
  static final Map<String, String> _cache = <String, String>{};
  String? _resolved;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  bool _needsResolve(String v) {
    final t = v.trim();
    return t.isEmpty || t.startsWith('Lat:');
  }

  String _cacheKey() =>
      '${widget.geo.latitude.toStringAsFixed(6)},${widget.geo.longitude.toStringAsFixed(6)}';

  Future<void> _resolveIfNeeded() async {
    if (!_needsResolve(widget.snapshot)) return;
    final apiKey = Env.placesApiKey;
    if (apiKey.trim().isEmpty) return;

    final key = _cacheKey();
    final cached = _cache[key];
    if (cached != null && cached.trim().isNotEmpty) {
      setState(() => _resolved = cached);
      return;
    }

    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${widget.geo.latitude},${widget.geo.longitude}'
        '&key=$apiKey',
      );
      final res = await http.get(uri);
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => _loading = false);
        return;
      }
      final decoded = json.decode(res.body);
      if (decoded is! Map<String, dynamic>) {
        setState(() => _loading = false);
        return;
      }
      final results = decoded['results'];
      String? formatted;
      if (results is List && results.isNotEmpty) {
        formatted = results.first['formatted_address']?.toString();
      }
      if (formatted != null && formatted.trim().isNotEmpty) {
        _cache[key] = formatted;
        if (mounted) {
          setState(() {
            _resolved = formatted;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 14,
        width: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: primaryOrange,
        ),
      );
    }
    final display =
        _resolved ?? (_needsResolve(widget.snapshot) ? '' : widget.snapshot);
    if (display.isEmpty) return const SizedBox.shrink();
    return Text(
      display,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StatusConfig helper
// ─────────────────────────────────────────────────────────────────────────────

class _StatusConfig {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;

  const _StatusConfig({
    required this.color,
    required this.bg,
    required this.icon,
    required this.label,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic status message widget
// ─────────────────────────────────────────────────────────────────────────────

class _StatusMessage extends StatelessWidget {
  final String title;
  final String subtitle;
  const _StatusMessage({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.info_outline,
                color: primaryOrange,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
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
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textGray600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

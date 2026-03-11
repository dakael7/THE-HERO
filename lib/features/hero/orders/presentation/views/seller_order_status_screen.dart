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
import '../../../../../domain/entities/user.dart';
import '../../../../../data/providers/network_providers.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../../shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/providers/payment_providers.dart';
import 'order_receipt_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ROOT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

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
      appBar: _buildAppBar(context),
      body: orderAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: primaryOrange)),
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

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: BoxDecoration(
          color: primaryYellow,
          boxShadow: [
            BoxShadow(
              color: primaryYellow.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                // Back button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: textGray900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Orange accent bar
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: primaryOrange,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                // Icon container
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: primaryOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.volunteer_activism_rounded,
                    size: 18,
                    color: primaryOrange,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Detalle del pedido',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CONTENT
// ─────────────────────────────────────────────────────────────────────────────

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
    final hasRider = order.rider.isAssigned &&
        (order.rider.riderNameSnapshot?.isNotEmpty ?? false);

    final canMarkReadyForPickup = order.inPersonPickup &&
        status != OrderStatus.delivered &&
        status != OrderStatus.canceled &&
        status != OrderStatus.failed &&
        status != OrderStatus.pickedUp &&
        status != OrderStatus.inTransit;

    final canMarkDelivered = order.inPersonPickup &&
        status != OrderStatus.delivered &&
        status != OrderStatus.canceled &&
        status != OrderStatus.failed &&
        (status == OrderStatus.pickedUp || status == OrderStatus.inTransit);

    final paymentAsync =
        ref.watch(watchPaymentByOrderIdProvider(order.orderId));
    final payment = paymentAsync.asData?.value;
    final isPaymentApproved = payment?.status == PaymentStatus.approved;
    final isCashPayment =
        payment?.paymentMethod == PaymentMethod.cash ||
            (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
            (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final canShowReceipt = status != OrderStatus.pendingPayment &&
        (isPaymentApproved || isCashPayment);

    final myTotal = myItems.fold(0.0, (s, i) => s + i.totalPrice);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── STATUS CARD ──────────────────────────────────────────
        _StatusCard(
          order: order,
          cfg: cfg,
          status: status,
          hasRider: hasRider,
          canShowReceipt: canShowReceipt,
          canMarkReadyForPickup: canMarkReadyForPickup,
          canMarkDelivered: canMarkDelivered,
          sellerId: sellerId,
        ),

        const SizedBox(height: 16),

        // ── SUMMARY CARD ─────────────────────────────────────────
        _SummaryCard(order: order, myTotal: myTotal),

        const SizedBox(height: 16),

        // ── MY ITEMS CARD ────────────────────────────────────────
        _MyItemsCard(myItems: myItems),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATUS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends ConsumerWidget {
  final Order order;
  final _StatusConfig cfg;
  final OrderStatus status;
  final bool hasRider;
  final bool canShowReceipt;
  final bool canMarkReadyForPickup;
  final bool canMarkDelivered;
  final String sellerId;

  const _StatusCard({
    required this.order,
    required this.cfg,
    required this.status,
    required this.hasRider,
    required this.canShowReceipt,
    required this.canMarkReadyForPickup,
    required this.canMarkDelivered,
    required this.sellerId,
  });

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    String newStatus,
    String successMsg,
  ) async {
    try {
      await ref
          .read(orderNotifierProvider.notifier)
          .updateStatus(order.orderId, newStatus);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMsg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: cfg.color.withOpacity(0.14),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Colored header ────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: cfg.bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cfg.color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(cfg.icon, color: cfg.color, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cfg.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: cfg.color,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cfg.color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'HRO-${order.orderId.length > 8 ? order.orderId.substring(0, 8) : order.orderId}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: cfg.color.withOpacity(0.75),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Chat chips
                _SellerChatActions(order: order, sellerId: sellerId),

                // Receipt button
                if (canShowReceipt) ...[
                  const SizedBox(height: 10),
                  _ReceiptButton(order: order),
                ],
              ],
            ),
          ),

          // ── Timeline ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: _OrderStatusTimeline(
              status: status,
              inPersonPickup: order.inPersonPickup,
            ),
          ),

          // ── Seller action buttons ─────────────────────────────
          if (canMarkReadyForPickup)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _PrimaryActionButton(
                label: 'Marcar listo para retiro',
                icon: Icons.inventory_2_rounded,
                color: primaryOrange,
                onTap: () => _updateStatus(
                  context,
                  ref,
                  'picked_up',
                  'Marcado como listo para retiro',
                ),
              ),
            ),

          if (canMarkDelivered)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _PrimaryActionButton(
                label: 'Marcar como entregado',
                icon: Icons.check_circle_rounded,
                color: categoryTextGreen,
                onTap: () => _updateStatus(
                  context,
                  ref,
                  'delivered',
                  'Pedido marcado como entregado',
                ),
              ),
            ),

          // ── Rider chip ────────────────────────────────────────
          if (hasRider && !order.inPersonPickup)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _RiderChip(order: order),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SUMMARY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final Order order;
  final double myTotal;

  const _SummaryCard({required this.order, required this.myTotal});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: textGray700.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: textGray700,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Resumen del pedido',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const _Hairline(),
          const SizedBox(height: 14),

          // Total row
          _DetailRow(
            icon: Icons.payments_rounded,
            iconColor: categoryTextGreen,
            label: 'Mis artículos',
            value: '\$${myTotal.toStringAsFixed(0)} CLP',
          ),

          // Delivery address row
          if (!order.inPersonPickup) ...[
            const SizedBox(height: 12),
            _DeliveryAddressRow(order: order),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
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
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
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

class _DeliveryAddressRow extends StatelessWidget {
  final Order order;
  const _DeliveryAddressRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final hasAddress = order.delivery.addressSnapshot.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.location_on_rounded,
            color: Color(0xFF2563EB),
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dirección de entrega',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textGray600,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 2),
              if (hasAddress)
                Text(
                  order.delivery.addressSnapshot,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textGray900,
                  ),
                )
              else
                _PlusCodeText(
                  snapshot: order.delivery.addressSnapshot,
                  geo: order.delivery.geo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textGray900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MY ITEMS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _MyItemsCard extends StatelessWidget {
  final List<OrderItem> myItems;
  const _MyItemsCard({required this.myItems});

  @override
  Widget build(BuildContext context) {
    if (myItems.isEmpty) return const SizedBox.shrink();

    final total = myItems.fold(0.0, (s, i) => s + i.totalPrice);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  size: 17,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mis artículos (${myItems.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: textGray900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              // Total pill
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '\$${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: primaryOrange,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const _Hairline(),
          const SizedBox(height: 14),

          // Items list
          ...List.generate(myItems.length, (index) {
            final item = myItems[index];
            final isLast = index == myItems.length - 1;
            return Column(
              children: [
                _ItemRow(item: item),
                if (!isLast) ...[
                  const SizedBox(height: 12),
                  const _Hairline(),
                  const SizedBox(height: 12),
                ],
              ],
            );
          }),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: primaryOrange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryOrange.withOpacity(0.15)),
          ),
          child: const Icon(
            Icons.volunteer_activism_outlined,
            color: primaryOrange,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.titleSnapshot,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                  fontSize: 13,
                ),
              ),
              if (item.qty > 1) ...[
                const SizedBox(height: 2),
                Text(
                  '×${item.qty} unidades',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textGray600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: backgroundGray50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderGray100),
          ),
          child: Text(
            '\$${item.totalPrice.toStringAsFixed(0)}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: textGray900,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TIMELINE
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

    final steps = inPersonPickup
        ? [
            _StepData('En espera', 'Coordina el retiro por chat'),
            _StepData('Coordinado', 'Retiro coordinado con el comprador'),
            _StepData('Listo', 'Deja listo el pedido para retiro'),
            _StepData('Retirado', 'Pedido completado'),
          ]
        : [
            _StepData('En espera', 'Buscando repartidor'),
            _StepData('Aceptado', 'Un rider tomó el pedido'),
            _StepData('Recogido', 'Rider en camino al destino'),
            _StepData('Entregado', 'Pedido completado'),
          ];

    return Column(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return _Connector(done: active > i ~/ 2);
        }
        final idx = i ~/ 2;
        return _TimelineStep(
          title: steps[idx].title,
          subtitle: steps[idx].subtitle,
          index: idx,
          activeIndex: active,
          status: status,
        );
      }),
    );
  }
}

class _StepData {
  final String title;
  final String subtitle;
  const _StepData(this.title, this.subtitle);
}

class _Connector extends StatelessWidget {
  final bool done;
  const _Connector({required this.done});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 17),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 22,
          width: 2,
          decoration: BoxDecoration(
            color: done
                ? categoryTextGreen.withOpacity(0.5)
                : borderGray100,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final int index;
  final int activeIndex;
  final OrderStatus status;

  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.index,
    required this.activeIndex,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final done = index < activeIndex ||
        (index == activeIndex && status == OrderStatus.delivered);
    final current = index == activeIndex;

    final Color dotBg;
    final Color textColor;
    final Color subtitleColor;
    final Widget dotChild;

    if (done) {
      dotBg = categoryTextGreen.withOpacity(0.14);
      textColor = categoryTextGreen;
      subtitleColor = textGray600;
      dotChild = const Icon(Icons.check_rounded,
          color: categoryTextGreen, size: 16);
    } else if (current) {
      dotBg = primaryOrange.withOpacity(0.14);
      textColor = textGray900;
      subtitleColor = textGray700;
      dotChild = Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: primaryOrange,
          shape: BoxShape.circle,
        ),
      );
    } else {
      dotBg = const Color(0xFFF0F0F0);
      textColor = textGray600;
      subtitleColor = textGray600;
      dotChild = Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: textGray600.withOpacity(0.25),
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: current
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: current
          ? BoxDecoration(
              color: primaryOrange.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: primaryOrange.withOpacity(0.15)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: dotBg,
              shape: BoxShape.circle,
            ),
            child: Center(child: dotChild),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: subtitleColor,
                    fontWeight: FontWeight.w500,
                  ),
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
//  SELLER CHAT ACTIONS
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
    String? avatarUrl,
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
      avatarUrl: avatarUrl,
    );
  }

  Future<void> _openRiderChat(NavigatorState navigator, WidgetRef ref) async {
    if (!order.rider.isAssigned) return;
    final riderId = order.rider.assignedRiderId;
    if (riderId == null || riderId.isEmpty) return;

    final seller = ref.read(profileProvider).value;
    if (seller == null) return;

    final riderUser = await ref.read(userByIdProvider(riderId).future);
    final riderName = (riderUser?.fullName.trim().isNotEmpty ?? false)
        ? riderUser!.fullName
        : (order.rider.riderNameSnapshot ?? 'Rider');

    final chatId = Chat.generateChatId(
      type: ChatType.heroRider,
      buyerId: sellerId,
      riderId: riderId,
      orderId: order.orderId,
    );

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
    final hasRider = order.rider.isAssigned &&
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

    final buyerAsync = ref.watch(userByIdStreamProvider(order.heroId));
    final buyerName = buyerAsync.maybeWhen(
      data: (u) => u?.fullName ?? 'Comprador',
      orElse: () => 'Comprador',
    );
    final buyerPhotoUrl = buyerAsync.maybeWhen(
      data: (u) => u?.profilePhotoUrl,
      orElse: () => null,
    );

    final riderId = order.rider.assignedRiderId;
    final riderAsync = (hasRider && riderId != null)
        ? ref.watch(userByIdStreamProvider(riderId))
        : const AsyncValue<User?>.data(null);
    final riderPhotoUrl = riderAsync.maybeWhen(
      data: (u) => u?.profilePhotoUrl,
      orElse: () => null,
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
            avatarUrl: riderPhotoUrl,
          ),
          const SizedBox(width: 6),
        ],
        _ChatChipButton(
          icon: Icons.person_rounded,
          label: buyerName,
          badgeCount: buyerBadgeCount,
          onTap: () => _openBuyerChat(Navigator.of(context), ref, buyerName),
          avatarUrl: buyerPhotoUrl,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT CHIP BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _ChatChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;
  final String? avatarUrl;

  const _ChatChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = badgeCount > 0;
    final url = avatarUrl?.trim() ?? '';
    final hasPhoto = url.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.65),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.85)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBadge) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 18),
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
            if (hasPhoto)
              ClipOval(
                child: Image.network(
                  url,
                  width: 20,
                  height: 20,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(icon, size: 15, color: primaryOrange),
                ),
              )
            else
              Icon(icon, size: 15, color: primaryOrange),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
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
//  PLUS CODE TEXT
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
//  STATUS MESSAGE
// ─────────────────────────────────────────────────────────────────────────────

class _StatusMessage extends StatelessWidget {
  final String title;
  final String subtitle;
  const _StatusMessage({required this.title, required this.subtitle});

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
                color: primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.volunteer_activism_rounded,
                size: 36,
                color: primaryOrange,
              ),
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
              subtitle,
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

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED PRIMITIVES
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFFF2F2F2));
}

class _ReceiptButton extends StatelessWidget {
  final Order order;
  const _ReceiptButton({required this.order});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => OrderReceiptScreen(orderId: order.orderId)),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.9)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_rounded, size: 16, color: primaryOrange),
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

class _RiderChip extends StatelessWidget {
  final Order order;
  const _RiderChip({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: primaryOrange.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryOrange.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primaryOrange.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.delivery_dining_rounded,
              color: primaryOrange,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Repartidor',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: textGray600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                order.rider.riderNameSnapshot ?? 'Asignado',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.32),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 14,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
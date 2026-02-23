import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_type.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../../shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import 'driver_rating_screen.dart';

class HeroOrderStatusScreen extends ConsumerWidget {
  final String orderId;
  const HeroOrderStatusScreen({super.key, required this.orderId});

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
          'Estado del pedido',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (err, _) => _StatusMessage(
          title: 'No pudimos cargar tu perfil',
          subtitle: err.toString(),
        ),
        data: (user) {
          if (user == null) {
            return const _StatusMessage(
              title: 'Inicia sesión',
              subtitle:
                  'Necesitas iniciar sesión para ver el estado del pedido.',
            );
          }

          final orderAsync = ref.watch(orderByIdProvider(orderId));
          return orderAsync.when(
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
                  title: 'Buscando tu pedido…',
                  subtitle:
                      'Espera unos segundos mientras sincronizamos el estado.',
                );
              }
              return _OrderStatusContent(order: order);
            },
          );
        },
      ),
    );
  }
}

class _PickupStopsSummary extends StatelessWidget {
  final Order order;
  const _PickupStopsSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    final stops = order.pickupStops;
    if (stops == null || stops.isEmpty) {
      return _row(
        'Recogida',
        order.pickup.addressSnapshot.isNotEmpty
            ? order.pickup.addressSnapshot
            : 'Sin dirección',
      );
    }

    return _row(
      'Recogidas',
      '${stops.length} punto${stops.length == 1 ? '' : 's'}',
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: textGray700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: textGray900,
            ),
          ),
        ),
      ],
    );
  }
}

class _PickupStopsCard extends StatelessWidget {
  final Order order;
  const _PickupStopsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final stops = order.pickupStops;
    if (stops == null || stops.isEmpty) {
      return const SizedBox.shrink();
    }

    final itemsByOfferId = {for (final i in order.items) i.offerId: i};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Puntos de recogida',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '${stops.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(stops.length, (index) {
            final stop = stops[index];
            final offerTitles = stop.offerIds
                .map((id) => itemsByOfferId[id]?.titleSnapshot)
                .whereType<String>()
                .where((e) => e.trim().isNotEmpty)
                .toList();
            final titles = offerTitles.isEmpty
                ? 'Artículos: ${stop.offerIds.length}'
                : offerTitles.take(2).join(' · ');

            return Padding(
              padding:
                  EdgeInsets.only(bottom: index == stops.length - 1 ? 0 : 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: backgroundGray50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderGray100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: primaryOrange,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.addressSnapshot.trim().isNotEmpty
                                ? stop.addressSnapshot
                                : 'Lat: ${stop.geo.latitude.toStringAsFixed(5)}, Lng: ${stop.geo.longitude.toStringAsFixed(5)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: textGray900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            titles,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: textGray600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _OrderStatusContent extends StatelessWidget {
  final Order order;

  const _OrderStatusContent({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order.status;

    final isFailed = status == OrderStatus.failed;
    final isCanceled = status == OrderStatus.canceled;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pedido HRO-${order.orderId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _HeroChatButton(order: order),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Estado actual: ${status.displayName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textGray700,
                ),
              ),
              const SizedBox(height: 12),
              _OrderStatusTimeline(status: status),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Delivery confirmation card
        if (status == OrderStatus.delivered && order.confirmedByHero != true)
          _DeliveryConfirmationCard(order: order),
        if (status == OrderStatus.delivered && order.confirmedByHero != true)
          const SizedBox(height: 16),
        if (isCanceled)
          _StatusBanner(
            title: 'Pedido cancelado',
            subtitle: order.cancelReason?.isNotEmpty == true
                ? order.cancelReason!
                : 'Este pedido fue cancelado.',
            color: Colors.red,
          )
        else if (isFailed)
          const _StatusBanner(
            title: 'Pedido fallido',
            subtitle: 'Este pedido tuvo un problema y no pudo completarse.',
            color: Colors.red,
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              _row('Total', '\$${order.amountTotal.toStringAsFixed(0)} CLP'),
              const SizedBox(height: 8),
              _PickupStopsSummary(order: order),
              const SizedBox(height: 8),
              _row(
                'Entrega',
                order.delivery.addressSnapshot.isNotEmpty
                    ? order.delivery.addressSnapshot
                    : 'Sin dirección',
              ),
              const SizedBox(height: 8),
              _row(
                'Repartidor',
                order.rider.isAssigned
                    ? (order.rider.riderNameSnapshot ?? 'Asignado')
                    : 'Aún no asignado',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PickupStopsCard(order: order),
        if ((order.pickupStops?.isNotEmpty ?? false)) const SizedBox(height: 16),
        _OrderItemsCard(order: order),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: textGray700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: textGray900,
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderItemsCard extends StatelessWidget {
  final Order order;

  const _OrderItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final items = order.items;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Productos',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '${order.totalItems} items',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'Sin productos',
              style: TextStyle(color: textGray600, fontWeight: FontWeight.w600),
            )
          else
            ...List.generate(items.length, (index) {
              final item = items[index];
              final lineTotal = item.unitPriceSnapshot * item.qty;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: backgroundGray50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderGray100),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        size: 18,
                        color: textGray600,
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
                          const SizedBox(height: 4),
                          Text(
                            '${item.qty} x \$${item.unitPriceSnapshot.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: textGray600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '\$${lineTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _OrderStatusTimeline extends StatelessWidget {
  final OrderStatus status;

  const _OrderStatusTimeline({required this.status});

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
          subtitle: 'Un rider tomó tu pedido',
          index: 1,
          activeIndex: active,
        ),
        _connector(active >= 2),
        _step(
          title: 'En camino',
          subtitle: 'Pedido en ruta',
          index: 2,
          activeIndex: active,
        ),
        _connector(active >= 3),
        _step(
          title: 'Entregado',
          subtitle: 'Pedido finalizado',
          index: 3,
          activeIndex: active,
        ),
      ],
    );
  }

  Widget _connector(bool done) {
    return Container(
      height: 18,
      width: 2,
      margin: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: done ? categoryTextGreen : borderGray100,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _step({
    required String title,
    required String subtitle,
    required int index,
    required int activeIndex,
  }) {
    final done = index < activeIndex;
    final current = index == activeIndex;

    final Color color;
    final IconData icon;

    if (done) {
      color = categoryTextGreen;
      icon = Icons.check_circle;
    } else if (current) {
      color = primaryOrange;
      icon = Icons.radio_button_checked;
    } else {
      color = textGray600;
      icon = Icons.radio_button_unchecked;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: current || done ? textGray900 : textGray700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: current ? textGray700 : textGray600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const _StatusBanner({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textGray700,
                    fontSize: 12,
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
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.receipt_long,
                size: 34,
                color: primaryOrange,
              ),
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
              subtitle,
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

class _HeroChatButton extends ConsumerWidget {
  final Order order;
  const _HeroChatButton({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!order.rider.isAssigned) {
      return const SizedBox.shrink();
    }
    final riderId = order.rider.assignedRiderId;
    if (riderId == null || riderId.isEmpty) {
      return const SizedBox.shrink();
    }

    final profileAsync = ref.watch(profileProvider);
    final riderAsync = ref.watch(userByIdProvider(riderId));

    return IconButton(
      tooltip: 'Chat con rider',
      icon: const Icon(Icons.chat_bubble_outline),
      color: primaryOrange,
      onPressed: () async {
        final user = profileAsync.value;
        if (user == null) return;

        // Get rider name from user provider
        final riderName =
            riderAsync.value?.fullName ??
            order.rider.riderNameSnapshot ??
            'Rider';

        final chatId = Chat.generateChatId(
          type: ChatType.heroRider,
          buyerId: order.heroId,
          riderId: riderId,
          orderId: order.orderId,
        );
        final chat = Chat(
          chatId: chatId,
          type: ChatType.heroRider,
          buyerId: order.heroId,
          buyerName: user.fullName,
          riderId: riderId,
          riderName: riderName,
          orderId: order.orderId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await ref.read(chatActionsProvider).ensureChatExists(chat);
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
        );
      },
    );
  }
}

class _DeliveryConfirmationCard extends StatelessWidget {
  final Order order;

  const _DeliveryConfirmationCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            categoryTextGreen.withValues(alpha: 0.1),
            categoryTextGreen.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: categoryTextGreen.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: categoryTextGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¿Recibiste el paquete?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Confirma que recibiste tu pedido',
                      style: TextStyle(fontSize: 13, color: textGray700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DriverRatingScreen(order: order),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: categoryTextGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Sí, lo recibí',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Función de reporte en desarrollo'),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryOrange,
                      side: const BorderSide(color: primaryOrange, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Reportar problema',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

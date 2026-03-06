import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/config/env.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../data/providers/network_providers.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_type.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../../domain/entities/payment.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../../shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/providers/payment_providers.dart';
import 'order_receipt_screen.dart';
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

  @override
  void didUpdateWidget(covariant _PlusCodeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot ||
        oldWidget.geo.latitude != widget.geo.latitude ||
        oldWidget.geo.longitude != widget.geo.longitude) {
      _resolved = null;
      _loading = false;
      _resolveIfNeeded();
    }
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
      if (res.statusCode != 200) return;

      final decoded = json.decode(res.body);
      if (decoded is! Map<String, dynamic>) return;

      String? compoundPlusCode;
      final plusCode = decoded['plus_code'];
      if (plusCode is Map<String, dynamic>) {
        final compound = plusCode['compound_code'];
        if (compound is String && compound.trim().isNotEmpty) {
          compoundPlusCode = compound.trim();
        }
      }

      if (compoundPlusCode == null || compoundPlusCode.trim().isEmpty) return;
      _cache[key] = compoundPlusCode;
      setState(() => _resolved = compoundPlusCode);
    } catch (_) {
      // swallow
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.snapshot.trim();
    final show = (_resolved != null && _resolved!.trim().isNotEmpty)
        ? _resolved!.trim()
        : (raw.isEmpty || raw.startsWith('Lat:')
              ? 'Ubicación en el mapa'
              : raw);

    return Row(
      children: [
        Expanded(
          child: Text(
            show,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
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
              padding: EdgeInsets.only(
                bottom: index == stops.length - 1 ? 0 : 12,
              ),
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
                          if (stop.addressSnapshot.trim().isNotEmpty)
                            Text(
                              stop.addressSnapshot,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                            )
                          else
                            _PlusCodeText(
                              snapshot:
                                  'Lat: ${stop.geo.latitude.toStringAsFixed(5)}, Lng: ${stop.geo.longitude.toStringAsFixed(5)}',
                              geo: stop.geo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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

class _OrderStatusContent extends ConsumerWidget {
  final Order order;

  const _OrderStatusContent({required this.order});

  static _StatusConfig _config(Order order) {
    final s = order.status;
    if (order.inPersonPickup) {
      switch (s) {
        case OrderStatus.created:
        case OrderStatus.pendingPayment:
        case OrderStatus.paid:
        case OrderStatus.queued:
          return _StatusConfig(
            color: const Color(0xFFF59E0B),
            bg: const Color(0xFFFEF3C7),
            icon: Icons.store_rounded,
            label: 'Coordinando retiro…',
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
            label: 'Listo para retirar',
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

    switch (s) {
      case OrderStatus.created:
      case OrderStatus.pendingPayment:
      case OrderStatus.paid:
      case OrderStatus.queued:
        return _StatusConfig(
          color: const Color(0xFFF59E0B),
          bg: const Color(0xFFFEF3C7),
          icon: Icons.hourglass_top_rounded,
          label: 'Buscando repartidor…',
        );
      case OrderStatus.assigned:
        return _StatusConfig(
          color: primaryOrange,
          bg: const Color(0xFFFFEDD5),
          icon: Icons.delivery_dining,
          label: 'Repartidor asignado',
        );
      case OrderStatus.pickedUp:
        return _StatusConfig(
          color: primaryOrange,
          bg: const Color(0xFFFFEDD5),
          icon: Icons.inventory_2_rounded,
          label: 'Paquete recogido',
        );
      case OrderStatus.inTransit:
        return _StatusConfig(
          color: const Color(0xFF2563EB),
          bg: const Color(0xFFDBEAFE),
          icon: Icons.local_shipping_rounded,
          label: 'En camino a ti',
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
    final isFailed = status == OrderStatus.failed;
    final isCanceled = status == OrderStatus.canceled;
    final hasRider =
        order.rider.isAssigned &&
        (order.rider.riderNameSnapshot?.isNotEmpty ?? false);

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
        // ── Status Card ─────────────────────────────────────────
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
              // Gradient header band
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
                    _OrderChatActions(order: order),
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
              // Rider chip (if assigned)
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
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: primaryOrange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.delivery_dining,
                            color: primaryOrange,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Repartidor',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                            ),
                            Text(
                              order.rider.riderNameSnapshot ?? 'Asignado',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── Delivery Confirmation Card ───────────────────────────
        if (status == OrderStatus.delivered &&
            order.confirmedByHero != true &&
            !order.inPersonPickup)
          _DeliveryConfirmationCard(order: order),
        if (status == OrderStatus.delivered &&
            order.confirmedByHero != true &&
            !order.inPersonPickup)
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
        // ── Details Card ────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detalles del pedido',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: textGray700,
                ),
              ),
              const SizedBox(height: 12),
              _iconRow(
                Icons.payments_rounded,
                const Color(0xFF059669),
                'Total',
                '\$${order.amountTotal.toStringAsFixed(0)} CLP',
              ),
              const SizedBox(height: 10),
              _iconPickupRow(),
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
                if (!hasRider) ...[
                  const SizedBox(height: 10),
                  _iconRow(
                    Icons.delivery_dining,
                    textGray600,
                    'Repartidor',
                    'Aún no asignado',
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PickupStopsCard(order: order),
        if ((order.pickupStops?.isNotEmpty ?? false))
          const SizedBox(height: 16),
        _OrderItemsCard(order: order),
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

  Widget _iconPickupRow() {
    final stops = order.pickupStops;
    final label = (stops != null && stops.isNotEmpty)
        ? '${stops.length} punto${stops.length == 1 ? '' : 's'} de recogida'
        : (order.pickup.addressSnapshot.isNotEmpty
              ? order.pickup.addressSnapshot
              : 'Sin dirección');
    return _iconRow(Icons.store_rounded, primaryOrange, 'Recogida', label);
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
            subtitle: 'Retiro coordinado con el donador',
            index: 1,
            activeIndex: active,
          ),
          _connector(active >= 2),
          _step(
            title: 'Listo',
            subtitle: 'El donador dejó listo el pedido',
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
    return Row(
      children: [
        const SizedBox(width: 17),
        Container(
          height: 22,
          width: 2,
          decoration: BoxDecoration(
            color: done ? categoryTextGreen : borderGray100,
            borderRadius: BorderRadius.circular(2),
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

class _OrderChatActions extends ConsumerWidget {
  final Order order;

  const _OrderChatActions({required this.order});

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

  Future<List<_SellerChatChoice>> _resolveSellerChoices(WidgetRef ref) async {
    final repo = ref.read(offersRepositoryProvider);

    final itemsByOfferId = {for (final i in order.items) i.offerId: i};
    final offerIds = itemsByOfferId.keys
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    if (offerIds.isEmpty) return const <_SellerChatChoice>[];

    final offers = await Future.wait(
      offerIds.map((id) => repo.getOfferById(id)),
    );

    final choices = <_SellerChatChoice>[];
    for (final offer in offers.whereType<Offer>()) {
      final sellerId = offer.heroId.trim();
      if (sellerId.isEmpty) continue;

      final offerId = offer.offerId.trim();
      if (offerId.isEmpty) continue;

      final title = itemsByOfferId[offerId]?.titleSnapshot;
      choices.add(
        _SellerChatChoice(
          sellerId: sellerId,
          offerId: offerId,
          itemTitle: (title != null && title.trim().isNotEmpty) ? title : null,
        ),
      );
    }

    return choices;
  }

  Future<void> _openRiderChat(NavigatorState navigator, WidgetRef ref) async {
    if (!order.rider.isAssigned) return;
    final riderId = order.rider.assignedRiderId;
    if (riderId == null || riderId.isEmpty) return;

    final buyer = ref.read(profileProvider).value;
    if (buyer == null) return;

    final riderAsync = ref.read(userByIdProvider(riderId));
    final riderName =
        riderAsync.value?.fullName ?? order.rider.riderNameSnapshot ?? 'Rider';

    final newChatId = Chat.generateChatId(
      type: ChatType.heroRider,
      buyerId: order.heroId,
      riderId: riderId,
      orderId: order.orderId,
    );
    final legacyChatId = '${ChatType.heroRider.jsonValue}_order_${order.orderId}';

    final docNew = await FirebaseFirestore.instance
        .collection('chats')
        .doc(newChatId)
        .get();
    final docLegacy = docNew.exists
        ? null
        : await FirebaseFirestore.instance
            .collection('chats')
            .doc(legacyChatId)
            .get();

    final legacyOk = (() {
      if (!(docLegacy?.exists ?? false)) return false;
      final data = docLegacy!.data() ?? <String, dynamic>{};
      final legacyBuyerId = (data['buyerId'] as String?) ?? (data['heroId'] as String?) ?? '';
      final legacyRiderId = (data['riderId'] as String?) ?? '';
      final rawParticipantIds = data['participantIds'];
      final participantIds = rawParticipantIds is List
          ? rawParticipantIds.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final expected = <String>[order.heroId.trim(), riderId.trim()];
      final hasOnlyExpected = participantIds.length == 2 &&
          participantIds.toSet().containsAll(expected) &&
          expected.toSet().containsAll(participantIds.toSet());

      final legacySellerId = (data['sellerId'] as String?) ?? '';
      return legacyBuyerId.trim() == order.heroId.trim() &&
          legacyRiderId.trim() == riderId.trim() &&
          legacySellerId.trim().isEmpty &&
          hasOnlyExpected;
    })();

    final chatId = docNew.exists ? newChatId : (legacyOk ? legacyChatId : newChatId);
    final chat = Chat(
      chatId: chatId,
      type: ChatType.heroRider,
      buyerId: order.heroId,
      buyerName: buyer.fullName,
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

  Future<void> _openSellerChat({
    required NavigatorState navigator,
    required WidgetRef ref,
    required String sellerId,
    required String offerId,
  }) async {
    final buyer = ref.read(profileProvider).value;
    if (buyer == null) return;

    final chatId = Chat.generateChatId(
      type: ChatType.heroSeller,
      buyerId: order.heroId,
      sellerId: sellerId,
      offerId: offerId,
    );
    final chat = Chat(
      chatId: chatId,
      type: ChatType.heroSeller,
      buyerId: order.heroId,
      buyerName: buyer.fullName,
      sellerId: sellerId,
      orderId: order.orderId,
      offerId: offerId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(chatActionsProvider).ensureChatExists(chat);
    if (!navigator.mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
    );
  }

  Future<void> _pickAndOpenSellerChat(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final choices = await _resolveSellerChoices(ref);
    if (choices.isEmpty) return;

    if (!context.mounted) return;
    final navigator = Navigator.of(context);

    if (choices.length == 1) {
      final c = choices.first;
      await _openSellerChat(
        navigator: navigator,
        ref: ref,
        sellerId: c.sellerId,
        offerId: c.offerId,
      );
      return;
    }

    if (!context.mounted) return;
    final selected = await showModalBottomSheet<_SellerChatChoice>(
      context: context,
      showDragHandle: true,
      backgroundColor: backgroundWhite,
      builder: (_) => _SellerPickerSheet(choices: choices),
    );

    if (selected == null) return;
    if (!context.mounted) return;
    await _openSellerChat(
      navigator: navigator,
      ref: ref,
      sellerId: selected.sellerId,
      offerId: selected.offerId,
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
    final sellerBadgeCount = sellerChatsAsync.maybeWhen(
      data: (chats) {
        if (currentUserId == null) return 0;
        final matching = chats.where(
          (c) =>
              c.type == ChatType.heroSeller &&
              (c.orderId ?? '').trim() == order.orderId.trim(),
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasRider)
          _buildChipWithUnread(
            ref: ref,
            chatId: Chat.generateChatId(
              type: ChatType.heroRider,
              buyerId: order.heroId,
              riderId: order.rider.assignedRiderId,
              orderId: order.orderId,
            ),
            icon: Icons.delivery_dining,
            label: riderName,
            onTap: () => _openRiderChat(Navigator.of(context), ref),
          ),
        const SizedBox(width: 4),
        _ChatChipButton(
          icon: Icons.storefront_outlined,
          label: 'Vendedor',
          badgeCount: sellerBadgeCount,
          onTap: () => _pickAndOpenSellerChat(context, ref),
        ),
      ],
    );
  }
}

// ...

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

class _SellerPickerSheet extends ConsumerWidget {
  final List<_SellerChatChoice> choices;

  const _SellerPickerSheet({required this.choices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona un vendedor',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: textGray900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...choices.map((c) {
              final asyncUser = ref.watch(userByIdProvider(c.sellerId));
              final sellerName = asyncUser.maybeWhen(
                data: (u) => (u?.fullName.trim().isNotEmpty ?? false)
                    ? u!.fullName
                    : 'Vendedor',
                orElse: () => 'Vendedor',
              );

              final itemTitle =
                  (c.itemTitle != null && c.itemTitle!.trim().isNotEmpty)
                  ? c.itemTitle!
                  : 'Artículo';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: primaryOrange,
                  ),
                ),
                title: Text(
                  itemTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textGray900,
                  ),
                ),
                subtitle: Text(
                  sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: textGray600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: textGray600),
                onTap: () {
                  Navigator.of(context).pop(
                    _SellerChatChoice(
                      sellerId: c.sellerId,
                      offerId: c.offerId,
                      itemTitle: c.itemTitle,
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SellerChatChoice {
  final String sellerId;
  final String offerId;
  final String? itemTitle;

  const _SellerChatChoice({
    required this.sellerId,
    required this.offerId,
    this.itemTitle,
  });
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

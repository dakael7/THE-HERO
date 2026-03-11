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
import '../../../../../domain/entities/user.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../../shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/providers/payment_providers.dart';
import 'order_receipt_screen.dart';
import 'driver_rating_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ROOT SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class HeroOrderStatusScreen extends ConsumerWidget {
  final String orderId;
  const HeroOrderStatusScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: _buildAppBar(context),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: primaryOrange)),
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
                child: CircularProgressIndicator(color: primaryOrange)),
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
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18, color: textGray900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Orange bar + icon + title
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: primaryOrange,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: primaryOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      size: 18, color: primaryOrange),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Estado del pedido',
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
//  PLUS CODE RESOLVER
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
          child: Text(show,
              style: widget.style,
              maxLines: widget.maxLines,
              overflow: widget.overflow),
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

// ─────────────────────────────────────────────────────────────────────────────
//  PICKUP STOPS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _PickupStopsCard extends StatelessWidget {
  final Order order;
  const _PickupStopsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final stops = order.pickupStops;
    if (stops == null || stops.isEmpty) return const SizedBox.shrink();

    final itemsByOfferId = {for (final i in order.items) i.offerId: i};

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
                child: const Icon(Icons.place_rounded,
                    size: 18, color: primaryOrange),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Puntos de recogida',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${stops.length}',
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

            final isLast = index == stops.length - 1;

            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
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
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: primaryOrange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: primaryOrange,
                            fontSize: 14,
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
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                                fontSize: 13,
                              ),
                            )
                          else
                            _PlusCodeText(
                              snapshot:
                                  'Lat: ${stop.geo.latitude.toStringAsFixed(5)}, Lng: ${stop.geo.longitude.toStringAsFixed(5)}',
                              geo: stop.geo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 3),
                          Text(
                            titles,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: textGray600,
                              fontSize: 11,
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

// ─────────────────────────────────────────────────────────────────────────────
//  ORDER STATUS CONTENT
// ─────────────────────────────────────────────────────────────────────────────
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
    final hasRider = order.rider.isAssigned &&
        (order.rider.riderNameSnapshot?.isNotEmpty ?? false);

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
        ),

        const SizedBox(height: 16),

        // ── DELIVERY CONFIRMATION ────────────────────────────────
        if (status == OrderStatus.delivered &&
            order.confirmedByHero != true &&
            !order.inPersonPickup) ...[
          _DeliveryConfirmationCard(order: order),
          const SizedBox(height: 16),
        ],

        // ── STATUS BANNER ────────────────────────────────────────
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
            subtitle:
                'Este pedido tuvo un problema y no pudo completarse.',
            color: Colors.red,
          ),

        // ── DETAILS CARD ─────────────────────────────────────────
        _DetailsCard(order: order, hasRider: hasRider),

        const SizedBox(height: 16),

        // ── PICKUP STOPS ─────────────────────────────────────────
        _PickupStopsCard(order: order),
        if (order.pickupStops?.isNotEmpty ?? false) const SizedBox(height: 16),

        // ── ITEMS CARD ───────────────────────────────────────────
        _OrderItemsCard(order: order),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATUS CARD  (extracted from _OrderStatusContent.build)
// ─────────────────────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final Order order;
  final _StatusConfig cfg;
  final OrderStatus status;
  final bool hasRider;
  final bool canShowReceipt;

  const _StatusCard({
    required this.order,
    required this.cfg,
    required this.status,
    required this.hasRider,
    required this.canShowReceipt,
  });

  @override
  Widget build(BuildContext context) {
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
          // ── Colored header ───────────────────────────────
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
                      child:
                          Icon(cfg.icon, color: cfg.color, size: 28),
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

                // Chat actions
                _OrderChatActions(order: order),

                // Receipt button
                if (canShowReceipt) ...[
                  const SizedBox(height: 10),
                  _ReceiptButton(order: order),
                ],
              ],
            ),
          ),

          // ── Timeline ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: _OrderStatusTimeline(
              status: status,
              inPersonPickup: order.inPersonPickup,
            ),
          ),

          // ── Rider chip ────────────────────────────────────
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

class _ReceiptButton extends StatelessWidget {
  final Order order;
  const _ReceiptButton({required this.order});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderReceiptScreen(orderId: order.orderId),
            ),
          );
        },
        child: Container(
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
            child: const Icon(Icons.delivery_dining_rounded,
                color: primaryOrange, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Repartidor asignado',
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

// ─────────────────────────────────────────────────────────────────────────────
//  DETAILS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _DetailsCard extends StatelessWidget {
  final Order order;
  final bool hasRider;
  const _DetailsCard({required this.order, required this.hasRider});

  Widget _row({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
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

  @override
  Widget build(BuildContext context) {
    final stops = order.pickupStops;
    final pickupLabel = (stops != null && stops.isNotEmpty)
        ? '${stops.length} punto${stops.length == 1 ? '' : 's'} de recogida'
        : (order.pickup.addressSnapshot.isNotEmpty
            ? order.pickup.addressSnapshot
            : 'Sin dirección');

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
                child: const Icon(Icons.info_outline_rounded,
                    size: 17, color: textGray700),
              ),
              const SizedBox(width: 10),
              const Text(
                'Detalles del pedido',
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
          _Hairline(),
          const SizedBox(height: 14),

          _row(
            icon: Icons.payments_rounded,
            iconColor: const Color(0xFF059669),
            label: 'Total del pedido',
            value: '\$${order.amountTotal.toStringAsFixed(0)} CLP',
          ),
          const SizedBox(height: 12),
          _row(
            icon: Icons.store_rounded,
            iconColor: primaryOrange,
            label: 'Recogida',
            value: pickupLabel,
          ),
          if (!order.inPersonPickup) ...[
            const SizedBox(height: 12),
            _row(
              icon: Icons.location_on_rounded,
              iconColor: const Color(0xFF2563EB),
              label: 'Entrega',
              value: order.delivery.addressSnapshot.isNotEmpty
                  ? order.delivery.addressSnapshot
                  : 'Sin dirección',
            ),
            if (!hasRider) ...[
              const SizedBox(height: 12),
              _row(
                icon: Icons.delivery_dining_rounded,
                iconColor: textGray600,
                label: 'Repartidor',
                value: 'Aún no asignado',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ORDER ITEMS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _OrderItemsCard extends StatelessWidget {
  final Order order;
  const _OrderItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final items = order.items;

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
                child: const Icon(Icons.shopping_bag_rounded,
                    size: 17, color: primaryOrange),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Productos',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: backgroundGray50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderGray100),
                ),
                child: Text(
                  '${order.totalItems} items',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textGray600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          _Hairline(),
          const SizedBox(height: 14),

          if (items.isEmpty)
            const Text(
              'Sin productos',
              style: TextStyle(
                  color: textGray600, fontWeight: FontWeight.w600),
            )
          else
            ...List.generate(items.length, (index) {
              final item = items[index];
              final lineTotal = item.unitPriceSnapshot * item.qty;
              final isLast = index == items.length - 1;

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
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
                            const SizedBox(height: 3),
                            Text(
                              '${item.qty} × \$${item.unitPriceSnapshot.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: backgroundGray50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderGray100),
                        ),
                        child: Text(
                          '\$${lineTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: textGray900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast) ...[
                    const SizedBox(height: 12),
                    _Hairline(),
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
            _StepData('Coordinado', 'Retiro coordinado con el donador'),
            _StepData('Listo', 'El donador dejó listo el pedido'),
            _StepData('Retirado', 'Pedido completado'),
          ]
        : [
            _StepData('En espera', 'Buscando repartidor'),
            _StepData('Aceptado', 'Un rider tomó tu pedido'),
            _StepData('En camino', 'Pedido en ruta'),
            _StepData('Entregado', 'Pedido finalizado'),
          ];

    return Column(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // connector
          final connectorIndex = i ~/ 2;
          return _Connector(done: active > connectorIndex);
        }
        final stepIndex = i ~/ 2;
        final s = steps[stepIndex];
        return _TimelineStep(
          title: s.title,
          subtitle: s.subtitle,
          index: stepIndex,
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
            color: done ? categoryTextGreen : borderGray100,
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

    final Color dotColor;
    final Color textColor;
    final Color subtitleColor;
    final Widget dotChild;

    if (done) {
      dotColor = categoryTextGreen.withOpacity(0.14);
      textColor = categoryTextGreen;
      subtitleColor = textGray600;
      dotChild = const Icon(Icons.check_rounded,
          color: categoryTextGreen, size: 16);
    } else if (current) {
      dotColor = primaryOrange.withOpacity(0.14);
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
      dotColor = const Color(0xFFF0F0F0);
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
              color: dotColor,
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
                      fontWeight: FontWeight.w500),
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
//  STATUS BANNER
// ─────────────────────────────────────────────────────────────────────────────
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
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.info_outline_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textGray700,
                    fontSize: 12,
                    height: 1.4,
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
//  STATUS MESSAGE  (loading / error empty states)
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
              child: const Icon(Icons.receipt_long_rounded,
                  size: 36, color: primaryOrange),
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
//  CHAT ACTIONS
// ─────────────────────────────────────────────────────────────────────────────
class _OrderChatActions extends ConsumerWidget {
  final Order order;
  const _OrderChatActions({required this.order});

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
        if ((chat.lastMessageSenderId ?? '').trim() == currentUserId)
          return 0;
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

  Future<List<_SellerChatChoice>> _resolveSellerChoices(WidgetRef ref) async {
    final repo = ref.read(offersRepositoryProvider);
    final itemsByOfferId = {for (final i in order.items) i.offerId: i};
    final offerIds =
        itemsByOfferId.keys.where((id) => id.trim().isNotEmpty).toSet();
    if (offerIds.isEmpty) return const <_SellerChatChoice>[];

    final offers =
        await Future.wait(offerIds.map((id) => repo.getOfferById(id)));

    final choices = <_SellerChatChoice>[];
    for (final offer in offers.whereType<Offer>()) {
      final sellerId = offer.heroId.trim();
      if (sellerId.isEmpty) continue;
      final offerId = offer.offerId.trim();
      if (offerId.isEmpty) continue;
      final title = itemsByOfferId[offerId]?.titleSnapshot;
      choices.add(_SellerChatChoice(
        sellerId: sellerId,
        offerId: offerId,
        itemTitle: (title != null && title.trim().isNotEmpty) ? title : null,
      ));
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
    final legacyChatId =
        '${ChatType.heroRider.jsonValue}_order_${order.orderId}';

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
      final legacyBuyerId = (data['buyerId'] as String?) ??
          (data['heroId'] as String?) ??
          '';
      final legacyRiderId = (data['riderId'] as String?) ?? '';
      final rawParticipantIds = data['participantIds'];
      final participantIds = rawParticipantIds is List
          ? rawParticipantIds
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
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

    final chatId =
        docNew.exists ? newChatId : (legacyOk ? legacyChatId : newChatId);
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
      BuildContext context, WidgetRef ref) async {
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
          offerId: c.offerId);
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
        offerId: selected.offerId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRider = order.rider.isAssigned &&
        (order.rider.assignedRiderId?.isNotEmpty ?? false);
    final riderName = order.rider.riderNameSnapshot ?? 'Rider';
    final riderId = order.rider.assignedRiderId;
    final riderAsync = (hasRider && riderId != null)
        ? ref.watch(userByIdStreamProvider(riderId))
        : const AsyncValue<User?>.data(null);
    final riderPhotoUrl = riderAsync.maybeWhen(
      data: (u) => u?.profilePhotoUrl,
      orElse: () => null,
    );

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

    final sellerIds = order.items
        .map((i) => i.sellerHeroIdSnapshot.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    final singleSellerId =
        sellerIds.length == 1 ? sellerIds.first : null;
    final sellerAsync = (singleSellerId != null)
        ? ref.watch(userByIdStreamProvider(singleSellerId))
        : const AsyncValue<User?>.data(null);
    final sellerName = sellerAsync.maybeWhen(
      data: (u) => (u?.fullName ?? '').trim(),
      orElse: () => '',
    );
    final sellerPhotoUrl = sellerAsync.maybeWhen(
      data: (u) => u?.profilePhotoUrl,
      orElse: () => null,
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
            icon: Icons.delivery_dining_rounded,
            label: '$riderName (Rider)',
            onTap: () => _openRiderChat(Navigator.of(context), ref),
            avatarUrl: riderPhotoUrl,
          ),
        if (hasRider) const SizedBox(width: 6),
        _ChatChipButton(
          icon: Icons.storefront_outlined,
          label: singleSellerId != null
              ? ((sellerName.isNotEmpty ? sellerName : 'Donador') +
                  ' (Donador)')
              : 'Donadores',
          badgeCount: sellerBadgeCount,
          onTap: () => _pickAndOpenSellerChat(context, ref),
          avatarUrl: singleSellerId != null ? sellerPhotoUrl : null,
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
//  SELLER PICKER SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _SellerPickerSheet extends ConsumerWidget {
  final List<_SellerChatChoice> choices;
  const _SellerPickerSheet({required this.choices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  child: const Icon(Icons.storefront_outlined,
                      size: 17, color: primaryOrange),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Selecciona un donador',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            ...choices.map((c) {
              final asyncUser = ref.watch(userByIdStreamProvider(c.sellerId));
              final sellerName = asyncUser.maybeWhen(
                data: (u) =>
                    (u?.fullName.trim().isNotEmpty ?? false)
                        ? u!.fullName
                        : 'Hero Donador',
                orElse: () => 'Hero Donador',
              );
              final itemTitle =
                  (c.itemTitle != null && c.itemTitle!.trim().isNotEmpty)
                      ? c.itemTitle!
                      : 'Artículo';

              return GestureDetector(
                onTap: () => Navigator.of(context).pop(
                  _SellerChatChoice(
                      sellerId: c.sellerId,
                      offerId: c.offerId,
                      itemTitle: c.itemTitle),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: backgroundGray50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderGray100),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.storefront_outlined,
                            color: primaryOrange, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              itemTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sellerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: textGray600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: textGray600, size: 20),
                    ],
                  ),
                ),
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

// ─────────────────────────────────────────────────────────────────────────────
//  DELIVERY CONFIRMATION CARD
// ─────────────────────────────────────────────────────────────────────────────
class _DeliveryConfirmationCard extends StatelessWidget {
  final Order order;
  const _DeliveryConfirmationCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: categoryTextGreen.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: categoryTextGreen.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: categoryTextGreen,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: categoryTextGreen.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¿Recibiste el paquete?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Confirma que recibiste tu pedido',
                      style: TextStyle(
                        fontSize: 12,
                        color: textGray700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DriverRatingScreen(order: order),
                      ),
                    );
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: categoryTextGreen,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: categoryTextGreen.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Sí, lo recibí',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Función de reporte en desarrollo'),
                      ),
                    );
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                          color: primaryOrange.withOpacity(0.4),
                          width: 1.5),
                    ),
                    child: const Center(
                      child: Text(
                        'Reportar problema',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: primaryOrange,
                        ),
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

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// White card wrapper with subtle shadow — used by all section cards
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

/// Hair-line divider
class _Hairline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFF2F2F2));
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
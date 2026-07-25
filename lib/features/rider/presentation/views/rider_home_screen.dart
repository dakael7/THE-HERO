import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../../../core/config/env.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/services/rider_commission_calculator.dart';
import '../../../../domain/config/pricing_config_provider.dart';
import '../widgets/rider_bottom_nav.dart';
import '../widgets/rider_header.dart';
import '../viewmodels/rider_home_viewmodel.dart';
import '../widgets/rider_home_metrics_dashboard.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart'
    as profile;
import '../../../shared/profile/presentation/views/profile_screen.dart'
    as profile_view;
import '../providers/rider_nearby_providers.dart';
import '../providers/rider_payout_summary_provider.dart';
import '../providers/rider_cumulative_stats_provider.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/order_status.dart';
import '../../domain/entities/nearby_order.dart';
import 'rider_delivery_map_screen.dart';
import 'delivery_details_screen.dart';
import '../../../shared/profile/presentation/views/rut_verification_screen.dart';
import '../../../shared/profile/presentation/widgets/rut_verification_cta_banner.dart';
import '../../../hero/orders/presentation/views/order_receipt_screen.dart';
import '../../../hero/payment/providers/payment_providers.dart';
import '../../../../domain/entities/payment.dart';

final mapControllerProvider = StateProvider<gmap.GoogleMapController?>(
  (ref) => null,
);

class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _ResolvedAddressText extends StatefulWidget {
  final String snapshot;
  final GeoPoint geo;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;

  const _ResolvedAddressText({
    required this.snapshot,
    required this.geo,
    required this.style,
    required this.maxLines,
    required this.overflow,
  });

  @override
  State<_ResolvedAddressText> createState() => _ResolvedAddressTextState();
}

class _ResolvedAddressTextState extends State<_ResolvedAddressText> {
  static final Map<String, String> _cache = <String, String>{};
  String? _resolved;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ResolvedAddressText oldWidget) {
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

  String _sanitizeAddress(String value) {
    final trimmed = value.trim();

    final plusCodeAtStart = RegExp(
      r'^\s*([A-Z0-9]{4,8}\+[A-Z0-9]{2,3})(?:\s+|,\s*)',
    );
    final removedLeading = trimmed.replaceFirst(plusCodeAtStart, '').trim();

    final plusCodeAtEnd = RegExp(
      r'(?:\s+|,\s*)([A-Z0-9]{4,8}\+[A-Z0-9]{2,3})\s*$',
    );
    final removedPlusCode = removedLeading.replaceAll(plusCodeAtEnd, '').trim();

    return removedPlusCode.replaceAll(RegExp(r'[\s,]+$'), '').trim();
  }

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

      final results = decoded['results'];
      if (results is! List || results.isEmpty) return;

      final first = results.first;
      if (first is! Map<String, dynamic>) return;

      final formatted = first['formatted_address'];
      if (formatted is! String || formatted.trim().isEmpty) return;

      final resolved = _sanitizeAddress(formatted);
      _cache[key] = resolved;
      setState(() => _resolved = resolved);
    } catch (_) {
      // swallow
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = (_resolved ?? widget.snapshot).trim();
    return Text(
      _loading && (text.isEmpty || text.startsWith('Lat:'))
          ? 'Resolviendo dirección...'
          : text,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen> {
  String? _selectedOrderId;
  gmap.GoogleMapController? _mapController;
  ProviderSubscription<gmap.GoogleMapController?>? _mapControllerSub;

  static const gmap.LatLng _fallbackCenter = gmap.LatLng(-33.4489, -70.6693);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(riderHomeViewModelProvider.notifier).reset();
    });
    _mapControllerSub = ref.listenManual(mapControllerProvider, (
      previous,
      next,
    ) {
      _mapController = next;
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _mapControllerSub?.close();
    super.dispose();
  }

  void _selectOrder(String orderId, double lat, double lng) {
    setState(() => _selectedOrderId = orderId);
    final controller = ref.read(mapControllerProvider);
    controller?.animateCamera(
      gmap.CameraUpdate.newLatLng(gmap.LatLng(lat, lng)),
    );
  }

  void _openDeliveryMap(String orderId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RiderDeliveryMapScreen(orderId: orderId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(
      riderHomeViewModelProvider.select((state) => state.selectedNavIndex),
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: selectedIndex != 0 && selectedIndex != 3
          ? AppBar(
              backgroundColor: primaryYellow,
              foregroundColor: textGray900,
              elevation: 0,
              title: Text(
                _getTitle(selectedIndex),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              automaticallyImplyLeading: false,
            )
          : null,
      body: _buildBody(selectedIndex),
      bottomNavigationBar: const RiderBottomNav(),
    );
  }

  String _getTitle(int index) {
    switch (index) {
      case 1:
        return 'En vivo';
      case 2:
        return 'Pedidos';
      case 3:
        return 'Mi Perfil';
      default:
        return '';
    }
  }

  String _formatTime(DateTime dateTime) {
    final formatter = DateFormat('HH:mm');
    return formatter.format(dateTime);
  }

  String _activeDeliveryActionLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.assigned:
        return 'Ir a la recogida';
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return 'Ir a la entrega';
      default:
        return 'Continuar entrega';
    }
  }

  Widget _buildBody(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildRequestsTab();
      case 2:
        return _buildActiveDeliveries();
      case 3:
        return profile_view.ProfileScreen(
          isRiderProfile: true,
          onBackPressed: () {
            ref.read(riderHomeViewModelProvider.notifier).selectNavItem(0);
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHomeTab() {
    final profileAsync = ref.watch(profile.profileStreamProvider);

    return profileAsync.when(
      loading: () => CustomScrollView(
        slivers: [
          const RiderHeader(),
          const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
          ),
        ],
      ),
      error: (e, _) => CustomScrollView(
        slivers: [
          const RiderHeader(),
          SliverFillRemaining(
            child: _buildEmptyState(
              icon: Icons.error_outline,
              title: 'Error de perfil',
              message: 'No pudimos cargar tu información de perfil',
            ),
          ),
        ],
      ),
      data: (user) {
        if (user == null) {
          return CustomScrollView(
            slivers: [
              const RiderHeader(),
              SliverFillRemaining(
                child: _buildEmptyState(
                  icon: Icons.login,
                  title: 'Sesión requerida',
                  message: 'Inicia sesión para ver tu panel',
                ),
              ),
            ],
          );
        }

        final cumulativeAsync = ref.watch(
          riderCumulativeStatsProvider(user.id),
        );
        final ordersAsync = ref.watch(riderOrdersProvider(user.id));
        final riderProfile = user.riderProfile;
        final rating = riderProfile?.rating ?? 0.0;
        final devCheckoutBypass = Env.devCheckoutBypass;

        final pendingAsync = ref.watch(riderPendingEarningsProvider(user.id));
        final pendingAmount = pendingAsync.asData?.value;
        final cumulative = cumulativeAsync.asData?.value;
        final orders = ordersAsync.asData?.value ?? const <Order>[];
        final computedFailedTrips = orders
            .where((o) => o.status == OrderStatus.failed)
            .length;

        final effectiveDeliveredTrips = cumulative?.completedTrips ?? 0;
        final canceledTrips = cumulative?.canceledTrips ?? 0;
        final effectiveTotalTrips = cumulative?.totalTrips ?? 0;
        final effectiveFailedTrips = computedFailedTrips;
        final effectiveCompletionRate =
            (effectiveDeliveredTrips + canceledTrips + effectiveFailedTrips) ==
                0
            ? 0.0
            : effectiveDeliveredTrips /
                  (effectiveDeliveredTrips +
                      canceledTrips +
                      effectiveFailedTrips);

        final balanceAmount =
            pendingAmount ?? cumulative?.pendingBalance ?? 0.0;

        return CustomScrollView(
          slivers: [
            const RiderHeader(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (!devCheckoutBypass)
                      RutVerificationCtaBanner(
                        user: user,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RutVerificationScreen(),
                            ),
                          );
                        },
                      ),
                    if (!devCheckoutBypass && !user.isRutVerified)
                      const SizedBox(height: 16),
                    RiderHomeMetricsDashboard(
                      headlineTitle: 'Saldo a favor',
                      headlineAmount: balanceAmount,
                      totalTrips: effectiveTotalTrips,
                      averageRating: rating,
                      canceledTrips: canceledTrips,
                      completionRate: effectiveCompletionRate,
                      onTapViewRequests: () {
                        ref
                            .read(riderHomeViewModelProvider.notifier)
                            .selectNavItem(1);
                      },
                    ),
                    const SizedBox(height: 16),
                    _infoCard(
                      iconBg: const Color(0xFFFFF7ED),
                      icon: Icons.access_time,
                      iconColor: const Color(0xFFEA580C),
                      title: 'Horario sugerido',
                      subtitle:
                          'Mayor demanda entre 12:00 - 14:00 y 19:00 - 21:00',
                    ),
                    const SizedBox(height: 12),
                    _infoCard(
                      iconBg: const Color(0xFFF5F3FF),
                      icon: Icons.location_on_outlined,
                      iconColor: const Color(0xFF7C3AED),
                      title: 'Zonas activas',
                      subtitle:
                          'Las Condes, Providencia y Ñuñoa con más pedidos ahora',
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoCard({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: textGray900.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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
      ),
    );
  }

  Widget _buildRequestsTab() {
    final locAsync = ref.watch(riderLocationStreamProvider);

    final center = locAsync.maybeWhen(
      data: (loc) => gmap.LatLng(loc.latitude, loc.longitude),
      orElse: () => _fallbackCenter,
    );

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _MapHeaderDelegate(
            child: _PersistentMapWidget(
              initialCenter: center,
              selectedOrderId: _selectedOrderId,
              onSelectOrder: _selectOrder,
            ),
          ),
        ),
        _OrderListSliver(
          selectedOrderId: _selectedOrderId,
          onSelectOrder: _selectOrder,
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: textGray600.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textGray900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: textGray600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDeliveries() {
    final profileAsync = ref.watch(profile.profileStreamProvider);

    return profileAsync.when(
      data: (user) {
        if (user == null) {
          return _buildEmptyState(
            icon: Icons.login,
            title: 'Sesión requerida',
            message: 'Inicia sesión para ver tus entregas activas',
          );
        }

        final ordersAsync = ref.watch(riderOrdersProvider(user.id));

        return ordersAsync.when(
          data: (orders) {
            final active = orders.where((o) => o.status.isActive).toList();

            if (active.isEmpty) {
              return _buildEmptyState(
                icon: Icons.delivery_dining_outlined,
                title: 'Sin entregas activas',
                message:
                    'Acepta pedidos desde la pestaña de solicitudes para empezar a ganar',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: active.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final order = active[index];
                return _buildActiveDeliveryCard(order);
              },
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: primaryOrange),
          ),
          error: (e, _) => _buildEmptyState(
            icon: Icons.error_outline,
            title: 'Error al cargar entregas',
            message: 'No pudimos cargar tus entregas activas',
          ),
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: primaryOrange)),
      error: (e, _) => _buildEmptyState(
        icon: Icons.error_outline,
        title: 'Error de perfil',
        message: 'No pudimos cargar tu información de perfil',
      ),
    );
  }

  Widget _buildActiveDeliveryCard(Order order) {
    final currentStatus = order.status;

    final paymentAsync = ref.watch(
      watchPaymentByOrderIdProvider(order.orderId),
    );
    final isPaymentLoading = paymentAsync.isLoading;
    final payment = paymentAsync.asData?.value;
    final isCashPayment =
        order.rider.isCashOrder ||
        payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final hasKnownPaymentMethod = !isPaymentLoading || order.rider.isCashOrder;

    final commissionConfig = ref.watch(riderCommissionConfigProvider);
    final earnings = RiderCommissionCalculator.calculateCommissionWith(
      deliveryFee: order.deliveryFee,
      serviceFeeCLP: commissionConfig.serviceFeeCLP,
      taxPercentage: commissionConfig.taxPercentage,
    );

    final amountToShow = !hasKnownPaymentMethod
        ? null
        : (isCashPayment
              ? order.amountTotal.toDouble()
              : earnings.netEarnings + order.tip);
    final amountLabel = !hasKnownPaymentMethod
        ? 'Calculando'
        : isCashPayment
        ? 'Cobras en efectivo'
        : 'Ganas por este pedido';
    final amountCaption = !hasKnownPaymentMethod
        ? null
        : (isCashPayment
              ? 'Se descuenta de tu saldo'
              : (order.tip > 0
                    ? 'Incluye propina \$${order.tip.toStringAsFixed(0)}'
                    : null));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openDeliveryMap(order.orderId),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Orange header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: primaryOrange,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido HRO-${order.orderId}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amountLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amountToShow == null
                              ? 'Cargando...'
                              : '\$${amountToShow.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (amountCaption != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            amountCaption,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      currentStatus.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pickup
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Retiro',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _ResolvedAddressText(
                              snapshot: order.pickup.addressSnapshot,
                              geo: order.pickup.geo,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: textGray900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (order.timestamps.pickedUpAt != null)
                              const SizedBox(height: 4),
                            if (order.timestamps.pickedUpAt != null)
                              Text(
                                'Retirado a las ${_formatTime(order.timestamps.pickedUpAt!)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Delivery
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Entrega',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _ResolvedAddressText(
                              snapshot: order.delivery.addressSnapshot,
                              geo: order.delivery.geo,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: textGray900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (order.timestamps.deliveredAt != null)
                              const SizedBox(height: 4),
                            if (order.timestamps.deliveredAt != null)
                              Text(
                                'Entregado a las ${_formatTime(order.timestamps.deliveredAt!)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openDeliveryMap(order.orderId),
                      icon: const Icon(Icons.navigation_outlined, size: 18),
                      label: Text(
                        _activeDeliveryActionLabel(currentStatus),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
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

                  if (order.status != OrderStatus.pendingPayment) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OrderReceiptScreen(
                                orderId: order.orderId,
                                isRiderView: true,
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
}

// =========================================================================
// MAPA PERSISTENTE (no se recrea en cada rebuild)
// =========================================================================

class _PersistentMapWidget extends ConsumerStatefulWidget {
  final gmap.LatLng initialCenter;
  final String? selectedOrderId;
  final void Function(String, double, double) onSelectOrder;

  const _PersistentMapWidget({
    required this.initialCenter,
    required this.selectedOrderId,
    required this.onSelectOrder,
  });

  @override
  ConsumerState<_PersistentMapWidget> createState() =>
      _PersistentMapWidgetState();
}

class _PersistentMapWidgetState extends ConsumerState<_PersistentMapWidget> {
  Set<gmap.Marker> _markers = {};
  gmap.LatLng? _lastRiderPosition;
  gmap.GoogleMapController? _mapController;
  bool _listening = false;
  Set<String> _lastOrderIds = {};
  String? _lastSelectedOrderId;
  bool _initialCameraSet = false;

  ProviderSubscription<AsyncValue<List<NearbyOrder>>>? _nearbyOrdersSub;
  ProviderSubscription<AsyncValue<dynamic>>? _riderLocationSub;

  @override
  void initState() {
    super.initState();
    _ensureListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialBuild();
    });
  }

  @override
  void dispose() {
    _nearbyOrdersSub?.close();
    _riderLocationSub?.close();
    super.dispose();
  }

  void _ensureListeners() {
    if (_listening) return;
    _listening = true;

    _nearbyOrdersSub = ref.listenManual(nearbyOrdersProvider, (prev, next) {
      if (mounted && next.hasValue) {
        _rebuildMarkers(next.value ?? []);
      }
    });

    _riderLocationSub = ref.listenManual(riderLocationStreamProvider, (
      prev,
      next,
    ) {
      if (mounted && next.hasValue && next.value != null) {
        final newPos = gmap.LatLng(next.value!.latitude, next.value!.longitude);
        if (_lastRiderPosition != newPos) {
          _lastRiderPosition = newPos;
          _rebuildMarkers(ref.read(nearbyOrdersProvider).value ?? []);

          // Move camera to new position smoothly
          _mapController?.animateCamera(gmap.CameraUpdate.newLatLng(newPos));

          debugPrint(
            'ðŸ“ [Map] Rider moved to: ${newPos.latitude}, ${newPos.longitude}',
          );
        }
      }
    });
  }

  void _initialBuild() {
    final nearby = ref.read(nearbyOrdersProvider).value ?? [];
    final loc = ref.read(riderLocationStreamProvider).value;
    if (loc != null) {
      _lastRiderPosition = gmap.LatLng(loc.latitude, loc.longitude);
      _rebuildMarkers(nearby);

      // Set initial camera position
      if (!_initialCameraSet && _mapController != null) {
        _mapController!.animateCamera(
          gmap.CameraUpdate.newCameraPosition(
            gmap.CameraPosition(target: _lastRiderPosition!, zoom: 14),
          ),
        );
        _initialCameraSet = true;
        debugPrint(
          'ðŸ“ [Map] Initial position set to: ${_lastRiderPosition!.latitude}, ${_lastRiderPosition!.longitude}',
        );
      }
    }
  }

  void _rebuildMarkers(List<NearbyOrder> nearby) {
    if (!mounted) return;

    final currentOrderIds = nearby.map((n) => n.order.orderId).toSet();
    final orderIdsChanged =
        _lastOrderIds.length != currentOrderIds.length ||
        !_lastOrderIds.containsAll(currentOrderIds);
    final selectedChanged = _lastSelectedOrderId != widget.selectedOrderId;

    if (!orderIdsChanged && !selectedChanged && _markers.isNotEmpty) {
      return;
    }

    _lastOrderIds = currentOrderIds;
    _lastSelectedOrderId = widget.selectedOrderId;

    setState(() {
      _markers = {
        // Marcador del rider
        if (_lastRiderPosition != null)
          gmap.Marker(
            markerId: const gmap.MarkerId('me'),
            position: _lastRiderPosition!,
            icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
              gmap.BitmapDescriptor.hueAzure,
            ),
            infoWindow: const gmap.InfoWindow(title: 'Tu ubicación'),
          ),
        // Marcadores de pedidos
        ...nearby.map((n) {
          final hasDistance = n.distanceMeters != null;
          final distanceKm = hasDistance ? (n.distanceMeters! / 1000) : 0;
          final isSelected = widget.selectedOrderId == n.order.orderId;

          return gmap.Marker(
            markerId: gmap.MarkerId(n.order.orderId),
            position: gmap.LatLng(
              n.order.pickup.geo.latitude,
              n.order.pickup.geo.longitude,
            ),
            icon: isSelected
                ? gmap.BitmapDescriptor.defaultMarkerWithHue(
                    gmap.BitmapDescriptor.hueOrange,
                  )
                : gmap.BitmapDescriptor.defaultMarker,
            infoWindow: gmap.InfoWindow(
              title: 'Pedido',
              snippet: hasDistance
                  ? '${distanceKm.toStringAsFixed(1)} km'
                  : 'Distancia no disponible',
            ),
            onTap: () {
              widget.onSelectOrder(
                n.order.orderId,
                n.order.pickup.geo.latitude,
                n.order.pickup.geo.longitude,
              );
            },
          );
        }),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return gmap.GoogleMap(
      key: const ValueKey('single_rider_map'),
      initialCameraPosition: gmap.CameraPosition(
        target: widget.initialCenter,
        zoom: 13,
      ),
      markers: _markers,
      onMapCreated: (controller) {
        _mapController = controller;
        ref.read(mapControllerProvider.notifier).state = controller;

        if (_lastRiderPosition != null && !_initialCameraSet) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _mapController != null) {
              _mapController!.animateCamera(
                gmap.CameraUpdate.newCameraPosition(
                  gmap.CameraPosition(target: _lastRiderPosition!, zoom: 14),
                ),
              );
              _initialCameraSet = true;
              debugPrint('ðŸ“ [Map] Camera positioned at rider location');
            }
          });
        }
      },
      liteModeEnabled: Env.mapsLiteMode,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      trafficEnabled: false,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: false,
      compassEnabled: false,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      minMaxZoomPreference: const gmap.MinMaxZoomPreference(10.0, 18.0),
      mapType: gmap.MapType.normal,
    );
  }
}

// =========================================================================
// LISTA DE PEDIDOS CERCANOS
// =========================================================================

class _OrderListSliver extends ConsumerWidget {
  final String? selectedOrderId;
  final void Function(String, double, double) onSelectOrder;

  const _OrderListSliver({
    required this.selectedOrderId,
    required this.onSelectOrder,
  });

  double _computePickupToDeliveryKm(NearbyOrder n) {
    final pickupPoints =
        (n.order.pickupStops != null && n.order.pickupStops!.isNotEmpty)
        ? n.order.pickupStops!.map((s) => s.geo).toList(growable: false)
        : <GeoPoint>[n.order.pickup.geo];

    final deliveryGeo = n.order.delivery.geo;
    if (pickupPoints.isEmpty) return 0.0;

    double totalKm = 0.0;
    for (int i = 0; i < pickupPoints.length - 1; i++) {
      totalKm += _calculateDistanceKm(
        pickupPoints[i].latitude,
        pickupPoints[i].longitude,
        pickupPoints[i + 1].latitude,
        pickupPoints[i + 1].longitude,
      );
    }
    totalKm += _calculateDistanceKm(
      pickupPoints.last.latitude,
      pickupPoints.last.longitude,
      deliveryGeo.latitude,
      deliveryGeo.longitude,
    );

    if (!totalKm.isFinite || totalKm < 0) return 0.0;
    return totalKm;
  }

  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.asin(math.sqrt(a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearbyAsync = ref.watch(nearbyOrdersProvider);

    return nearbyAsync.when(
      data: (nearby) {
        if (nearby.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.radar,
                      size: 72,
                      color: textGray600.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No hay pedidos cercanos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mantente disponible y revisa que tu ubicación esté activa.',
                      style: TextStyle(color: textGray600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final n = nearby[index];
              return _buildOrderCard(context, ref, n);
            }, childCount: nearby.length),
          ),
        );
      },
      loading: () => const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator(color: primaryOrange)),
      ),
      error: (error, stack) => SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 72,
                  color: textGray600.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Error al cargar pedidos',
                  style: TextStyle(
                    color: textGray900,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'No pudimos cargar los pedidos cercanos',
                  style: TextStyle(color: textGray600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, WidgetRef ref, NearbyOrder n) {
    final isSelected = selectedOrderId == n.order.orderId;

    final paymentAsync = ref.watch(
      watchPaymentByOrderIdProvider(n.order.orderId),
    );
    final isPaymentLoading = paymentAsync.isLoading;
    final payment = paymentAsync.asData?.value;
    final isCashPayment =
        payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');

    final commissionConfig2 = ref.watch(riderCommissionConfigProvider);
    final earnings = RiderCommissionCalculator.calculateCommissionWith(
      deliveryFee: n.order.deliveryFee,
      serviceFeeCLP: commissionConfig2.serviceFeeCLP,
      taxPercentage: commissionConfig2.taxPercentage,
    );

    final amountToShow = isPaymentLoading
        ? null
        : (isCashPayment
              ? n.order.amountTotal.toDouble()
              : earnings.netEarnings + n.order.tip);
    final amountLabel = isPaymentLoading
        ? 'Calculando'
        : (isCashPayment ? 'Cobras en efectivo' : 'Ganas por este pedido');
    final amountCaption = isPaymentLoading
        ? null
        : (isCashPayment
              ? 'Requiere saldo \$${n.order.amountTotal.toStringAsFixed(0)}'
              : (n.order.tip > 0
                    ? 'Incluye propina \$${n.order.tip.toStringAsFixed(0)}'
                    : null));

    final distanceToPickupKm = n.distanceMeters != null
        ? (n.distanceMeters! / 1000)
        : null;

    final estimatedKm = n.order.requirements.estimatedDistanceKm;
    final orderDistanceKm = (estimatedKm.isFinite && estimatedKm > 0.01)
        ? estimatedKm
        : _computePickupToDeliveryKm(n);

    final totalWeightKg = n.order.requirements.weightKg;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: primaryOrange, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          onSelectOrder(
            n.order.orderId,
            n.order.pickup.geo.latitude,
            n.order.pickup.geo.longitude,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Orange header with order ID and price
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: primaryOrange,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido HRO-${n.order.orderId}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amountLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amountToShow == null
                              ? 'Cargando...'
                              : '\$${amountToShow.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (amountCaption != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            amountCaption,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isPaymentLoading
                          ? Colors.white.withValues(alpha: 0.15)
                          : isCashPayment
                          ? const Color(0xFF4CAF50).withValues(alpha: 0.9)
                          : const Color(0xFF2196F3).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPaymentLoading)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        else ...[
                          Icon(
                            isCashPayment
                                ? Icons.payments_outlined
                                : Icons.credit_card,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCashPayment ? 'EFECTIVO' : 'APP',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Pickup and delivery info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pickup
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Retiro',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _ResolvedAddressText(
                              snapshot: n.order.pickup.addressSnapshot,
                              geo: n.order.pickup.geo,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: textGray900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (n.order.pickupSchedule != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                n.order.pickupSchedule!
                                    .getScheduleDescription(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textGray600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Delivery
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Entrega',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _ResolvedAddressText(
                              snapshot: n.order.delivery.addressSnapshot,
                              geo: n.order.delivery.geo,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textGray900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              n.order.delivery.recipientName,
                              style: TextStyle(
                                fontSize: 12,
                                color: textGray600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Distance, weight, and details link
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            distanceToPickupKm != null
                                ? 'A retiro ${distanceToPickupKm.toStringAsFixed(1)} km'
                                : 'A retiro -',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textGray700,
                            ),
                          ),
                          Text(
                            '•',
                            style: TextStyle(fontSize: 13, color: textGray600),
                          ),
                          Text(
                            'Del pedido ${orderDistanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textGray700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${totalWeightKg.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textGray700,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              // Validate coordinates before opening details
                              final hasValidPickup =
                                  n.order.pickup.geo.latitude != 0 &&
                                  n.order.pickup.geo.longitude != 0;
                              final hasValidDelivery =
                                  n.order.delivery.geo.latitude != 0 &&
                                  n.order.delivery.geo.longitude != 0;

                              if (!hasValidPickup || !hasValidDelivery) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: const [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Este pedido no tiene coordenadas válidas. Contacta al soporte.',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: Colors.orange,
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      DeliveryDetailsScreen(order: n.order),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                Text(
                                  'Ver detalles',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: primaryOrange,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 16,
                                  color: primaryOrange,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// DELEGATE DEL HEADER DEL MAPA (no se reconstruye)
// =========================================================================

class _MapHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  static const double height = 250;

  const _MapHeaderDelegate({required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(_MapHeaderDelegate oldDelegate) => false;
}

import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/map_camera_utils.dart';
import '../../../../domain/entities/location_entity.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../../domain/services/rider_commission_calculator.dart';
import '../../../../domain/config/pricing_config_provider.dart';
import '../../../../data/repositories/location_repository_impl.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../shared/profile/presentation/views/rut_verification_screen.dart';
import '../../../hero/payment/providers/payment_providers.dart';
import '../../domain/services/rider_tracking_service.dart';
import '../../domain/services/directions_service.dart';
import '../providers/rider_nearby_providers.dart';
import 'rider_delivery_map_screen.dart';
import '../../../../domain/entities/payment.dart';
import 'rider_earnings_screen.dart';

final _currentDeviceLocationProvider =
    FutureProvider.autoDispose<LocationEntity>((ref) {
      final repo = LocationRepositoryImpl();
      return repo.getCurrentLocation();
    });

final _routeProvider = FutureProvider.autoDispose
    .family<DirectionsRoute, _RouteRequestParams>((ref, params) {
      final service = DirectionsService();
      return service.getRoute(
        pickupLat: params.originLat,
        pickupLng: params.originLng,
        deliveryLat: params.destinationLat,
        deliveryLng: params.destinationLng,
        waypoints: params.waypoints,
      );
    });

class _RouteRequestParams {
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final List<DirectionsPoint> waypoints;
  final String waypointsKey;

  const _RouteRequestParams({
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    this.waypoints = const <DirectionsPoint>[],
    this.waypointsKey = '',
  });

  @override
  bool operator ==(Object other) {
    return other is _RouteRequestParams &&
        other.originLat == originLat &&
        other.originLng == originLng &&
        other.destinationLat == destinationLat &&
        other.destinationLng == destinationLng &&
        other.waypointsKey == waypointsKey;
  }

  @override
  int get hashCode => Object.hash(
    originLat,
    originLng,
    destinationLat,
    destinationLng,
    waypointsKey,
  );
}

class DeliveryDetailsScreen extends ConsumerStatefulWidget {
  final Order order;

  const DeliveryDetailsScreen({super.key, required this.order});

  @override
  ConsumerState<DeliveryDetailsScreen> createState() =>
      _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends ConsumerState<DeliveryDetailsScreen> {
  gmap.GoogleMapController? _mapController;
  String? _lastRouteDebug;
  bool _isClaiming = false;

  String _normalizeErrorMessage(Object e) {
    final raw = e.toString();
    const prefix = 'Exception: ';
    if (raw.startsWith(prefix)) return raw.substring(prefix.length).trim();

    return raw.trim();
  }

  Map<String, double?> _extractCashHoldNumbers(String message) {
    final matches = RegExp(r'\$\s*([0-9]+(?:\.[0-9]+)?)').allMatches(message);
    final values = <double>[];
    for (final m in matches) {
      final s = m.group(1);
      if (s == null) continue;
      final v = double.tryParse(s);
      if (v == null) continue;
      values.add(v);
    }
    return {
      'required': values.isNotEmpty ? values[0] : null,
      'available': values.length >= 2 ? values[1] : null,
    };
  }

  Future<void> _showCashAcceptErrorSheet({required String message}) async {
    final normalized = message.trim();
    final numbers = _extractCashHoldNumbers(normalized);
    final required = numbers['required'];
    final available = numbers['available'];
    final hasNumbers = required != null || available != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Icon + title
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F0),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.payments_outlined,
                        color: Color(0xFFDC2626),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No puedes aceptar este pedido',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: textGray900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Saldo insuficiente para pago en efectivo',
                            style: TextStyle(
                              fontSize: 12,
                              color: textGray600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: textGray600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  'Este pedido requiere pago en efectivo. Para tomarlo debes tener saldo disponible suficiente.',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textGray700,
                    height: 1.5,
                  ),
                ),

                if (hasNumbers) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8E8E8)),
                    ),
                    child: Column(
                      children: [
                        if (required != null)
                          _CashRow(
                            label: 'Requerido (efectivo)',
                            value: '\$${required.toStringAsFixed(0)}',
                            valueColor: textGray900,
                          ),
                        if (required != null && available != null)
                          const SizedBox(height: 10),
                        if (available != null)
                          _CashRow(
                            label: 'Disponible',
                            value: '\$${available.toStringAsFixed(0)}',
                            valueColor: const Color(0xFFDC2626),
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text(
                    normalized,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textGray600,
                      height: 1.4,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RiderEarningsScreen(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: primaryOrange),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text(
                              'Ver ganancias',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: primaryOrange,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: primaryOrange,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: primaryOrange.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Entendido',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
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
          ),
        );
      },
    );
  }

  double _roundCoord(double v) => double.parse(v.toStringAsFixed(5));

  bool _isValidLatLng(gmap.LatLng p) {
    if (!p.latitude.isFinite || !p.longitude.isFinite) return false;
    if (p.latitude == 0.0 && p.longitude == 0.0) return false;
    if (p.latitude.abs() > 90 || p.longitude.abs() > 180) return false;
    return true;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final claimState = ref.watch(orderNotifierProvider);

    final commissionConfig = ref.watch(riderCommissionConfigProvider);
    final stops = widget.order.pickupStops ?? const [];
    final earnings = RiderCommissionCalculator.calculateCommissionWith(
      deliveryFee: widget.order.deliveryFee,
      serviceFeeCLP: commissionConfig.serviceFeeCLP,
      taxPercentage: commissionConfig.taxPercentage,
    );

    final paymentAsync = ref.watch(
      watchPaymentByOrderIdProvider(widget.order.orderId),
    );
    final isPaymentLoading = paymentAsync.isLoading;
    final payment = paymentAsync.asData?.value;
    final isCashPayment =
        widget.order.rider.isCashOrder ||
        payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final hasKnownPaymentMethod =
        !isPaymentLoading || widget.order.rider.isCashOrder;
    final amountToShow = !hasKnownPaymentMethod
        ? null
        : (isCashPayment
              ? widget.order.amountTotal.toDouble()
              : earnings.netEarnings + widget.order.tip);
    final amountLabel = !hasKnownPaymentMethod
        ? 'calculando'
        : (isCashPayment ? 'a cobrar' : 'ganancia');
    final amountCaption = !hasKnownPaymentMethod
        ? null
        : (isCashPayment ? 'descuenta saldo' : null);

    final primaryPickupGeo = stops.isNotEmpty
        ? stops.first.geo
        : widget.order.pickup.geo;
    final pickupLat = primaryPickupGeo.latitude;
    final pickupLng = primaryPickupGeo.longitude;
    final deliveryLat = widget.order.delivery.geo.latitude;
    final deliveryLng = widget.order.delivery.geo.longitude;

    final deviceRiderLocationAsync = ref.watch(riderLocationStreamProvider);
    final deviceLatLng = deviceRiderLocationAsync.maybeWhen(
      data: (loc) => gmap.LatLng(loc.latitude, loc.longitude),
      orElse: () => null,
    );

    final currentLocationAsync = ref.watch(_currentDeviceLocationProvider);
    final currentLatLng = currentLocationAsync.maybeWhen(
      data: (loc) => gmap.LatLng(loc.latitude, loc.longitude),
      orElse: () => null,
    );

    final effectiveRiderLatLng =
        (deviceLatLng != null && _isValidLatLng(deviceLatLng))
        ? deviceLatLng
        : ((currentLatLng != null && _isValidLatLng(currentLatLng))
              ? currentLatLng
              : null);

    final riderLatLngStable = effectiveRiderLatLng == null
        ? null
        : gmap.LatLng(
            _roundCoord(effectiveRiderLatLng.latitude),
            _roundCoord(effectiveRiderLatLng.longitude),
          );

    final showFullRoute =
        riderLatLngStable != null && _isValidLatLng(riderLatLngStable);

    final pickupPoints = stops.isNotEmpty
        ? stops.map((s) => s.geo).toList()
        : <GeoPoint>[widget.order.pickup.geo];
    final pickupWaypoints = pickupPoints
        .map(
          (geo) =>
              DirectionsPoint(latitude: geo.latitude, longitude: geo.longitude),
        )
        .toList(growable: false);
    final pickupWaypointsKey = pickupPoints
        .map(
          (geo) =>
              '${geo.latitude.toStringAsFixed(5)},${geo.longitude.toStringAsFixed(5)}',
        )
        .join('|');

    final routeAsync = ref.watch(
      _routeProvider(
        _RouteRequestParams(
          originLat: showFullRoute ? riderLatLngStable.latitude : pickupLat,
          originLng: showFullRoute ? riderLatLngStable.longitude : pickupLng,
          destinationLat: deliveryLat,
          destinationLng: deliveryLng,
          waypoints: showFullRoute
              ? pickupWaypoints
              : const <DirectionsPoint>[],
          waypointsKey: showFullRoute ? pickupWaypointsKey : '',
        ),
      ),
    );

    final pickupLocation = gmap.LatLng(pickupLat, pickupLng);
    final deliveryLocation = gmap.LatLng(deliveryLat, deliveryLng);
    final allPickupLocations = stops.isNotEmpty
        ? stops
              .map((s) => gmap.LatLng(s.geo.latitude, s.geo.longitude))
              .toList(growable: false)
        : <gmap.LatLng>[pickupLocation];
    final initialCenter = gmap.LatLng(
      (pickupLat + deliveryLat) / 2,
      (pickupLng + deliveryLng) / 2,
    );

    final polylinePoints = routeAsync.maybeWhen(
      data: (route) =>
          route.path.map((p) => gmap.LatLng(p.latitude, p.longitude)).toList(),
      orElse: () => <gmap.LatLng>[],
    );

    final distanceText = routeAsync.maybeWhen(
      data: (r) => '${(r.distanceMeters / 1000).toStringAsFixed(1)} km',
      orElse: () => '0.0 km',
    );

    final durationText = routeAsync.maybeWhen(
      data: (r) => '${(r.durationSeconds / 60).ceil()} min',
      orElse: () => '~15 min',
    );

    final debug =
        'rider=${riderLatLngStable == null ? '-' : '${riderLatLngStable.latitude},${riderLatLngStable.longitude}'} '
        'pickup=$pickupLat,$pickupLng delivery=$deliveryLat,$deliveryLng '
        'fullRoute=$showFullRoute '
        'src=${effectiveRiderLatLng == null ? '-' : (deviceLatLng != null ? 'stream' : 'current')}';
    if (_lastRouteDebug != debug) {
      _lastRouteDebug = debug;
      // ignore: avoid_print
      print('🧭 [DeliveryDetailsMap] $debug');
    }

    final pickupMarkers = <gmap.Marker>{
      if (stops.isEmpty)
        gmap.Marker(
          markerId: const gmap.MarkerId('pickup'),
          position: pickupLocation,
          icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
            gmap.BitmapDescriptor.hueOrange,
          ),
          infoWindow: const gmap.InfoWindow(title: 'Recogida'),
        )
      else
        for (int i = 0; i < stops.length; i++)
          gmap.Marker(
            markerId: gmap.MarkerId('pickup_${i + 1}'),
            position: gmap.LatLng(
              stops[i].geo.latitude,
              stops[i].geo.longitude,
            ),
            icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
              gmap.BitmapDescriptor.hueOrange,
            ),
            infoWindow: gmap.InfoWindow(
              title: 'Recogida ${i + 1}/${stops.length}',
            ),
          ),
    };

    gmap.LatLngBounds boundsForPoints(List<gmap.LatLng> points) {
      final lats = points.map((p) => p.latitude).toList();
      final lngs = points.map((p) => p.longitude).toList();
      return gmap.LatLngBounds(
        southwest: gmap.LatLng(
          lats.reduce((a, b) => a < b ? a : b),
          lngs.reduce((a, b) => a < b ? a : b),
        ),
        northeast: gmap.LatLng(
          lats.reduce((a, b) => a > b ? a : b),
          lngs.reduce((a, b) => a > b ? a : b),
        ),
      );
    }

    final cameraPoints = <gmap.LatLng>[
      if (showFullRoute) riderLatLngStable,
      ...allPickupLocations,
      deliveryLocation,
    ];

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: Stack(
        children: [
          // ── MAPA ──
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: gmap.GoogleMap(
                initialCameraPosition: gmap.CameraPosition(
                  target: initialCenter,
                  zoom: 13.5,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (polylinePoints.isNotEmpty) {
                    unawaited(() async {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 16),
                      );
                      if (!mounted || _mapController == null) return;
                      final moved = await animateCameraWhenMapReady(
                        controller: _mapController!,
                        cameraUpdateBuilder: () =>
                            gmap.CameraUpdate.newLatLngBounds(
                              boundsForPoints(cameraPoints),
                              80,
                            ),
                      );
                      if (!moved) {
                        debugPrint(
                          '[DeliveryDetails] Could not fit map bounds',
                        );
                      }
                    }());
                  }
                },
                polylines: {
                  if (polylinePoints.isNotEmpty)
                    gmap.Polyline(
                      polylineId: const gmap.PolylineId('route'),
                      points: polylinePoints,
                      width: 5,
                      color: primaryOrange,
                      patterns: [
                        gmap.PatternItem.dash(20),
                        gmap.PatternItem.gap(10),
                      ],
                    ),
                },
                markers: {
                  ...pickupMarkers,
                  gmap.Marker(
                    markerId: const gmap.MarkerId('delivery'),
                    position: deliveryLocation,
                    icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                      gmap.BitmapDescriptor.hueGreen,
                    ),
                    infoWindow: const gmap.InfoWindow(title: 'Entrega'),
                  ),
                  if (effectiveRiderLatLng != null &&
                      _isValidLatLng(effectiveRiderLatLng))
                    gmap.Marker(
                      markerId: const gmap.MarkerId('rider'),
                      position: effectiveRiderLatLng,
                      icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                        gmap.BitmapDescriptor.hueAzure,
                      ),
                      infoWindow: const gmap.InfoWindow(title: 'Rider (Tú)'),
                    ),
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),

          // ── TOP BAR ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    // Back button
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: textGray900,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Title pill
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_shipping_outlined,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Detalles de Entrega',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── DISTANCE / TIME CARDS ──
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 72),
                child: Row(
                  children: [
                    Expanded(
                      child: _MapInfoChip(
                        icon: Icons.route_outlined,
                        label: showFullRoute
                            ? 'Desde tu ubicación'
                            : 'Distancia del pedido',
                        value: distanceText,
                        color: primaryOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MapInfoChip(
                        icon: Icons.access_time_rounded,
                        label: 'Tiempo estimado',
                        value: durationText,
                        color: categoryTextBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── BOTTOM SHEET ──
          DraggableScrollableSheet(
            initialChildSize: 0.44,
            minChildSize: 0.44,
            maxChildSize: 0.44,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        children: [
                          // Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0E0E0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── ORDER HEADER ──
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Product image
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: backgroundGray50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderGray100),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child:
                                    widget.order.items.isNotEmpty &&
                                        widget
                                            .order
                                            .items
                                            .first
                                            .imageUrlSnapshot
                                            .startsWith('http')
                                    ? CachedNetworkImage(
                                        imageUrl: widget
                                            .order
                                            .items
                                            .first
                                            .imageUrlSnapshot,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: primaryOrange,
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            const Icon(
                                              Icons
                                                  .image_not_supported_outlined,
                                              color: textGray600,
                                            ),
                                      )
                                    : const Icon(
                                        Icons.shopping_bag_outlined,
                                        size: 32,
                                        color: textGray600,
                                      ),
                              ),
                              const SizedBox(width: 14),

                              // Order info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pedido #${widget.order.orderId.substring(0, widget.order.orderId.length.clamp(0, 8)).toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: textGray900,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final buyerAsync = ref.watch(
                                          userByIdProvider(widget.order.heroId),
                                        );
                                        final buyerName = buyerAsync.maybeWhen(
                                          data: (u) =>
                                              (u?.fullName.trim().isNotEmpty ??
                                                  false)
                                              ? u!.fullName
                                              : 'Hero',
                                          orElse: () => 'Hero',
                                        );
                                        final buyerPhotoUrl = buyerAsync
                                            .maybeWhen(
                                              data: (u) => u?.profilePhotoUrl,
                                              orElse: () => null,
                                            );
                                        final hasBuyerPhoto =
                                            (buyerPhotoUrl ?? '')
                                                .trim()
                                                .isNotEmpty;

                                        return Row(
                                          children: [
                                            Container(
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                color: primaryOrange.withValues(
                                                  alpha: 0.12,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: hasBuyerPhoto
                                                  ? Image.network(
                                                      buyerPhotoUrl!.trim(),
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) {
                                                            return const Icon(
                                                              Icons.person,
                                                              color:
                                                                  primaryOrange,
                                                              size: 14,
                                                            );
                                                          },
                                                    )
                                                  : const Icon(
                                                      Icons.person,
                                                      color: primaryOrange,
                                                      size: 14,
                                                    ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                buyerName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: textGray700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        _TagChip(
                                          icon: Icons.scale_outlined,
                                          label:
                                              '${widget.order.requirements.weightKg.toStringAsFixed(1)} kg',
                                          bgColor: categoryBgBlue,
                                          textColor: categoryTextBlue,
                                        ),
                                        const SizedBox(width: 6),
                                        if (isCashPayment)
                                          _TagChip(
                                            icon: Icons.payments_outlined,
                                            label: 'Efectivo',
                                            bgColor: const Color(0xFFFFF3E0),
                                            textColor: const Color(0xFFFF6B00),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Earnings badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF22C55E),
                                      Color(0xFF16A34A),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF16A34A,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      amountToShow == null
                                          ? '...'
                                          : '\$${amountToShow.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    Text(
                                      amountLabel,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (amountCaption != null)
                                      Text(
                                        amountCaption,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Divider
                          Container(height: 1, color: const Color(0xFFF0F0F0)),
                          const SizedBox(height: 16),

                          // ── PRODUCTS ──
                          _OrderItemsCard(order: widget.order),
                          const SizedBox(height: 16),

                          // ── CONCIERGE INFO ──
                          if (widget.order.useConcierge &&
                              widget.order.conciergeInfo != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFFFCC00),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3E0),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.business_rounded,
                                          color: primaryOrange,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Retiro en Portería',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: textGray900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _buildConciergeInfoRow(
                                    icon: Icons.apartment_rounded,
                                    label: 'Edificio',
                                    value: widget
                                        .order
                                        .conciergeInfo!
                                        .buildingName,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildConciergeInfoRow(
                                    icon: Icons.inventory_2_rounded,
                                    label: 'Paquete',
                                    value:
                                        widget.order.conciergeInfo!.packageName,
                                  ),
                                  if (widget
                                      .order
                                      .conciergeInfo!
                                      .instructions
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _buildConciergeInfoRow(
                                      icon: Icons.info_outline_rounded,
                                      label: 'Instrucciones',
                                      value: widget
                                          .order
                                          .conciergeInfo!
                                          .instructions,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // ── ADDRESSES ──
                          _buildAddressCard(
                            icon: Icons.radio_button_checked_rounded,
                            label: (stops.isNotEmpty)
                                ? 'Recogidas'
                                : 'Recogida',
                            dotColor: primaryOrange,
                            addressWidget: stops.isNotEmpty
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: List.generate(stops.length, (i) {
                                      final stop = stops[i];
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          top: i == 0 ? 0 : 8,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: primaryOrange,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${i + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _ResolvedAddressText(
                                                snapshot: stop.addressSnapshot,
                                                geo: stop.geo,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: textGray900,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _ResolvedAddressText(
                                        snapshot:
                                            widget.order.pickup.addressSnapshot,
                                        geo: widget.order.pickup.geo,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: textGray900,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (widget.order.pickup.instructions
                                          .trim()
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            widget.order.pickup.instructions
                                                .trim(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: textGray600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                            onTap: () async {
                              final geo = widget.order.pickup.geo;
                              final copy =
                                  '${widget.order.pickup.addressSnapshot}\n(${geo.latitude}, ${geo.longitude})';
                              await Clipboard.setData(
                                ClipboardData(text: copy),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Recogida copiada al portapapeles',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),

                          // Route line
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 22,
                              top: 2,
                              bottom: 2,
                            ),
                            child: Column(
                              children: List.generate(
                                3,
                                (_) => Container(
                                  width: 2,
                                  height: 6,
                                  margin: const EdgeInsets.only(bottom: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDDDDDD),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          _buildAddressCard(
                            icon: Icons.location_on_rounded,
                            label: 'Entrega',
                            dotColor: categoryTextGreen,
                            addressWidget: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ResolvedAddressText(
                                  snapshot:
                                      widget.order.delivery.addressSnapshot,
                                  geo: widget.order.delivery.geo,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textGray900,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.order.delivery.instructions
                                    .trim()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      widget.order.delivery.instructions.trim(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: textGray600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () async {
                              final geo = widget.order.delivery.geo;
                              final copy =
                                  '${widget.order.delivery.addressSnapshot}\n(${geo.latitude}, ${geo.longitude})';
                              await Clipboard.setData(
                                ClipboardData(text: copy),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Entrega copiada al portapapeles',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),

                          if (widget.order.delivery.deliverToReception) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: categoryBgGreen,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: categoryTextGreen),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.apartment_outlined,
                                    size: 16,
                                    color: categoryTextGreen,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Entregar en portería/recepción',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: categoryTextGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),

                    // ── ACCEPT BUTTON ──
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: GestureDetector(
                          onTap: (claimState.isLoading || _isClaiming)
                              ? null
                              : () async {
                                  await _claimOrder(context);
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              color: (claimState.isLoading || _isClaiming)
                                  ? primaryOrange.withValues(alpha: 0.7)
                                  : primaryOrange,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: (claimState.isLoading || _isClaiming)
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: primaryOrange.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                            ),
                            child: (claimState.isLoading || _isClaiming)
                                ? const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'Aceptar Entrega',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard({
    required IconData icon,
    required String label,
    required Color dotColor,
    required Widget addressWidget,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
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
                color: dotColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: dotColor, size: 18),
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
                      fontWeight: FontWeight.w700,
                      color: textGray600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  addressWidget,
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.copy_outlined, size: 16, color: textGray600),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConciergeInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: primaryOrange, size: 16),
        const SizedBox(width: 8),
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
              const SizedBox(height: 2),
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

  Future<void> _claimOrder(BuildContext context) async {
    if (_isClaiming) return;
    setState(() {
      _isClaiming = true;
    });
    final profile = await ref.read(profileStreamProvider.future);
    final user = profile;
    final devCheckoutBypass = Env.devCheckoutBypass;
    if (user == null || (!devCheckoutBypass && user.riderProfile == null)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes completar tu perfil de rider.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _isClaiming = false;
        });
      }
      return;
    }

    if (!devCheckoutBypass && !user.isRutVerified) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes verificar tu RUT para aceptar pedidos.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RutVerificationScreen()),
        );
      }
      if (mounted) {
        setState(() {
          _isClaiming = false;
        });
      }
      return;
    }

    final riderVehicleType = devCheckoutBypass
        ? VehicleType.truck
        : user.riderProfile!.activeVehicleTypeEnum;
    final riderName = user.identity.fullName.trim().isNotEmpty
        ? user.identity.fullName
        : 'Rider dev';
    final riderPhone = user.contact.phoneNumber;

    try {
      await ref
          .read(orderNotifierProvider.notifier)
          .claimOrder(
            orderId: widget.order.orderId,
            riderId: user.id,
            riderVehicleType: riderVehicleType,
            riderName: riderName,
            riderPhone: riderPhone,
            order: widget.order,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('¡Pedido aceptado exitosamente!'),
              ],
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                RiderDeliveryMapScreen(orderId: widget.order.orderId),
          ),
        );
      }

      Future(() async {
        try {
          final trackingService = RiderTrackingService(
            firestore: FirebaseFirestore.instance,
            locationRepository: LocationRepositoryImpl(),
          );
          await trackingService.startTracking(
            orderId: widget.order.orderId,
            riderId: user.id,
          );
        } catch (trackingError) {
          // ignore: avoid_print
          print('⚠️ Warning: Failed to start tracking: $trackingError');
        }
      });
    } catch (e) {
      if (context.mounted) {
        final msg = _normalizeErrorMessage(e);
        final alreadyClaimed =
            msg.toLowerCase().contains('pedido ya tiene rider asignado') ||
            msg.toLowerCase().contains('pedido ya no está disponible');
        final isCashHoldError =
            msg.toLowerCase().contains('pago en efectivo') ||
            msg.toLowerCase().contains('pendiente por pagar');
        if (alreadyClaimed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Este pedido ya fue tomado por otro rider.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).maybePop();
        } else if (isCashHoldError) {
          await _showCashAcceptErrorSheet(message: msg);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al aceptar: $msg'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClaiming = false;
        });
      }
    }
  }
}

// ─────────────────────────────────────────────
//  MAP INFO CHIP
// ─────────────────────────────────────────────
class _MapInfoChip extends StatelessWidget {
  const _MapInfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: textGray600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  TAG CHIP
// ─────────────────────────────────────────────
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  CASH ROW (bottom sheet)
// ─────────────────────────────────────────────
class _CashRow extends StatelessWidget {
  const _CashRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textGray600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  RESOLVED ADDRESS TEXT
// ─────────────────────────────────────────────
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

// ─────────────────────────────────────────────
//  ORDER ITEMS CARD
// ─────────────────────────────────────────────
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
        color: backgroundGray50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  size: 14,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Productos',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: borderGray100,
                  borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 12),
          Container(height: 1, color: borderGray100),
          const SizedBox(height: 12),

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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: Colors.white,
                        child: item.imageUrlSnapshot.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrlSnapshot,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryOrange,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                      Icons.image_not_supported_outlined,
                                      color: textGray600,
                                      size: 16,
                                    ),
                              )
                            : const Icon(
                                Icons.shopping_bag_outlined,
                                size: 18,
                                color: textGray600,
                              ),
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
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: textGray900,
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
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '\$${lineTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: textGray900,
                        ),
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

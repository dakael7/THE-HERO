import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/config/env.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/location_entity.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/services/rider_commission_calculator.dart';
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

final _currentDeviceLocationProvider = FutureProvider.autoDispose<LocationEntity>((
  ref,
) {
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
  int get hashCode =>
      Object.hash(
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

    final stops = widget.order.pickupStops ?? const [];
    final earnings = RiderCommissionCalculator.calculateCommission(
      deliveryFee: widget.order.deliveryFee,
    );

    final paymentAsync = ref.watch(
      watchPaymentByOrderIdProvider(widget.order.orderId),
    );
    final payment = paymentAsync.asData?.value;
    final isCashPayment = payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final baseAmountToShow = isCashPayment
        ? (widget.order.amountTotal - widget.order.tip)
            .clamp(0, double.infinity)
        : earnings.netEarnings;
    final primaryPickupGeo = (stops.isNotEmpty) ? stops.first.geo : widget.order.pickup.geo;
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

    final effectiveRiderLatLng = (deviceLatLng != null && _isValidLatLng(deviceLatLng))
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

    final showFullRoute = riderLatLngStable != null && _isValidLatLng(riderLatLngStable);

    final pickupPoints = stops.isNotEmpty ? stops.map((s) => s.geo).toList() : <GeoPoint>[widget.order.pickup.geo];
    final pickupWaypoints = pickupPoints
        .map(
          (geo) => DirectionsPoint(
            latitude: geo.latitude,
            longitude: geo.longitude,
          ),
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
          waypoints: showFullRoute ? pickupWaypoints : const <DirectionsPoint>[],
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

    final debug = 'rider=${riderLatLngStable == null ? '-' : '${riderLatLngStable.latitude},${riderLatLngStable.longitude}'} '
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
      final minLat = lats.reduce((a, b) => a < b ? a : b);
      final maxLat = lats.reduce((a, b) => a > b ? a : b);
      final minLng = lngs.reduce((a, b) => a < b ? a : b);
      final maxLng = lngs.reduce((a, b) => a > b ? a : b);
      return gmap.LatLngBounds(
        southwest: gmap.LatLng(minLat, minLng),
        northeast: gmap.LatLng(maxLat, maxLng),
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
          // Mapa con la ruta
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
                  // Ajustar bounds para mostrar marcadores
                  if (polylinePoints.isNotEmpty) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (_mapController != null) {
                        _mapController!.animateCamera(
                          gmap.CameraUpdate.newLatLngBounds(
                            boundsForPoints(cameraPoints),
                            80,
                          ),
                        );
                      }
                    });
                  }
                },
                polylines: {
                  if (polylinePoints.isNotEmpty)
                    gmap.Polyline(
                      polylineId: const gmap.PolylineId('route'),
                      points: polylinePoints,
                      width: 4,
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

          // Header con botón de volver
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: textGray900),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.20),
                          ),
                        ),
                        child: const Text(
                          'Detalles de Entrega',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Info cards flotantes sobre el mapa
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 70),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        icon: Icons.route_outlined,
                        label: showFullRoute
                            ? 'Distancia (desde tu ubicación)'
                            : 'Distancia (del pedido)',
                        value: distanceText,
                        color: primaryOrange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoCard(
                        icon: Icons.access_time_outlined,
                        label: 'Tiempo est.',
                        value: durationText,
                        color: categoryTextBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Panel de detalles deslizable
          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.42,
            maxChildSize: 0.42,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        children: [
                          // Indicador de arrastre
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: textGray600.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                    // Producto y earnings
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Imagen del producto
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 70,
                            height: 70,
                            color: backgroundGray50,
                            child:
                                widget.order.items.isNotEmpty &&
                                    widget.order.items.first.imageUrlSnapshot
                                        .startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: widget
                                        .order
                                        .items
                                        .first
                                        .imageUrlSnapshot,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: primaryOrange,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        const Icon(
                                          Icons.image_not_supported_outlined,
                                          color: textGray600,
                                        ),
                                  )
                                : const Icon(
                                    Icons.shopping_bag_outlined,
                                    size: 32,
                                    color: textGray600,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Info del producto
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pedido HRO-${widget.order.orderId}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: textGray900,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: categoryBgBlue,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.scale_outlined,
                                      size: 14,
                                      color: categoryTextBlue,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${widget.order.requirements.weightKg.toStringAsFixed(1)} kg',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: categoryTextBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Earnings badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF4CAF50,
                                ).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.payments_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '\$${baseAmountToShow.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Divider
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: borderGray100.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 20),

                    _OrderItemsCard(order: widget.order),
                    const SizedBox(height: 20),

                    // Concierge Info Section (if applicable)
                    if (widget.order.useConcierge &&
                        widget.order.conciergeInfo != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9E6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primaryYellow, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(
                                  Icons.business,
                                  color: primaryOrange,
                                  size: 24,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Retiro en Portería',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: textGray900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildConciergeInfoRow(
                              icon: Icons.apartment,
                              label: 'Edificio',
                              value: widget.order.conciergeInfo!.buildingName,
                            ),
                            const SizedBox(height: 8),
                            _buildConciergeInfoRow(
                              icon: Icons.inventory_2,
                              label: 'Paquete',
                              value: widget.order.conciergeInfo!.packageName,
                            ),
                            if (widget
                                .order
                                .conciergeInfo!
                                .instructions
                                .isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildConciergeInfoRow(
                                icon: Icons.info_outline,
                                label: 'Instrucciones',
                                value: widget.order.conciergeInfo!.instructions,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Direcciones compactas
                    _buildCompactAddressRow(
                      icon: Icons.location_on_outlined,
                      label: (widget.order.pickupStops != null &&
                              widget.order.pickupStops!.isNotEmpty)
                          ? 'Recogidas'
                          : 'Recogida',
                      address: (widget.order.pickupStops != null &&
                              widget.order.pickupStops!.isNotEmpty)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: List.generate(
                                widget.order.pickupStops!.length,
                                (i) {
                                  final stop = widget.order.pickupStops![i];
                                  return Padding(
                                    padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${i + 1}. ',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: textGray900,
                                          ),
                                        ),
                                        Expanded(
                                          child: _ResolvedAddressText(
                                            snapshot: stop.addressSnapshot,
                                            geo: stop.geo,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: textGray900,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ResolvedAddressText(
                                  snapshot: widget.order.pickup.addressSnapshot,
                                  geo: widget.order.pickup.geo,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: textGray900,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.order.pickup.instructions.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      widget.order.pickup.instructions.trim(),
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
                      color: primaryOrange,
                      onTap: () async {
                        final geo = widget.order.pickup.geo;
                        final copy = '${widget.order.pickup.addressSnapshot}\n(${geo.latitude}, ${geo.longitude})';
                        await Clipboard.setData(ClipboardData(text: copy));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Recogida copiada al portapapeles'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildCompactAddressRow(
                      icon: Icons.flag_outlined,
                      label: 'Entrega',
                      address: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ResolvedAddressText(
                            snapshot: widget.order.delivery.addressSnapshot,
                            geo: widget.order.delivery.geo,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: textGray900,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.order.delivery.instructions.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
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
                      color: categoryTextGreen,
                      onTap: () async {
                        final geo = widget.order.delivery.geo;
                        final copy =
                            '${widget.order.delivery.addressSnapshot}\n(${geo.latitude}, ${geo.longitude})';
                        await Clipboard.setData(ClipboardData(text: copy));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Entrega copiada al portapapeles'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    if (widget.order.delivery.deliverToReception) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
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
                              size: 18,
                              color: categoryTextGreen,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Entregar en portería/recepción',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: categoryTextGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: claimState.isLoading
                                ? null
                                : () async {
                                    await _claimOrder(context);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              shadowColor:
                                  primaryOrange.withValues(alpha: 0.4),
                            ),
                            child: claimState.isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.check_circle_outline, size: 22),
                                      SizedBox(width: 8),
                                      Text(
                                        'Aceptar Entrega',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
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

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textGray600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAddressRow({
    required IconData icon,
    required String label,
    required Widget address,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundGray50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textGray600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    address,
                  ],
                ),
              ),
            ],
          ),
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
        Icon(icon, color: primaryOrange, size: 18),
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
                  fontWeight: FontWeight.w600,
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
    final profile = await ref.read(profileStreamProvider.future);
    final user = profile;
    if (user == null || user.riderProfile == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes completar tu perfil de rider.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!user.isRutVerified) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes verificar tu RUT para aceptar pedidos.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const RutVerificationScreen(),
          ),
        );
      }
      return;
    }

    final riderVehicleType = user.riderProfile!.activeVehicleTypeEnum;
    final riderName = user.identity.fullName;
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

      // Start tracking this order (non-blocking - don't fail claim if tracking fails)
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
        // Log tracking error but don't block the claim success
        // ignore: avoid_print
        print('⚠️ Warning: Failed to start tracking: $trackingError');
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('¡Pedido aceptado exitosamente!'),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al aceptar: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
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
    final raw = widget.snapshot.trim();
    final show = (_resolved != null && _resolved!.trim().isNotEmpty)
        ? _resolved!.trim()
        : (raw.isEmpty || raw.startsWith('Lat:') ? 'Ubicación en el mapa' : raw);

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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Productos',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 15,
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
                padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 42,
                        height: 42,
                        color: Colors.white,
                        child: item.imageUrlSnapshot.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrlSnapshot,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryOrange,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: textGray600,
                                  size: 18,
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

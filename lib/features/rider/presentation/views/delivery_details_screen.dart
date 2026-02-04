import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/order.dart';
import '../../../../data/repositories/location_repository_impl.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../domain/services/rider_tracking_service.dart';
import '../../domain/services/directions_service.dart';
import 'rider_delivery_map_screen.dart';

final _routeProvider = FutureProvider.autoDispose
    .family<DirectionsRoute, _RouteParams>((ref, params) {
      final service = DirectionsService();
      return service.getRoute(
        pickupLat: params.pickupLat,
        pickupLng: params.pickupLng,
        deliveryLat: params.deliveryLat,
        deliveryLng: params.deliveryLng,
      );
    });

class _RouteParams {
  final double pickupLat;
  final double pickupLng;
  final double deliveryLat;
  final double deliveryLng;

  const _RouteParams({
    required this.pickupLat,
    required this.pickupLng,
    required this.deliveryLat,
    required this.deliveryLng,
  });
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

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final claimState = ref.watch(orderNotifierProvider);

    // Extract data from order
    final pickupLat = widget.order.pickup.geo.latitude;
    final pickupLng = widget.order.pickup.geo.longitude;
    final deliveryLat = widget.order.delivery.geo.latitude;
    final deliveryLng = widget.order.delivery.geo.longitude;

    final routeAsync = ref.watch(
      _routeProvider(
        _RouteParams(
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          deliveryLat: deliveryLat,
          deliveryLng: deliveryLng,
        ),
      ),
    );

    final pickupLocation = gmap.LatLng(pickupLat, pickupLng);
    final deliveryLocation = gmap.LatLng(deliveryLat, deliveryLng);
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

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: Stack(
        children: [
          // Mapa con la ruta
          Positioned.fill(
            child: gmap.GoogleMap(
              initialCameraPosition: gmap.CameraPosition(
                target: initialCenter,
                zoom: 13.5,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                // Ajustar bounds para mostrar ambos marcadores
                if (polylinePoints.isNotEmpty) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_mapController != null) {
                      _mapController!.animateCamera(
                        gmap.CameraUpdate.newLatLngBounds(
                          _calculateBounds(pickupLocation, deliveryLocation),
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
                gmap.Marker(
                  markerId: const gmap.MarkerId('pickup'),
                  position: pickupLocation,
                  icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                    gmap.BitmapDescriptor.hueOrange,
                  ),
                  infoWindow: const gmap.InfoWindow(title: 'Recogida'),
                ),
                gmap.Marker(
                  markerId: const gmap.MarkerId('delivery'),
                  position: deliveryLocation,
                  icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                    gmap.BitmapDescriptor.hueGreen,
                  ),
                  infoWindow: const gmap.InfoWindow(title: 'Entrega'),
                ),
              },
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // Header con botón de volver
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
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
                  const Text(
                    'Detalles de Entrega',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Info cards flotantes sobre el mapa
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.route_outlined,
                    label: 'Distancia',
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

          // Panel de detalles deslizable
          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.42,
            maxChildSize: 0.85,
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
                                widget.order.items.isNotEmpty
                                    ? widget.order.items.first.titleSnapshot
                                    : 'Pedido',
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
                                '\$${widget.order.deliveryFee.toStringAsFixed(0)}',
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
                      label: 'Recogida',
                      address: widget.order.pickup.addressSnapshot,
                      color: primaryOrange,
                    ),
                    const SizedBox(height: 12),
                    _buildCompactAddressRow(
                      icon: Icons.flag_outlined,
                      label: 'Entrega',
                      address: widget.order.delivery.addressSnapshot,
                      color: categoryTextGreen,
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

                    // Botón de aceptar
                    SizedBox(
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
                          shadowColor: primaryOrange.withValues(alpha: 0.4),
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
    required String address,
    required Color color,
  }) {
    return Container(
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
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textGray900,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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

  gmap.LatLngBounds _calculateBounds(gmap.LatLng pos1, gmap.LatLng pos2) {
    final southwest = gmap.LatLng(
      pos1.latitude < pos2.latitude ? pos1.latitude : pos2.latitude,
      pos1.longitude < pos2.longitude ? pos1.longitude : pos2.longitude,
    );
    final northeast = gmap.LatLng(
      pos1.latitude > pos2.latitude ? pos1.latitude : pos2.latitude,
      pos1.longitude > pos2.longitude ? pos1.longitude : pos2.longitude,
    );
    return gmap.LatLngBounds(southwest: southwest, northeast: northeast);
  }

  Future<void> _claimOrder(BuildContext context) async {
    final profile = await ref.read(profileProvider.future);
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

    final riderVehicleType = user.riderProfile!.vehicle.type;
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

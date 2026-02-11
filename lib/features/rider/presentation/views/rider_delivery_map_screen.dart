import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/chat.dart';
import '../../../../domain/entities/chat_type.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../domain/services/directions_service.dart';
import '../providers/rider_location_provider.dart';

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

class RiderDeliveryMapScreen extends ConsumerStatefulWidget {
  final String orderId;

  const RiderDeliveryMapScreen({super.key, required this.orderId});

  @override
  ConsumerState<RiderDeliveryMapScreen> createState() =>
      _RiderDeliveryMapScreenState();
}

class _RiderDeliveryMapScreenState
    extends ConsumerState<RiderDeliveryMapScreen> {
  gmap.GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _openChat({required Order order}) async {
    final riderId = order.rider.assignedRiderId;
    if (riderId == null || riderId.isEmpty) {
      throw Exception('Pedido sin rider asignado');
    }

    final profileAsync = ref.read(profileProvider);
    final user = profileAsync.value;
    if (user == null) {
      throw Exception('Usuario no autenticado');
    }

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
      buyerName:
          'Cliente', // We don't have hero name in Order, will use generic
      riderId: riderId,
      riderName: user.fullName,
      orderId: order.orderId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(chatActionsProvider).ensureChatExists(chat);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
    );
  }

  Future<void> _setStatus(Order order, OrderStatus status) async {
    final notifier = ref.read(orderNotifierProvider.notifier);
    await notifier.updateStatus(order.orderId, _orderStatusToString(status));
  }

  static String _orderStatusToString(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
        return 'created';
      case OrderStatus.pendingPayment:
        return 'pending_payment';
      case OrderStatus.paid:
        return 'paid';
      case OrderStatus.queued:
        return 'queued';
      case OrderStatus.assigned:
        return 'assigned';
      case OrderStatus.pickedUp:
        return 'picked_up';
      case OrderStatus.inTransit:
        return 'in_transit';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.canceled:
        return 'canceled';
      case OrderStatus.failed:
        return 'failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdProvider(widget.orderId));

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Entrega en curso',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: orderAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Pedido no disponible'));
          }

          final pickupLat = order.pickup.geo.latitude;
          final pickupLng = order.pickup.geo.longitude;
          final deliveryLat = order.delivery.geo.latitude;
          final deliveryLng = order.delivery.geo.longitude;

          final pickupLocation = gmap.LatLng(pickupLat, pickupLng);
          final deliveryLocation = gmap.LatLng(deliveryLat, deliveryLng);

          // Watch rider's real-time location from Firestore
          final riderLocationAsync = ref.watch(
            riderLocationForOrderProvider(widget.orderId),
          );

          final initialCenter = gmap.LatLng(
            (pickupLat + deliveryLat) / 2,
            (pickupLng + deliveryLng) / 2,
          );

          // Get the main route from pickup to delivery
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

          final polylinePoints = routeAsync.maybeWhen(
            data: (route) => route.path
                .map((p) => gmap.LatLng(p.latitude, p.longitude))
                .toList(),
            orElse: () => <gmap.LatLng>[],
          );

          // Build markers set
          final markers = <gmap.Marker>{
            // Pickup marker
            gmap.Marker(
              markerId: const gmap.MarkerId('pickup'),
              position: pickupLocation,
              icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                gmap.BitmapDescriptor.hueOrange,
              ),
              infoWindow: const gmap.InfoWindow(title: 'Recogida'),
            ),
            // Delivery marker
            gmap.Marker(
              markerId: const gmap.MarkerId('delivery'),
              position: deliveryLocation,
              icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                gmap.BitmapDescriptor.hueGreen,
              ),
              infoWindow: const gmap.InfoWindow(title: 'Entrega'),
            ),
          };

          // Build polylines set
          final polylines = <gmap.Polyline>{};

          // Add rider marker and route to pickup if rider location is available
          riderLocationAsync.whenData((riderLoc) {
            if (riderLoc != null) {
              // Add rider marker
              markers.add(
                gmap.Marker(
                  markerId: const gmap.MarkerId('rider'),
                  position: gmap.LatLng(riderLoc.latitude, riderLoc.longitude),
                  icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                    gmap.BitmapDescriptor.hueAzure,
                  ),
                  infoWindow: const gmap.InfoWindow(title: 'Rider (Tú)'),
                ),
              );

              // Create route from rider to pickup (if order is not yet picked up)
              if (order.status == OrderStatus.assigned) {
                // For simplicity, draw a straight line from rider to pickup
                // In production, you'd want to fetch the actual route
                polylines.add(
                  gmap.Polyline(
                    polylineId: const gmap.PolylineId('rider_to_pickup'),
                    points: [
                      gmap.LatLng(riderLoc.latitude, riderLoc.longitude),
                      pickupLocation,
                    ],
                    width: 4,
                    color: const Color(0xFF3B82F6), // Blue color
                    patterns: [
                      gmap.PatternItem.dash(15),
                      gmap.PatternItem.gap(10),
                    ],
                  ),
                );
              }
            }
          });

          // Add main route from pickup to delivery
          if (polylinePoints.isNotEmpty) {
            polylines.add(
              gmap.Polyline(
                polylineId: const gmap.PolylineId('route'),
                points: polylinePoints,
                width: 4,
                color: primaryOrange,
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: gmap.GoogleMap(
                  initialCameraPosition: gmap.CameraPosition(
                    target: initialCenter,
                    zoom: 13.5,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    // Adjust camera to show all markers
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (_mapController != null) {
                        // Calculate bounds to include all points
                        riderLocationAsync.whenData((riderLoc) {
                          if (riderLoc != null) {
                            _mapController!.animateCamera(
                              gmap.CameraUpdate.newLatLngBounds(
                                _calculateBoundsForThreePoints(
                                  gmap.LatLng(
                                    riderLoc.latitude,
                                    riderLoc.longitude,
                                  ),
                                  pickupLocation,
                                  deliveryLocation,
                                ),
                                80,
                              ),
                            );
                          } else {
                            _mapController!.animateCamera(
                              gmap.CameraUpdate.newLatLngBounds(
                                _calculateBounds(
                                  pickupLocation,
                                  deliveryLocation,
                                ),
                                80,
                              ),
                            );
                          }
                        });
                      }
                    });
                  },
                  polylines: polylines,
                  markers: markers,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _BottomPanel(
                  order: order,
                  onChat: () async {
                    try {
                      await _openChat(order: order);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('No se pudo abrir chat: $e')),
                      );
                    }
                  },
                  onPickedUp: order.status == OrderStatus.assigned
                      ? () => _setStatus(order, OrderStatus.pickedUp)
                      : null,
                  onInTransit: (order.status == OrderStatus.pickedUp)
                      ? () => _setStatus(order, OrderStatus.inTransit)
                      : null,
                  onDelivered: (order.status == OrderStatus.inTransit)
                      ? () => _setStatus(order, OrderStatus.delivered)
                      : null,
                ),
              ),
            ],
          );
        },
      ),
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

  gmap.LatLngBounds _calculateBoundsForThreePoints(
    gmap.LatLng pos1,
    gmap.LatLng pos2,
    gmap.LatLng pos3,
  ) {
    final minLat = [
      pos1.latitude,
      pos2.latitude,
      pos3.latitude,
    ].reduce((a, b) => a < b ? a : b);
    final maxLat = [
      pos1.latitude,
      pos2.latitude,
      pos3.latitude,
    ].reduce((a, b) => a > b ? a : b);
    final minLng = [
      pos1.longitude,
      pos2.longitude,
      pos3.longitude,
    ].reduce((a, b) => a < b ? a : b);
    final maxLng = [
      pos1.longitude,
      pos2.longitude,
      pos3.longitude,
    ].reduce((a, b) => a > b ? a : b);

    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final Order order;
  final VoidCallback onChat;
  final VoidCallback? onPickedUp;
  final VoidCallback? onInTransit;
  final VoidCallback? onDelivered;

  const _BottomPanel({
    required this.order,
    required this.onChat,
    required this.onPickedUp,
    required this.onInTransit,
    required this.onDelivered,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Estado: ${order.status.displayName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
              ),
              IconButton(
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline),
                color: primaryOrange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ActionButton(label: 'Retirando (Picked up)', onPressed: onPickedUp),
          const SizedBox(height: 8),
          _ActionButton(label: 'En vía (In transit)', onPressed: onInTransit),
          const SizedBox(height: 8),
          _ActionButton(label: 'Entregado', onPressed: onDelivered),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _ActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed == null ? borderGray100 : primaryOrange,
          foregroundColor: onPressed == null ? textGray600 : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

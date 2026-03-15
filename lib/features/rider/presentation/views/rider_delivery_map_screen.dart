import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'dart:async';

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/chat.dart';
import '../../../../domain/entities/chat_type.dart';
import '../../../../domain/entities/offer.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../../domain/entities/payment.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../shared/chat/presentation/providers/chat_providers.dart';
import '../../../shared/chat/presentation/views/chat_conversation_screen.dart';
import 'rider_delivery_chats_screen.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../hero/payment/providers/payment_providers.dart';
import '../../../../data/repositories/location_repository_impl.dart';
import '../../domain/services/directions_service.dart';
import '../../domain/services/rider_tracking_service.dart';
import '../providers/rider_nearby_providers.dart';
import '../providers/rider_location_provider.dart';
import '../../../hero/orders/presentation/views/order_receipt_screen.dart';
import 'rider_home_screen.dart';

final _routeProvider = FutureProvider.autoDispose
    .family<DirectionsRoute?, _RouteRequestParams>((ref, params) {
      final service = DirectionsService();
      // ignore: avoid_print
      print(
        '🛰️ [_routeProvider] origin=${params.pickupLat},${params.pickupLng} '
        'destination=${params.deliveryLat},${params.deliveryLng}',
      );
      return service.getRoute(
        pickupLat: params.pickupLat,
        pickupLng: params.pickupLng,
        deliveryLat: params.deliveryLat,
        deliveryLng: params.deliveryLng,
        waypoints: params.waypoints,
      );
    });

final _offerByIdProvider = FutureProvider.autoDispose.family<Offer?, String>((
  ref,
  offerId,
) async {
  final repo = ref.read(offersRepositoryProvider);
  return repo.getOfferById(offerId);
});

class _RouteRequestParams {
  final double pickupLat;
  final double pickupLng;
  final double deliveryLat;
  final double deliveryLng;
  final List<DirectionsPoint> waypoints;
  final String waypointsKey;

  const _RouteRequestParams({
    required this.pickupLat,
    required this.pickupLng,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.waypoints,
    required this.waypointsKey,
  });

  @override
  bool operator ==(Object other) {
    return other is _RouteRequestParams &&
        other.pickupLat == pickupLat &&
        other.pickupLng == pickupLng &&
        other.deliveryLat == deliveryLat &&
        other.deliveryLng == deliveryLng &&
        other.waypointsKey == waypointsKey;
  }

  @override
  int get hashCode =>
      Object.hash(pickupLat, pickupLng, deliveryLat, deliveryLng, waypointsKey);
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
  gmap.LatLng? _lastCameraRider;
  StreamSubscription? _trackingSub;
  int _pickupStopIndex = 0;
  bool _arrivedAtPickupStop = false;

  double _roundCoord(double v) => double.parse(v.toStringAsFixed(5));

  Future<bool> _markPickupStopCompleted({
    required String orderId,
    required int stopIndex,
  }) async {
    try {
      final firestore = ref.read(firebaseFirestoreProvider);
      final riderUid = ref.read(firebaseAuthProvider).currentUser?.uid;
      // ignore: avoid_print
      print(
        '📌 [_markPickupStopCompleted] orderId=$orderId stopIndex=$stopIndex uid=$riderUid',
      );
      await firestore.collection('orders').doc(orderId).update({
        'pickupProgress.currentStopIndex': stopIndex,
        'pickupProgress.updatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ [_markPickupStopCompleted] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar progreso: $e')),
        );
      }
      return false;
    }
  }

  void _syncPickupIndexFromOrder(Order order) {
    final stops = order.pickupStops ?? const [];
    if (stops.isEmpty) return;

    final persisted = order.pickupProgressCurrentStopIndex;
    if (persisted == null) return;

    final clamped = persisted.clamp(0, stops.length - 1);
    if (clamped == _pickupStopIndex) return;

    setState(() {
      _pickupStopIndex = clamped;
      _arrivedAtPickupStop = false;
    });
  }

  Future<void> _cancelAsRider(Order order) async {
    final user = ref.read(profileProvider).value;
    if (user == null) {
      throw Exception('Usuario no autenticado');
    }

    final assignedId = order.rider.assignedRiderId;
    if (assignedId == null || assignedId.isEmpty || assignedId != user.id) {
      throw Exception('Pedido no asignado a este rider');
    }

    if (order.status != OrderStatus.assigned) {
      throw Exception('Solo puedes cancelar antes de recoger');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cancelar entrega'),
          content: const Text(
            'Solo puedes cancelar si aún no has recogido ningún punto. '
            'El pedido volverá a estar disponible para otros riders.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Volver'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await ref.read(orderNotifierProvider.notifier).unassignRiderAndRequeue(
          orderId: order.orderId,
          riderId: user.id,
        );

    await _trackingSub?.cancel();
    _trackingSub = null;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final user = ref.read(profileProvider).value;
        if (user == null) return;

        final order = await ref.read(orderByIdProvider(widget.orderId).future);
        if (order == null) return;

        final assignedRiderId = order.rider.assignedRiderId;
        if (assignedRiderId == null || assignedRiderId.isEmpty) return;
        if (assignedRiderId != user.id) return;

        final trackingService = RiderTrackingService(
          firestore: FirebaseFirestore.instance,
          locationRepository: LocationRepositoryImpl(),
        );
        _trackingSub = await trackingService.startTracking(
          orderId: widget.orderId,
          riderId: user.id,
        );
      } catch (e) {
        // ignore: avoid_print
        print('⚠️ [RiderDeliveryMap] Failed to start tracking: $e');
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _trackingSub?.cancel();
    super.dispose();
  }

  Future<void> _openChat({
    required Order order,
    required String buyerId,
    required String buyerName,
  }) async {
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
      buyerId: buyerId,
      riderId: riderId,
      orderId: order.orderId,
    );

    final chat = Chat(
      chatId: chatId,
      type: ChatType.heroRider,
      buyerId: buyerId,
      buyerName: buyerName,
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
    if (status == OrderStatus.delivered) {
      final okToDeliver = await _maybeConfirmCashPayment(orderId: order.orderId);
      if (!okToDeliver || !mounted) return;
    }

    final notifier = ref.read(orderNotifierProvider.notifier);
    try {
      await notifier.updateStatus(order.orderId, _orderStatusToString(status));
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ [RiderDeliveryMap] Failed to set status=${status.name} for orderId=${order.orderId}: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo avanzar: $e')),
      );
      return;
    }
    if (!mounted) return;

    if (status == OrderStatus.delivered) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _DeliveryCompletedScreen(orderId: order.orderId),
        ),
      );
    }
  }

  Future<bool> _maybeConfirmCashPayment({required String orderId}) async {
    final paymentRepo = ref.read(paymentRepositoryProvider);
    final payment = await paymentRepo.getPaymentByOrderId(orderId);
    if (!mounted) return false;
    if (payment == null) return true;

    final isCashPayment = payment.paymentMethod == PaymentMethod.cash ||
        (payment.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment.statusDetail?.toLowerCase() == 'cash_on_delivery');

    final shouldConfirm = isCashPayment && payment.status == PaymentStatus.pending;
    if (!shouldConfirm) return true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cobro'),
        content: const Text(
          'Este pedido es con pago en efectivo. ¿Confirmas que cobraste el dinero al entregar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Aún no'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar cobro'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return false;

    final riderId = ref.read(profileProvider).value?.id;
    final now = DateTime.now();
    final existingMeta = payment.metadata ?? const <String, dynamic>{};

    final updated = payment.copyWith(
      status: PaymentStatus.approved,
      statusDetail: 'cash_collected',
      approvedAt: now,
      updatedAt: now,
      metadata: <String, dynamic>{
        ...existingMeta,
        'confirmedByRiderId': riderId,
        'confirmedAt': now.toIso8601String(),
      },
    );

    try {
      await paymentRepo.savePayment(updated);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cobro en efectivo confirmado')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo confirmar el cobro: $e')),
      );
      return false;
    }
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
    final paymentAsync = ref.watch(watchPaymentByOrderIdProvider(widget.orderId));
    final payment = paymentAsync.asData?.value;
    final isCashPayment = payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final canConfirmCash =
        isCashPayment && payment?.status == PaymentStatus.pending;

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
        actions: [
          IconButton(
            tooltip: 'Ver boleta',
            icon: const Icon(Icons.receipt_long),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderReceiptScreen(
                    orderId: widget.orderId,
                    isRiderView: true,
                  ),
                ),
              );
            },
          ),
          if (canConfirmCash)
            IconButton(
              tooltip: 'Confirmar cobro (efectivo)',
              icon: const Icon(Icons.payments_outlined),
              onPressed: () async {
                await _maybeConfirmCashPayment(orderId: widget.orderId);
              },
            ),
          orderAsync.maybeWhen(
            data: (order) {
              if (order == null) return const SizedBox.shrink();
              final userId = ref.read(profileProvider).value?.id;
              final canCancel =
                  order.status == OrderStatus.assigned &&
                  userId != null &&
                  userId.isNotEmpty &&
                  order.rider.assignedRiderId == userId;

              if (!canCancel) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Cancelar entrega',
                icon: const Icon(Icons.cancel_outlined),
                onPressed: () async {
                  try {
                    await _cancelAsRider(order);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo cancelar: $e')),
                    );
                  }
                },
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
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

          // Keep UI stop index aligned with persisted pickup progress.
          // Use post-frame to avoid calling setState during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncPickupIndexFromOrder(order);
          });

          final stops = order.pickupStops ?? const [];
          final needsPickup = order.status == OrderStatus.assigned;
          final needsDelivery = order.status == OrderStatus.pickedUp ||
              order.status == OrderStatus.inTransit;

          final effectivePickupStopIndex = (!needsPickup || stops.isEmpty)
              ? 0
              : _pickupStopIndex.clamp(0, stops.length - 1);

          final isLastPickupStop = stops.isEmpty ||
              effectivePickupStopIndex >= stops.length - 1;
          final arrivedAtPickup = needsPickup && _arrivedAtPickupStop;

          final pickupTargetGeo = (!needsPickup)
              ? order.pickup.geo
              : (stops.isNotEmpty
                  ? stops[effectivePickupStopIndex].geo
                  : order.pickup.geo);

          final pickupLat = pickupTargetGeo.latitude;
          final pickupLng = pickupTargetGeo.longitude;
          final deliveryLat = order.delivery.geo.latitude;
          final deliveryLng = order.delivery.geo.longitude;

          final pickupLocation = gmap.LatLng(pickupLat, pickupLng);
          final deliveryLocation = gmap.LatLng(deliveryLat, deliveryLng);

          // Watch rider's real-time location from Firestore
          final riderLocationAsync = ref.watch(
            riderLocationForOrderProvider(widget.orderId),
          );

          // Prefer device GPS stream for the rider marker & routing.
          final deviceRiderLocationAsync = ref.watch(riderLocationStreamProvider);

          final deviceLatLng = deviceRiderLocationAsync.maybeWhen(
            data: (loc) => gmap.LatLng(loc.latitude, loc.longitude),
            orElse: () => null,
          );
          final firestoreLatLng = riderLocationAsync.maybeWhen(
            data: (loc) => loc == null ? null : gmap.LatLng(loc.latitude, loc.longitude),
            orElse: () => null,
          );

          // Sometimes emulators / stale providers yield a default location (e.g. US)
          // that makes Directions return ZERO_RESULTS for local deliveries.
          // If the device location is implausibly far from both pickup and delivery,
          // prefer the Firestore location (if available).
          final riderLatLng = () {
            if (deviceLatLng == null) return firestoreLatLng;
            final distance = ll.Distance();
            final dToPickup = distance.as(
              ll.LengthUnit.Meter,
              ll.LatLng(deviceLatLng.latitude, deviceLatLng.longitude),
              ll.LatLng(pickupLat, pickupLng),
            );
            final dToDelivery = distance.as(
              ll.LengthUnit.Meter,
              ll.LatLng(deviceLatLng.latitude, deviceLatLng.longitude),
              ll.LatLng(deliveryLat, deliveryLng),
            );

            const farThresholdMeters = 200000.0;
            final isImplausible = dToPickup > farThresholdMeters &&
                dToDelivery > farThresholdMeters;

            if (!isImplausible) return deviceLatLng;
            if (firestoreLatLng == null) {
              // ignore: avoid_print
              print(
                '⚠️ [RiderDeliveryMap] Device GPS implausible and no Firestore location. '
                'Skipping rider location for routing. '
                'device=${deviceLatLng.latitude},${deviceLatLng.longitude} '
                'pickup=$pickupLat,$pickupLng delivery=$deliveryLat,$deliveryLng '
                'dToPickup=${dToPickup.toStringAsFixed(0)}m '
                'dToDelivery=${dToDelivery.toStringAsFixed(0)}m',
              );
              return null;
            }

            // ignore: avoid_print
            print(
              '⚠️ [RiderDeliveryMap] Ignoring device GPS (too far). '
              'device=${deviceLatLng.latitude},${deviceLatLng.longitude} '
              'pickup=$pickupLat,$pickupLng delivery=$deliveryLat,$deliveryLng '
              'dToPickup=${dToPickup.toStringAsFixed(0)}m '
              'dToDelivery=${dToDelivery.toStringAsFixed(0)}m',
            );
            return firestoreLatLng;
          }();

          // Stabilize rider coordinate changes to avoid refetching routes on
          // every tiny GPS jitter.
          final riderLatLngStable = riderLatLng == null
              ? null
              : gmap.LatLng(
                  _roundCoord(riderLatLng.latitude),
                  _roundCoord(riderLatLng.longitude),
                );

          final initialCenter = gmap.LatLng(
            (pickupLat + deliveryLat) / 2,
            (pickupLng + deliveryLng) / 2,
          );

          // If we already have a controller, keep the camera near the rider
          // as their GPS updates, but avoid spamming camera animations.
          if (_mapController != null && riderLatLng != null) {
            final last = _lastCameraRider;
            final movedEnough = last == null ||
                (last.latitude - riderLatLng.latitude).abs() > 0.0005 ||
                (last.longitude - riderLatLng.longitude).abs() > 0.0005;
            if (movedEnough) {
              _lastCameraRider = riderLatLng;
              _mapController!.animateCamera(
                gmap.CameraUpdate.newLatLng(riderLatLng),
              );
            }
          }

      final showRoute =
          riderLatLngStable != null && (needsPickup || needsDelivery);

      final pickupWaypoints = () {
        if (!needsPickup) return <DirectionsPoint>[];

        // Build ordered stops: current pickup stop -> next pickup stops -> delivery.
        // Destination stays as delivery; pickups are passed as waypoints.
        if (stops.isEmpty) {
          return <DirectionsPoint>[
            DirectionsPoint(latitude: pickupLat, longitude: pickupLng),
          ];
        }

        final remaining = stops.skip(effectivePickupStopIndex);
        return remaining
            .map(
              (s) => DirectionsPoint(
                latitude: s.geo.latitude,
                longitude: s.geo.longitude,
              ),
            )
            .toList();
      }();

      final pickupWaypointsKey = pickupWaypoints
          .map(
            (p) =>
                '${_roundCoord(p.latitude)}:${_roundCoord(p.longitude)}',
          )
          .join('|');

      final routeAsync = !showRoute
          ? const AsyncValue<DirectionsRoute?>.data(null)
          : ref.watch(
              _routeProvider(
                _RouteRequestParams(
                  pickupLat: riderLatLngStable.latitude,
                  pickupLng: riderLatLngStable.longitude,
                  deliveryLat: deliveryLat,
                  deliveryLng: deliveryLng,
                  waypoints: pickupWaypoints,
                  waypointsKey: pickupWaypointsKey,
                ),
              ),
            );

      final targetLatLng = !showRoute
          ? null
          : (needsPickup ? pickupLocation : deliveryLocation);

      final routeColor = needsPickup ? primaryOrange : const Color(0xFF3B82F6);

      final markers = <gmap.Marker>{
        if (needsPickup)
          ...(() {
            if (stops.isEmpty) {
              return <gmap.Marker>[
                gmap.Marker(
                  markerId: const gmap.MarkerId('pickup'),
                  position: pickupLocation,
                  icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                    gmap.BitmapDescriptor.hueOrange,
                  ),
                  infoWindow: const gmap.InfoWindow(title: 'Recogida'),
                ),
              ];
            }

            return List.generate(stops.length, (i) {
              final stop = stops[i];
              final isCurrent = i == effectivePickupStopIndex;
              return gmap.Marker(
                markerId: gmap.MarkerId('pickup_${i + 1}'),
                position: gmap.LatLng(
                  stop.geo.latitude,
                  stop.geo.longitude,
                ),
                icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                  isCurrent
                      ? gmap.BitmapDescriptor.hueAzure
                      : gmap.BitmapDescriptor.hueOrange,
                ),
                infoWindow: gmap.InfoWindow(
                  title: 'Recogida ${i + 1}/${stops.length}',
                ),
              );
            });
          })(),
        gmap.Marker(
          markerId: const gmap.MarkerId('delivery'),
          position: deliveryLocation,
          icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
            gmap.BitmapDescriptor.hueGreen,
          ),
          infoWindow: const gmap.InfoWindow(title: 'Entrega'),
        ),
      };

      if (riderLatLng != null) {
        markers.add(
          gmap.Marker(
            markerId: const gmap.MarkerId('rider'),
            position: riderLatLng,
            icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
              gmap.BitmapDescriptor.hueAzure,
            ),
            infoWindow: const gmap.InfoWindow(title: 'Rider (Tú)'),
          ),
        );
      }

      // Build polylines set
      final polylines = <gmap.Polyline>{};

      final routePoints = routeAsync.maybeWhen(
        data: (route) => (route?.path ?? const <DirectionsPoint>[])
            .map((p) => gmap.LatLng(p.latitude, p.longitude))
            .toList(),
        orElse: () => const <gmap.LatLng>[],
      );

      final routeStatusText = () {
        if (!showRoute) return 'Ruta: esperando ubicación/estado';
        return routeAsync.when(
          data: (route) {
            if (route == null || routePoints.isEmpty) {
              return 'Ruta: fallback recta';
            }
            final mins = (route.durationSeconds / 60).round();
            final km = route.distanceMeters / 1000.0;
            return 'Ruta: $mins min • ${km.toStringAsFixed(1)} km';
          },
          loading: () => 'Ruta: calculando...',
          error: (e, _) => 'Ruta: error ($e)',
        );
      }();

      if (showRoute && routePoints.isNotEmpty) {
        polylines.add(
          gmap.Polyline(
            polylineId: const gmap.PolylineId('follow_route'),
            points: routePoints,
            width: 7,
            color: routeColor,
            geodesic: true,
            zIndex: 10,
          ),
        );
      } else if (showRoute && targetLatLng != null) {
        polylines.add(
          gmap.Polyline(
            polylineId: const gmap.PolylineId('fallback_route'),
            points: [riderLatLngStable, targetLatLng],
            width: 6,
            color: routeColor,
            geodesic: true,
            zIndex: 5,
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
                  markers: markers,
                  polylines: polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      routeStatusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _BottomPanel(
                  order: order,
                  stepTitle: needsPickup
                      ? (arrivedAtPickup && isLastPickupStop
                          ? 'Siguiente: Retirar'
                          : (stops.isEmpty
                              ? 'Siguiente: Recoger'
                              : 'Siguiente: Recoger ${effectivePickupStopIndex + 1}/${stops.length}'))
                      : 'Siguiente: Entregar',
                  needsPickup: needsPickup,
                  arrivedAtPickupStop: arrivedAtPickup,
                  pickupStopsCount: stops.length,
                  pickupStopIndex: effectivePickupStopIndex,
                  currentPickupOfferIds: (needsPickup &&
                          stops.isNotEmpty &&
                          effectivePickupStopIndex < stops.length)
                      ? stops[effectivePickupStopIndex].offerIds
                      : const <String>[],
                  currentPickupAddressSnapshot: (!needsPickup)
                      ? ''
                      : (stops.isNotEmpty && effectivePickupStopIndex < stops.length)
                          ? stops[effectivePickupStopIndex].addressSnapshot
                          : order.pickup.addressSnapshot,
                  deliveryAddressSnapshot: order.delivery.addressSnapshot,
                  onOpenChat: ({
                    required String buyerId,
                    required String buyerName,
                  }) async {
                    try {
                      await _openChat(
                        order: order,
                        buyerId: buyerId,
                        buyerName: buyerName,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('No se pudo abrir chat: $e')),
                      );
                    }
                  },
                  onOpenChats: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RiderDeliveryChatsScreen(
                          orderId: order.orderId,
                        ),
                      ),
                    );
                  },
                  onArrivedAtPickupStop: (!needsPickup || stops.isEmpty)
                      ? null
                      : () async {
                          final isLast =
                              effectivePickupStopIndex >= stops.length - 1;

                          // Persist progress for per-stop hero notifications.
                          // Store NEXT stop index so the app can resume correctly
                          // after rebuilds (current stop becomes the next one).
                          final nextStopIndex = isLast
                              ? effectivePickupStopIndex
                              : (effectivePickupStopIndex + 1);
                          final ok = await _markPickupStopCompleted(
                            orderId: order.orderId,
                            stopIndex: nextStopIndex,
                          );

                          if (!ok) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No se pudo guardar el progreso. Intenta de nuevo.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (!isLast) {
                            setState(() {
                              _pickupStopIndex =
                                  (effectivePickupStopIndex + 1).clamp(0, 9999);
                              _arrivedAtPickupStop = false;
                            });
                          } else {
                            setState(() => _arrivedAtPickupStop = true);
                          }
                        },
                  onPickedUp: order.status == OrderStatus.assigned
                      ? (stops.isNotEmpty &&
                              effectivePickupStopIndex < stops.length - 1
                          ? null
                          : () async {
                              await _setStatus(order, OrderStatus.pickedUp);
                              if (!mounted) return;
                              setState(() => _arrivedAtPickupStop = false);
                            })
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

}

class _BottomPanel extends ConsumerWidget {
  final Order order;
  final String stepTitle;
  final bool needsPickup;
  final bool arrivedAtPickupStop;
  final int pickupStopsCount;
  final int pickupStopIndex;
  final List<String> currentPickupOfferIds;
  final String currentPickupAddressSnapshot;
  final String deliveryAddressSnapshot;
  final Future<void> Function({required String buyerId, required String buyerName})
  onOpenChat;
  final VoidCallback onOpenChats;
  final VoidCallback? onArrivedAtPickupStop;
  final VoidCallback? onPickedUp;
  final VoidCallback? onInTransit;
  final VoidCallback? onDelivered;

  const _BottomPanel({
    required this.order,
    required this.stepTitle,
    required this.needsPickup,
    required this.arrivedAtPickupStop,
    required this.pickupStopsCount,
    required this.pickupStopIndex,
    required this.currentPickupOfferIds,
    required this.currentPickupAddressSnapshot,
    required this.deliveryAddressSnapshot,
    required this.onOpenChat,
    required this.onOpenChats,
    required this.onArrivedAtPickupStop,
    required this.onPickedUp,
    required this.onInTransit,
    required this.onDelivered,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasStops = pickupStopsCount > 0;
    final currentPickupHuman = (pickupStopIndex + 1).clamp(1, pickupStopsCount);
    final isLastPickupStop =
        !hasStops || pickupStopIndex >= pickupStopsCount - 1;
    final arrivedLabel = hasStops
        ? 'Llegué a la recogida $currentPickupHuman/$pickupStopsCount'
        : 'Llegué a la recogida';
    final arrivedEnabled = needsPickup &&
        onArrivedAtPickupStop != null &&
        !(arrivedAtPickupStop && isLastPickupStop);
    final pickedUpEnabled = onPickedUp != null;
    final inTransitEnabled = onInTransit != null;
    final deliveredEnabled = onDelivered != null;

    final String? targetPhone;
    final String? chatBuyerId;

    String? pickupSummary;
    String? pickupWhere;

    if (needsPickup) {
      final offerId = currentPickupOfferIds.isNotEmpty
          ? currentPickupOfferIds.first
          : null;
      final offerAsync = offerId == null
          ? const AsyncValue<Offer?>.data(null)
          : ref.watch(_offerByIdProvider(offerId));
      final offerTitle = offerAsync.value?.title;
      final donorId = offerAsync.value?.heroId;
      final donorAsync = (donorId == null || donorId.isEmpty)
          ? const AsyncValue.data(null)
          : ref.watch(userByIdProvider(donorId));
      targetPhone = donorAsync.value?.phoneNumber;
      chatBuyerId = donorId;

      final extraOffers = currentPickupOfferIds.length - 1;
      final titleBase = (offerTitle != null && offerTitle.trim().isNotEmpty)
          ? offerTitle.trim()
          : 'Pedido';
      pickupSummary = extraOffers > 0
          ? '$titleBase (+$extraOffers más)'
          : titleBase;

      final pickupAddress = currentPickupAddressSnapshot.trim();
      pickupWhere = pickupAddress.isNotEmpty
          ? pickupAddress
          : 'Ubicación de recogida';
    } else {
      targetPhone = order.delivery.recipientPhone;
      chatBuyerId = order.heroId;
    }

    final _ = targetPhone;
    final buyerIdResolved = chatBuyerId;
    final canChat = buyerIdResolved != null && buyerIdResolved.trim().isNotEmpty;

    final riderUid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final chatBadgeCount = (() {
      if (!canChat) return 0;
      final riderId = order.rider.assignedRiderId;
      if (riderId == null || riderId.trim().isEmpty) return 0;

      final chatId = Chat.generateChatId(
        type: ChatType.heroRider,
        buyerId: buyerIdResolved.trim(),
        riderId: riderId.trim(),
        orderId: order.orderId,
      );

      final chatAsync = ref.watch(chatByIdProvider(chatId));
      return chatAsync.maybeWhen(
        data: (chat) {
          if (chat == null) return 0;
          if (riderUid == null) return 0;
          if (chat.unreadCount <= 0) return 0;
          if ((chat.lastMessageSenderId ?? '').trim() == riderUid) return 0;
          return chat.unreadCount;
        },
        orElse: () => 0,
      );
    })();


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
                tooltip: 'Abrir chat',
                onPressed: onOpenChats,
                icon: _ChatIconWithBadge(count: chatBadgeCount),
                color: primaryOrange,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  stepTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textGray700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              _StepPills(
                pickupStopsCount: pickupStopsCount,
                pickupStopIndex: pickupStopIndex,
                needsPickup: needsPickup,
                arrivedAtPickupStop: arrivedAtPickupStop,
                status: order.status,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (needsPickup)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primaryOrange.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: primaryOrange,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vas a recoger: ${pickupSummary ?? 'Pedido'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: textGray900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pickupWhere ?? 'Ubicación de recogida',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: textGray700,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF3B82F6),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vas a entregar a: ${order.delivery.recipientName.isNotEmpty ? order.delivery.recipientName : 'Hero'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: textGray900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                deliveryAddressSnapshot.trim().isNotEmpty
                                    ? deliveryAddressSnapshot.trim()
                                    : order.delivery.addressSnapshot,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textGray700,
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              tooltip: 'Ver dirección',
                              onPressed: () async {
                                final address = (deliveryAddressSnapshot.trim().isNotEmpty
                                        ? deliveryAddressSnapshot.trim()
                                        : order.delivery.addressSnapshot)
                                    .trim();
                                if (address.isEmpty) return;

                                final instructions =
                                    order.delivery.instructions.trim();
                                final full = instructions.isNotEmpty
                                    ? '$address\n\nInstrucciones: $instructions'
                                    : address;

                                await showDialog<void>(
                                  context: context,
                                  builder: (ctx) {
                                    return AlertDialog(
                                      title: const Text('Dirección de entrega'),
                                      content: Text(full),
                                      actions: [
                                        TextButton(
                                          onPressed: () async {
                                            await Clipboard.setData(
                                              ClipboardData(text: full),
                                            );
                                            if (!ctx.mounted) return;
                                            Navigator.of(ctx).pop();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Dirección copiada al portapapeles'),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          },
                                          child: const Text('Copiar'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(),
                                          child: const Text('Cerrar'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              icon: const Icon(
                                Icons.article_outlined,
                                size: 18,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (needsPickup) ...[
            _ActionButton(
              icon: Icons.store_mall_directory_outlined,
              label: arrivedLabel,
              onPressed: arrivedEnabled ? onArrivedAtPickupStop : null,
            ),
            if (isLastPickupStop) ...[
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.shopping_bag_outlined,
                label: 'Retiré el pedido',
                onPressed: pickedUpEnabled ? onPickedUp : null,
              ),
            ],
          ] else ...[
            _ActionButton(
              icon: Icons.local_shipping_outlined,
              label: 'En vía',
              onPressed: inTransitEnabled ? onInTransit : null,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              icon: Icons.check_circle_outline,
              label: 'Entregado',
              onPressed: deliveredEnabled ? onDelivered : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatIconWithBadge extends StatelessWidget {
  final int count;

  const _ChatIconWithBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble_outline),
        if (count > 0)
          PositionedDirectional(
            end: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: primaryOrange,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StepPills extends StatelessWidget {
  final int pickupStopsCount;
  final int pickupStopIndex;
  final bool needsPickup;
  final bool arrivedAtPickupStop;
  final OrderStatus status;

  const _StepPills({
    required this.pickupStopsCount,
    required this.pickupStopIndex,
    required this.needsPickup,
    required this.arrivedAtPickupStop,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[];

    if (pickupStopsCount > 0) {
      for (int i = 0; i < pickupStopsCount; i++) {
        final isDone = !needsPickup ||
            i < pickupStopIndex ||
            (arrivedAtPickupStop && i == pickupStopIndex);
        final isCurrent = needsPickup &&
            i == pickupStopIndex &&
            !(arrivedAtPickupStop && i == pickupStopIndex);
        pills.add(
          _Pill(
            text: '${i + 1}',
            active: isCurrent,
            done: isDone,
          ),
        );
        if (i < pickupStopsCount - 1) pills.add(const SizedBox(width: 6));
      }
    } else {
      pills.add(
        _Pill(
          text: 'R',
          active: needsPickup && !arrivedAtPickupStop,
          done: !needsPickup || arrivedAtPickupStop,
        ),
      );
    }

    pills.add(const SizedBox(width: 6));
    pills.add(
      _Pill(
        text: 'D',
        active: !needsPickup,
        done: status == OrderStatus.delivered,
      ),
    );

    return Row(mainAxisSize: MainAxisSize.min, children: pills);
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool active;
  final bool done;

  const _Pill({
    required this.text,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = done
        ? Colors.green.withValues(alpha: 0.16)
        : (active
            ? primaryOrange.withValues(alpha: 0.16)
            : borderGray100);
    final Color fg = done
        ? Colors.green
        : (active ? primaryOrange : textGray600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: done
              ? Colors.green.withValues(alpha: 0.35)
              : (active
                  ? primaryOrange.withValues(alpha: 0.35)
                  : borderGray100),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: fg,
        ),
      ),
    );
  }
}

class _DeliveryCompletedScreen extends StatelessWidget {
  final String orderId;

  const _DeliveryCompletedScreen({required this.orderId});

  @override
  Widget build(BuildContext context) {
    final shortId = orderId.length <= 8 ? orderId : orderId.substring(0, 8);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Entrega completada',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 54,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pedido #$shortId',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '¡Entrega marcada como completada!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Puedes volver al inicio para ver nuevos pedidos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textGray600,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
                      (_) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Volver al inicio',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

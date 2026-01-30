import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import '../../../../core/config/env.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/rider_bottom_nav.dart';
import '../widgets/rider_header.dart';
import '../viewmodels/rider_home_viewmodel.dart';
import '../widgets/rider_home_metrics_dashboard.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart'
    as profile;
import '../../../shared/profile/presentation/views/profile_screen.dart'
    as profile_view;
import '../widgets/delivery_request_card.dart';
import 'delivery_details_screen.dart';
import '../providers/rider_nearby_providers.dart';
import '../providers/rider_stats_provider.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../../domain/entities/order_status.dart';
import '../../domain/entities/nearby_order.dart';

final mapControllerProvider = StateProvider<gmap.GoogleMapController?>(
  (ref) => null,
);

class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen> {
  String? _selectedOrderId;
  gmap.GoogleMapController? _mapController;
  ProviderSubscription<gmap.GoogleMapController?>? _mapControllerSub;

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
    final profileAsync = ref.watch(profile.profileProvider);

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

        final statsAsync = ref.watch(riderStatsProvider(user.id));
        final riderProfile = user.riderProfile;

        return statsAsync.when(
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
                  title: 'Error al cargar',
                  message: 'No pudimos cargar tu panel',
                ),
              ),
            ],
          ),
          data: (stats) {
            final rating = riderProfile?.rating ?? 0.0;
            final safeStats = stats ?? const <String, dynamic>{};
            final totalEarnings =
                (safeStats['totalEarnings'] as num?)?.toDouble() ?? 0.0;
            final weeklyEarnings =
                (safeStats['weeklyEarnings'] as num?)?.toDouble() ?? 0.0;
            final totalTrips = (safeStats['totalTrips'] as num?)?.toInt() ?? 0;
            final canceledTrips =
                (safeStats['canceledTrips'] as num?)?.toInt() ?? 0;
            final deliveredTrips =
                (safeStats['deliveredTrips'] as num?)?.toInt() ?? 0;
            final failedTrips =
                (safeStats['failedTrips'] as num?)?.toInt() ?? 0;
            final completionRate = (deliveredTrips + canceledTrips + failedTrips) == 0
                ? 0.0
                : deliveredTrips /
                    (deliveredTrips + canceledTrips + failedTrips);

            return CustomScrollView(
              slivers: [
                const RiderHeader(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        RiderHomeMetricsDashboard(
                          totalEarnings: totalEarnings,
                          weeklyEarnings: weeklyEarnings,
                          totalTrips: totalTrips,
                          averageRating: rating,
                          bonuses: 45000,
                          canceledTrips: canceledTrips,
                          completionRate: completionRate,
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

    return locAsync.when(
      data: (loc) {
        // Always use current location for map center
        final currentCenter = gmap.LatLng(loc.latitude, loc.longitude);

        return CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _MapHeaderDelegate(
                child: _PersistentMapWidget(
                  initialCenter: currentCenter,
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
      },
      loading: () => CustomScrollView(
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
          ),
        ],
      ),
      error: (error, stack) => CustomScrollView(
        slivers: [
          SliverFillRemaining(
            child: _buildEmptyState(
              icon: Icons.error_outline,
              title: 'Error de ubicación',
              message:
                  'No pudimos obtener tu ubicación. Verifica los permisos.',
            ),
          ),
        ],
      ),
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
    final profileAsync = ref.watch(profile.profileProvider);

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

  Widget _buildActiveDeliveryCard(dynamic order) {
    final currentStatus = order.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    order.orderId,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(currentStatus.displayName),
                  backgroundColor: primaryOrange.withValues(alpha: 0.12),
                  labelStyle: const TextStyle(
                    color: primaryOrange,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildAddressInfo(
              icon: Icons.location_on_outlined,
              label: 'Recogida',
              address: order.pickup.addressSnapshot,
            ),
            const SizedBox(height: 8),
            _buildAddressInfo(
              icon: Icons.flag_outlined,
              label: 'Entrega',
              address: order.delivery.addressSnapshot,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusButton(
                  context: context,
                  label: 'Recogido',
                  target: 'picked_up',
                  enabled: currentStatus == OrderStatus.assigned,
                  orderId: order.orderId,
                ),
                _statusButton(
                  context: context,
                  label: 'En ruta',
                  target: 'in_transit',
                  enabled: currentStatus == OrderStatus.pickedUp,
                  orderId: order.orderId,
                ),
                _statusButton(
                  context: context,
                  label: 'Entregado',
                  target: 'delivered',
                  enabled: currentStatus == OrderStatus.inTransit,
                  orderId: order.orderId,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressInfo({
    required IconData icon,
    required String label,
    required String address,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: textGray600),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textGray600,
                ),
              ),
              Text(
                address,
                style: const TextStyle(fontSize: 13, color: textGray900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusButton({
    required BuildContext context,
    required String label,
    required String target,
    required bool enabled,
    required String orderId,
  }) {
    return ElevatedButton(
      onPressed: enabled
          ? () async {
              try {
                await ref
                    .read(orderNotifierProvider.notifier)
                    .updateStatus(orderId, target);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Estado actualizado a $label'),
                      backgroundColor: primaryOrange,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al actualizar estado: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled
            ? primaryOrange
            : textGray600.withValues(alpha: 0.2),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: enabled ? 2 : 0,
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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

          print(
            '📍 [Map] Rider moved to: ${newPos.latitude}, ${newPos.longitude}',
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
        print(
          '📍 [Map] Initial position set to: ${_lastRiderPosition!.latitude}, ${_lastRiderPosition!.longitude}',
        );
      }
    }
  }

  void _rebuildMarkers(List<NearbyOrder> nearby) {
    if (!mounted || _lastRiderPosition == null) return;

    // Optimización: comparar IDs de pedidos y selectedOrderId antes de reconstruir
    final currentOrderIds = nearby.map((n) => n.order.orderId).toSet();
    final orderIdsChanged =
        _lastOrderIds.length != currentOrderIds.length ||
        !_lastOrderIds.containsAll(currentOrderIds);
    final selectedChanged = _lastSelectedOrderId != widget.selectedOrderId;

    // Solo reconstruir si hay cambios reales
    if (!orderIdsChanged && !selectedChanged && _markers.isNotEmpty) {
      return;
    }

    _lastOrderIds = currentOrderIds;
    _lastSelectedOrderId = widget.selectedOrderId;

    setState(() {
      _markers = {
        // Marcador del rider
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

        // Set initial position after map is created
        if (_lastRiderPosition != null && !_initialCameraSet) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _mapController != null) {
              _mapController!.animateCamera(
                gmap.CameraUpdate.newCameraPosition(
                  gmap.CameraPosition(target: _lastRiderPosition!, zoom: 14),
                ),
              );
              _initialCameraSet = true;
              print('📍 [Map] Camera positioned at rider location');
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
              return _buildOrderCard(context, n);
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

  Widget _buildOrderCard(BuildContext context, NearbyOrder n) {
    final productName = n.order.items.isNotEmpty
        ? n.order.items.first.titleSnapshot
        : 'Pedido';
    final productImage = n.order.items.isNotEmpty
        ? n.order.items.first.imageUrlSnapshot
        : '';
    final totalWeight = n.order.items.fold<double>(
      0,
      (sum, item) => sum + item.totalWeight,
    );
    final hasDistance = n.distanceMeters != null;
    final distanceKm = hasDistance ? (n.distanceMeters! / 1000) : 0.0;
    final earnings = n.order.deliveryFee;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DeliveryRequestCard(
        key: ValueKey(n.order.orderId),
        productName: productName,
        productImage: productImage,
        weight: totalWeight,
        distance: distanceKm,
        earnings: earnings,
        pickupAddress: n.order.pickup.addressSnapshot,
        deliveryAddress: n.order.delivery.addressSnapshot,
        deliverToReception: n.order.delivery.deliverToReception,
        onViewDetails: (context) {
          // Validate coordinates before opening details
          final hasValidPickup =
              n.order.pickup.geo.latitude != 0 &&
              n.order.pickup.geo.longitude != 0;
          final hasValidDelivery =
              n.order.delivery.geo.latitude != 0 &&
              n.order.delivery.geo.longitude != 0;

          if (!hasValidPickup || !hasValidDelivery) {
            print('⚠️ [DeliveryDetails] Invalid coordinates:');
            print(
              '   Pickup: ${n.order.pickup.geo.latitude}, ${n.order.pickup.geo.longitude}',
            );
            print(
              '   Delivery: ${n.order.delivery.geo.latitude}, ${n.order.delivery.geo.longitude}',
            );

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: Colors.white),
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

          print('✅ [DeliveryDetails] Opening with valid coordinates:');
          print(
            '   Pickup: ${n.order.pickup.geo.latitude}, ${n.order.pickup.geo.longitude}',
          );
          print(
            '   Delivery: ${n.order.delivery.geo.latitude}, ${n.order.delivery.geo.longitude}',
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeliveryDetailsScreen(
                order: n.order,
                productName: productName,
                productImage: productImage,
                weight: totalWeight,
                distance: distanceKm,
                earnings: earnings,
                pickupAddress: n.order.pickup.addressSnapshot,
                deliveryAddress: n.order.delivery.addressSnapshot,
                pickupLat: n.order.pickup.geo.latitude,
                pickupLng: n.order.pickup.geo.longitude,
                deliveryLat: n.order.delivery.geo.latitude,
                deliveryLng: n.order.delivery.geo.longitude,
              ),
            ),
          );
        },
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

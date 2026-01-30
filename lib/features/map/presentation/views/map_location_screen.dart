import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import '../../../../core/config/env.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/map_providers.dart';
import '../state/map_state.dart';
import '../widgets/map_controls.dart';
import '../widgets/product_list_sheet.dart';

class MapLocationScreen extends ConsumerStatefulWidget {
  const MapLocationScreen({super.key});

  @override
  ConsumerState<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends ConsumerState<MapLocationScreen> {
  gmap.GoogleMapController? _mapController;
  double _currentZoom = 14;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapViewModelProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(
      mapViewModelProvider.select((state) => state.isLoading),
    );
    final error = ref.watch(
      mapViewModelProvider.select((state) => state.error),
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        title: const Text(
          'Mapa de productos cercanos',
          style: TextStyle(color: textGray900, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: textGray900,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryOrange))
          : error != null
              ? _buildErrorState(error)
              : Column(
                  children: [
                    // Map Section (65%)
                    Expanded(
                      flex: 6,
                      child: _ProductsMapSection(
                        onControllerReady: (controller) {
                          _mapController = controller;
                        },
                        onZoomChanged: (zoom) {
                          _currentZoom = zoom;
                        },
                      ),
                    ),

                    // Radius slider + label
                    const _SearchRadiusSection(),

                    // Product List Section (35%)
                    Expanded(
                      flex: 4,
                      child: RepaintBoundary(
                        child: _ProductsListSection(
                          controller: _mapController,
                          currentZoom: _currentZoom,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 64, color: textGray600),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: textGray900),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(mapViewModelProvider.notifier).initialize();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchRadiusSection extends ConsumerWidget {
  const _SearchRadiusSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchRadius = ref.watch(
      mapViewModelProvider.select((state) => state.searchRadius),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, size: 18, color: textGray600),
              const SizedBox(width: 8),
              Text(
                'Radio de búsqueda: ${(searchRadius / 1000).toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                ),
              ),
            ],
          ),
          Slider(
            value: searchRadius.clamp(1000, 15000),
            min: 1000,
            max: 15000,
            divisions: 8,
            activeColor: primaryOrange,
            onChanged: (value) {
              ref.read(mapViewModelProvider.notifier).updateSearchRadius(value);
            },
          ),
        ],
      ),
    );
  }
}

class _ProductsListSection extends ConsumerWidget {
  final gmap.GoogleMapController? controller;
  final double currentZoom;

  const _ProductsListSection({required this.controller, required this.currentZoom});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(
      mapViewModelProvider.select((state) => state.nearbyProducts),
    );
    final selected = ref.watch(
      mapViewModelProvider.select((state) => state.selectedProduct),
    );

    return ProductListSheet(
      products: products,
      selectedProduct: selected,
      onProductTap: (product) {
        ref.read(mapViewModelProvider.notifier).selectProduct(product);
        controller?.animateCamera(
          gmap.CameraUpdate.newLatLngZoom(
            gmap.LatLng(product.location.latitude, product.location.longitude),
            currentZoom,
          ),
        );
      },
    );
  }
}

class _ProductsMapSection extends ConsumerStatefulWidget {
  final void Function(gmap.GoogleMapController controller) onControllerReady;
  final void Function(double zoom) onZoomChanged;

  const _ProductsMapSection({
    required this.onControllerReady,
    required this.onZoomChanged,
  });

  @override
  ConsumerState<_ProductsMapSection> createState() => _ProductsMapSectionState();
}

class _ProductsMapSectionState extends ConsumerState<_ProductsMapSection> {
  gmap.GoogleMapController? _controller;
  gmap.CameraPosition? _initialCameraPosition;
  Set<gmap.Marker> _markers = const {};
  Set<gmap.Circle> _circles = const {};

  List<MapProduct> _lastProducts = const [];
  MapProduct? _lastSelected;
  double _lastRadius = -1;
  double? _lastUserLat;
  double? _lastUserLng;

  String? _lastOverlaysSignature;

  ProviderSubscription<MapState>? _sub;

  @override
  void initState() {
    super.initState();
    _syncFrom(ref.read(mapViewModelProvider));
    _sub = ref.listenManual(mapViewModelProvider, (prev, next) {
      _syncFrom(next);
    });
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  void _syncFrom(MapState state) {
    if (!mounted) return;

    final products = state.nearbyProducts;
    final selected = state.selectedProduct;
    final radius = state.searchRadius;
    final userLoc = state.userLocation;

    final userLat = userLoc?.latitude;
    final userLng = userLoc?.longitude;

    final productsChanged = !identical(products, _lastProducts);
    final selectedChanged = selected?.id != _lastSelected?.id;
    final radiusChanged = radius != _lastRadius;
    final userChanged = userLat != _lastUserLat || userLng != _lastUserLng;

    if (_initialCameraPosition == null) {
      final target = userLat != null && userLng != null
          ? gmap.LatLng(userLat, userLng)
          : const gmap.LatLng(-33.4489, -70.6693);
      _initialCameraPosition = gmap.CameraPosition(target: target, zoom: 15);
    }

    if (!(productsChanged || selectedChanged || radiusChanged || userChanged)) return;

    _lastProducts = products;
    _lastSelected = selected;
    _lastRadius = radius;
    _lastUserLat = userLat;
    _lastUserLng = userLng;

    String r(double v) => v.toStringAsFixed(5);
    final sigBuffer = StringBuffer()
      ..write('u:')
      ..write(userLat == null ? '-' : r(userLat))
      ..write(',')
      ..write(userLng == null ? '-' : r(userLng))
      ..write('|rad:')
      ..write(radius.toStringAsFixed(0))
      ..write('|sel:')
      ..write(selected?.id ?? '-')
      ..write('|p:');

    for (final p in products) {
      sigBuffer
        ..write(p.id)
        ..write('@')
        ..write(r(p.location.latitude))
        ..write(',')
        ..write(r(p.location.longitude))
        ..write(';');
    }

    final overlaysSignature = sigBuffer.toString();
    if (_lastOverlaysSignature == overlaysSignature) return;
    _lastOverlaysSignature = overlaysSignature;

    final markers = <gmap.Marker>{};

    if (userLat != null && userLng != null) {
      markers.add(
        gmap.Marker(
          markerId: const gmap.MarkerId('user'),
          position: gmap.LatLng(userLat, userLng),
          icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
            gmap.BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    for (final product in products) {
      final isSelected = selected?.id == product.id;
      markers.add(
        gmap.Marker(
          markerId: gmap.MarkerId(product.id),
          position: gmap.LatLng(product.location.latitude, product.location.longitude),
          icon: isSelected
              ? gmap.BitmapDescriptor.defaultMarkerWithHue(
                  gmap.BitmapDescriptor.hueOrange,
                )
              : gmap.BitmapDescriptor.defaultMarker,
          onTap: () {
            ref.read(mapViewModelProvider.notifier).selectProduct(product);
            _controller?.animateCamera(
              gmap.CameraUpdate.newLatLng(
                gmap.LatLng(product.location.latitude, product.location.longitude),
              ),
            );
          },
        ),
      );
    }

    final circles = <gmap.Circle>{};
    if (userLat != null && userLng != null) {
      circles.add(
        gmap.Circle(
          circleId: const gmap.CircleId('search-radius'),
          center: gmap.LatLng(userLat, userLng),
          radius: radius,
          fillColor: primaryOrange.withValues(alpha: 0.12),
          strokeColor: primaryOrange.withValues(alpha: 0.32),
          strokeWidth: 2,
        ),
      );
    }

    setState(() {
      _markers = markers;
      _circles = circles;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initialCameraPosition ??
        const gmap.CameraPosition(target: gmap.LatLng(-33.4489, -70.6693), zoom: 15);

    return Stack(
      children: [
        gmap.GoogleMap(
          initialCameraPosition: initial,
          onMapCreated: (controller) {
            _controller = controller;
            widget.onControllerReady(controller);
          },
          onCameraMove: (pos) {
            widget.onZoomChanged(pos.zoom);
          },
          onTap: (_) => ref.read(mapViewModelProvider.notifier).selectProduct(null),
          markers: _markers,
          circles: _circles,
          liteModeEnabled: Env.mapsLiteMode,
          buildingsEnabled: false,
          indoorViewEnabled: false,
          trafficEnabled: false,
          tiltGesturesEnabled: false,
          rotateGesturesEnabled: false,
          compassEnabled: false,
          mapType: gmap.MapType.normal,
          minMaxZoomPreference: const gmap.MinMaxZoomPreference(10, 18),
          zoomControlsEnabled: false,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: MapControls(
            onMyLocationTap: () {
              final userLoc = ref.read(mapViewModelProvider).userLocation;
              if (userLoc == null) return;
              _controller?.animateCamera(
                gmap.CameraUpdate.newLatLngZoom(
                  gmap.LatLng(userLoc.latitude, userLoc.longitude),
                  15,
                ),
              );
            },
            onZoomIn: () {
              _controller?.animateCamera(gmap.CameraUpdate.zoomIn());
            },
            onZoomOut: () {
              _controller?.animateCamera(gmap.CameraUpdate.zoomOut());
            },
          ),
        ),
      ],
    );
  }
}

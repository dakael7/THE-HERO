import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../../../core/config/env.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../hero/presentation/views/buyer_catalog_screen.dart';
import '../providers/map_providers.dart';
import '../state/map_state.dart';
import '../widgets/map_controls.dart';
import '../widgets/product_list_sheet.dart';
import '../widgets/floating_search_bar.dart';
import '../widgets/filter_chips_widget.dart';

class MapLocationScreen extends ConsumerStatefulWidget {
  const MapLocationScreen({super.key});

  @override
  ConsumerState<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends ConsumerState<MapLocationScreen> {
  gmap.GoogleMapController? _mapController;
  double _currentZoom = 14;
  String? _selectedCategory;

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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Mapa de donaciones',
          style: TextStyle(color: textGray900, fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        elevation: 0,
        foregroundColor: textGray900,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, primaryYellow.withValues(alpha: 0.1)],
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryOrange))
          : error != null
          ? _buildErrorState(error)
          : Stack(
              children: [
                // Map Section (Full Screen)
                _ProductsMapSection(
                  onControllerReady: (controller) {
                    _mapController = controller;
                  },
                  onZoomChanged: (zoom) {
                    _currentZoom = zoom;
                  },
                ),

                // Floating Search Bar
                SafeArea(child: _buildFloatingSearchBar()),

                // Filter Chips
                Positioned(
                  top: MediaQuery.of(context).padding.top + 130,
                  left: 0,
                  right: 0,
                  child: _buildFilterChips(),
                ),

                // Radius Control Button
                Positioned(left: 16, bottom: 100, child: _buildRadiusButton()),

                // Product List Bottom Sheet
                DraggableScrollableSheet(
                  initialChildSize: 0.35,
                  minChildSize: 0.15,
                  maxChildSize: 0.75,
                  builder: (context, scrollController) {
                    return _ProductsListSection(
                      controller: _mapController,
                      currentZoom: _currentZoom,
                      scrollController: scrollController,
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildFloatingSearchBar() {
    final products = ref.watch(
      mapViewModelProvider.select((state) => state.nearbyProducts),
    );

    return FloatingSearchBar(
      productCount: products.length,
      onSearchTap: () {
        // TODO: Implement search functionality
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Búsqueda en desarrollo')));
      },
      onFilterTap: () => _showRadiusSheet(),
    );
  }

  Widget _buildFilterChips() {
    final products = ref.watch(
      mapViewModelProvider.select((state) => state.nearbyProducts),
    );

    // Extract unique categories
    final categories = products.map((p) => p.category).toSet().toList()..sort();

    if (categories.isEmpty) return const SizedBox.shrink();

    return FilterChipsWidget(
      categories: categories,
      selectedCategory: _selectedCategory,
      onCategorySelected: (category) {
        setState(() {
          _selectedCategory = category;
        });
        // TODO: Filter products by category
      },
    );
  }

  Widget _buildRadiusButton() {
    final searchRadius = ref.watch(
      mapViewModelProvider.select((state) => state.searchRadius),
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        onTap: _showRadiusSheet,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.radar, size: 20, color: primaryOrange),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Radio',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: textGray600,
                    ),
                  ),
                  Text(
                    '${(searchRadius / 1000).toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRadiusSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _RadiusSelectorSheet(),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.location_off,
                size: 50,
                color: primaryOrange,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(mapViewModelProvider.notifier).initialize();
              },
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Reintentar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadiusSelectorSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchRadius = ref.watch(
      mapViewModelProvider.select((state) => state.searchRadius),
    );
    final products = ref.watch(
      mapViewModelProvider.select((state) => state.nearbyProducts),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: backgroundGray50,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'Radio de Búsqueda',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${products.length} productos encontrados',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textGray600,
            ),
          ),
          const SizedBox(height: 24),

          // Slider
          Row(
            children: [
              const Icon(Icons.radar, color: primaryOrange, size: 24),
              Expanded(
                child: Slider(
                  value: searchRadius.clamp(1000, 15000),
                  min: 1000,
                  max: 15000,
                  divisions: 14,
                  activeColor: primaryOrange,
                  inactiveColor: backgroundGray50,
                  label: '${(searchRadius / 1000).toStringAsFixed(1)} km',
                  onChanged: (value) {
                    ref
                        .read(mapViewModelProvider.notifier)
                        .updateSearchRadius(value);
                  },
                ),
              ),
              Text(
                '${(searchRadius / 1000).toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: primaryOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick presets
          Row(
            children: [
              _buildPresetButton(context, ref, '1 km', 1000),
              const SizedBox(width: 8),
              _buildPresetButton(context, ref, '3 km', 3000),
              const SizedBox(width: 8),
              _buildPresetButton(context, ref, '5 km', 5000),
              const SizedBox(width: 8),
              _buildPresetButton(context, ref, '10 km', 10000),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPresetButton(
    BuildContext context,
    WidgetRef ref,
    String label,
    double value,
  ) {
    final currentRadius = ref.watch(
      mapViewModelProvider.select((state) => state.searchRadius),
    );
    final isSelected = (currentRadius - value).abs() < 100;

    return Expanded(
      child: Material(
        color: isSelected ? primaryOrange : backgroundGray50,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            ref.read(mapViewModelProvider.notifier).updateSearchRadius(value);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : textGray900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductsListSection extends ConsumerWidget {
  final gmap.GoogleMapController? controller;
  final double currentZoom;
  final ScrollController scrollController;

  const _ProductsListSection({
    required this.controller,
    required this.currentZoom,
    required this.scrollController,
  });

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

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OfferDetailScreen(offer: product.offer),
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
  ConsumerState<_ProductsMapSection> createState() =>
      _ProductsMapSectionState();
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

    if (!(productsChanged || selectedChanged || radiusChanged || userChanged))
      return;

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
          position: gmap.LatLng(
            product.location.latitude,
            product.location.longitude,
          ),
          icon: isSelected
              ? gmap.BitmapDescriptor.defaultMarkerWithHue(
                  gmap.BitmapDescriptor.hueOrange,
                )
              : gmap.BitmapDescriptor.defaultMarker,
          infoWindow: gmap.InfoWindow(
            title: product.name,
            snippet: 'Ver detalles',
            onTap: () {
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OfferDetailScreen(offer: product.offer),
                ),
              );
            },
          ),
          onTap: () {
            ref.read(mapViewModelProvider.notifier).selectProduct(product);
            _controller?.animateCamera(
              gmap.CameraUpdate.newLatLng(
                gmap.LatLng(
                  product.location.latitude,
                  product.location.longitude,
                ),
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
          strokeColor: primaryOrange.withValues(alpha: 0.35),
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
    final initial =
        _initialCameraPosition ??
        const gmap.CameraPosition(
          target: gmap.LatLng(-33.4489, -70.6693),
          zoom: 15,
        );

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
          onTap: (_) =>
              ref.read(mapViewModelProvider.notifier).selectProduct(null),
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
          bottom: 120,
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

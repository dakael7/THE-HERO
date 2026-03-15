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
import '../widgets/filter_chips_widget.dart';

class MapLocationScreen extends ConsumerStatefulWidget {
  const MapLocationScreen({super.key});

  @override
  ConsumerState<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends ConsumerState<MapLocationScreen>
    with SingleTickerProviderStateMixin {
  gmap.GoogleMapController? _mapController;
  double _currentZoom = 14;
  String? _selectedCategory;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _sheetExtent = 0.35;
  double? _pendingSheetExtent;
  bool _sheetExtentUpdateScheduled = false;

  AnimationController? _headerAnimController;
  Animation<double> _headerOpacity = const AlwaysStoppedAnimation<double>(1.0);

  @override
  void initState() {
    super.initState();

    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _headerOpacity = CurvedAnimation(
      parent: _headerAnimController!,
      curve: Curves.easeOut,
    );
    _headerAnimController!.forward();

    _sheetController.addListener(() {
      final next = _sheetController.size;
      if ((next - _sheetExtent).abs() < 0.001) return;

      // DraggableScrollableController notifications can fire during layout/
      // paint. Deferring avoids: "Build scheduled during frame".
      _pendingSheetExtent = next;
      if (_sheetExtentUpdateScheduled) return;
      _sheetExtentUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetExtentUpdateScheduled = false;
        if (!mounted) return;
        final pending = _pendingSheetExtent;
        if (pending == null) return;
        if ((pending - _sheetExtent).abs() < 0.001) return;
        setState(() => _sheetExtent = pending);
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapViewModelProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _sheetController.dispose();
    _headerAnimController?.dispose();
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
      appBar: _buildAppBar(),
      body: isLoading
          ? _buildLoadingState()
          : error != null
              ? _buildErrorState(error)
              : _buildMapBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(128),
      child: FadeTransition(
        opacity: _headerOpacity,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ─────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 10, 16, 0),
                  child: Row(
                    children: [
                      // Orange accent bar
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
                          color: primaryOrange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.map_outlined,
                          size: 18,
                          color: primaryOrange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Mapa de donaciones',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textGray900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      // Product count badge
                      _ProductCountBadge(),
                    ],
                  ),
                ),

                // ── Filter chips ──────────────────────────────────────
                const SizedBox(height: 8),
                _buildFilterChips(),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapBody() {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.of(context).size.height;
            final sheetHeight = screenHeight * _sheetExtent;
            final safeBottom = MediaQuery.of(context).padding.bottom;
            final buttonsBottom = sheetHeight + safeBottom + 16;

            return Stack(
              children: [
                // Map
                _ProductsMapSection(
                  onControllerReady: (controller) {
                    _mapController = controller;
                  },
                  onZoomChanged: (zoom) {
                    _currentZoom = zoom;
                  },
                ),

                // Radius button
                Positioned(
                  left: 16,
                  bottom: buttonsBottom,
                  child: _buildRadiusButton(),
                ),

                // Map controls
                Positioned(
                  right: 16,
                  bottom: buttonsBottom,
                  child: MapControls(
                    onMyLocationTap: () {
                      final userLoc =
                          ref.read(mapViewModelProvider).userLocation;
                      if (userLoc == null) return;
                      _mapController?.animateCamera(
                        gmap.CameraUpdate.newLatLngZoom(
                          gmap.LatLng(
                              userLoc.latitude, userLoc.longitude),
                          15,
                        ),
                      );
                    },
                    onZoomIn: () {
                      _mapController
                          ?.animateCamera(gmap.CameraUpdate.zoomIn());
                    },
                    onZoomOut: () {
                      _mapController
                          ?.animateCamera(gmap.CameraUpdate.zoomOut());
                    },
                  ),
                ),

                // Bottom sheet
                DraggableScrollableSheet(
                  controller: _sheetController,
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
            );
          },
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final products = ref.watch(
      mapViewModelProvider.select((state) => state.nearbyProducts),
    );
    final categories =
        products.map((p) => p.category).toSet().toList()..sort();
    if (categories.isEmpty) return const SizedBox.shrink();

    return FilterChipsWidget(
      categories: categories,
      selectedCategory: _selectedCategory,
      onCategorySelected: (category) {
        setState(() => _selectedCategory = category);
      },
    );
  }

  Widget _buildRadiusButton() {
    final searchRadius = ref.watch(
      mapViewModelProvider.select((state) => state.searchRadius),
    );

    return GestureDetector(
      onTap: _showRadiusSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: primaryOrange.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primaryOrange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.radar_rounded,
                size: 18,
                color: primaryOrange,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Radio de búsqueda',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: textGray600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      '${(searchRadius / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: primaryOrange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Cambiar',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: primaryOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRadiusSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _RadiusSelectorSheet(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.location_searching_rounded,
              size: 34,
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Buscando productos cerca...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textGray700,
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: primaryOrange,
              strokeWidth: 2.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: const Color(0xFFFECACA), width: 1.5),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                size: 42,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No pudimos ubicarte',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textGray900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: textGray600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () =>
                  ref.read(mapViewModelProvider.notifier).initialize(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Reintentar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCT COUNT BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _ProductCountBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      mapViewModelProvider.select((state) => state.nearbyProducts.length),
    );

    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: primaryYellow,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: primaryYellow.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 13, color: textGray900),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RADIUS SELECTOR SHEET
// ─────────────────────────────────────────────────────────────────────────────
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 20),

          // Header row
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primaryOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.radar_rounded,
                    size: 20, color: primaryOrange),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Radio de búsqueda',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    '${products.length} producto${products.length == 1 ? '' : 's'} encontrado${products.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textGray600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  '${(searchRadius / 1000).toStringAsFixed(1)} km',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: primaryOrange,
              inactiveTrackColor: const Color(0xFFF0F0F0),
              thumbColor: primaryOrange,
              overlayColor: primaryOrange.withOpacity(0.15),
              trackHeight: 5,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: searchRadius.clamp(1000, 100000),
              min: 1000,
              max: 100000,
              divisions: 99,
              onChanged: (value) {
                ref
                    .read(mapViewModelProvider.notifier)
                    .updateSearchRadius(value);
              },
            ),
          ),

          const SizedBox(height: 8),

          // Quick presets
          Row(
            children: [
              _buildPreset(context, ref, '1 km', 1000, searchRadius),
              const SizedBox(width: 8),
              _buildPreset(context, ref, '3 km', 3000, searchRadius),
              const SizedBox(width: 8),
              _buildPreset(context, ref, '5 km', 5000, searchRadius),
              const SizedBox(width: 8),
              _buildPreset(context, ref, '100 km', 100000, searchRadius),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreset(
    BuildContext context,
    WidgetRef ref,
    String label,
    double value,
    double current,
  ) {
    final isSelected = (current - value).abs() < 100;

    return Expanded(
      child: GestureDetector(
        onTap: () => ref
            .read(mapViewModelProvider.notifier)
            .updateSearchRadius(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primaryOrange : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : textGray700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCTS LIST SECTION
// ─────────────────────────────────────────────────────────────────────────────
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
            gmap.LatLng(
                product.location.latitude, product.location.longitude),
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

// ─────────────────────────────────────────────────────────────────────────────
//  MAP SECTION
// ─────────────────────────────────────────────────────────────────────────────
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

class _ProductsMapSectionState
    extends ConsumerState<_ProductsMapSection> {
  gmap.GoogleMapController? _controller;
  gmap.CameraPosition? _initialCameraPosition;
  Set<gmap.Marker> _markers = const {};
  Set<gmap.Circle> _circles = const {};

  bool _overlayUpdateScheduled = false;
  Set<gmap.Marker>? _pendingMarkers;
  Set<gmap.Circle>? _pendingCircles;

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
    final userChanged =
        userLat != _lastUserLat || userLng != _lastUserLng;

    if (_initialCameraPosition == null) {
      final target = userLat != null && userLng != null
          ? gmap.LatLng(userLat, userLng)
          : const gmap.LatLng(-33.4489, -70.6693);
      _initialCameraPosition =
          gmap.CameraPosition(target: target, zoom: 15);
    }

    if (!(productsChanged ||
        selectedChanged ||
        radiusChanged ||
        userChanged)) return;

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
                  builder: (_) =>
                      OfferDetailScreen(offer: product.offer),
                ),
              );
            },
          ),
          onTap: () {
            ref
                .read(mapViewModelProvider.notifier)
                .selectProduct(product);
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
          fillColor: primaryOrange.withOpacity(0.1),
          strokeColor: primaryOrange.withOpacity(0.3),
          strokeWidth: 2,
        ),
      );
    }

    // Provider notifications may arrive during build/layout; schedule overlay
    // updates after the frame to avoid rebuild-during-frame assertions.
    _pendingMarkers = markers;
    _pendingCircles = circles;
    if (_overlayUpdateScheduled) return;
    _overlayUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayUpdateScheduled = false;
      if (!mounted) return;
      final nextMarkers = _pendingMarkers;
      final nextCircles = _pendingCircles;
      if (nextMarkers == null || nextCircles == null) return;
      setState(() {
        _markers = nextMarkers;
        _circles = nextCircles;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initialCameraPosition ??
        const gmap.CameraPosition(
          target: gmap.LatLng(-33.4489, -70.6693),
          zoom: 15,
        );

    return gmap.GoogleMap(
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
      minMaxZoomPreference: const gmap.MinMaxZoomPreference(6, 18),
      zoomControlsEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}
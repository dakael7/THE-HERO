import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../../../core/config/env.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/location_entity.dart';
import '../../../hero/presentation/views/buyer_catalog_screen.dart';
import '../providers/map_providers.dart';
import '../state/map_state.dart';
import '../widgets/map_controls.dart';
import '../widgets/product_list_sheet.dart';

class MapLocationScreen extends ConsumerStatefulWidget {
  const MapLocationScreen({super.key});

  @override
  ConsumerState<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends ConsumerState<MapLocationScreen>
    with SingleTickerProviderStateMixin {
  static const double _sheetExtentDeltaThreshold = 0.006;

  gmap.GoogleMapController? _mapController;
  double _currentZoom = 14;
  String? _selectedCategory;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _sheetExtent = 0.32;
  double? _pendingSheetExtent;
  bool _sheetExtentUpdateScheduled = false;

  List<MapProduct> _cachedCategorySource = const [];
  List<String> _cachedCategories = const [];
  List<MapProduct> _cachedVisibleSource = const [];
  String? _cachedVisibleCategory;
  List<MapProduct> _cachedVisibleProducts = const [];

  AnimationController? _headerAnimController;
  Animation<double> _headerOpacity = const AlwaysStoppedAnimation<double>(1.0);

  @override
  void initState() {
    super.initState();

    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _headerOpacity = CurvedAnimation(
      parent: _headerAnimController!,
      curve: Curves.easeOut,
    );
    _headerAnimController!.forward();

    _sheetController.addListener(_handleSheetExtentChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapViewModelProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _sheetController
      ..removeListener(_handleSheetExtentChange)
      ..dispose();
    _headerAnimController?.dispose();
    super.dispose();
  }

  void _handleSheetExtentChange() {
    final next = _sheetController.size;
    if ((next - _sheetExtent).abs() < _sheetExtentDeltaThreshold) return;

    _pendingSheetExtent = next;
    if (_sheetExtentUpdateScheduled) return;
    _sheetExtentUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetExtentUpdateScheduled = false;
      if (!mounted) return;
      final pending = _pendingSheetExtent;
      if (pending == null) return;
      if ((pending - _sheetExtent).abs() < _sheetExtentDeltaThreshold) return;
      setState(() => _sheetExtent = pending);
    });
  }

  String? _normalizeCategory(String? category) {
    final normalized = category?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  List<MapProduct> _applyCategoryFilter(
    List<MapProduct> products,
    String? category,
  ) {
    final normalized = _normalizeCategory(category);
    if (identical(products, _cachedVisibleSource) &&
        normalized == _cachedVisibleCategory) {
      return _cachedVisibleProducts;
    }

    final filtered = normalized == null
        ? products
        : products
            .where((p) => p.category.trim().toLowerCase() == normalized)
            .toList(growable: false);

    _cachedVisibleSource = products;
    _cachedVisibleCategory = normalized;
    _cachedVisibleProducts = filtered;
    return filtered;
  }

  List<String> _extractCategories(List<MapProduct> products) {
    if (identical(products, _cachedCategorySource)) {
      return _cachedCategories;
    }
    final values = products
        .map((p) => p.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _cachedCategorySource = products;
    _cachedCategories = values;
    return values;
  }

  void _onCategorySelected(String? category) {
    final currentCategory = _normalizeCategory(_selectedCategory);
    final nextCategory = _normalizeCategory(category);
    if (currentCategory == nextCategory) return;

    final selected = ref.read(mapViewModelProvider).selectedProduct;
    setState(() => _selectedCategory = category);

    if (selected != null && nextCategory != null) {
      if (_normalizeCategory(selected.category) != nextCategory) {
        ref.read(mapViewModelProvider.notifier).selectProduct(null);
      }
    }
  }

  double _clampDouble(double value, double min, double max) {
    if (max < min) return min;
    return math.max(min, math.min(value, max));
  }

  @override
  Widget build(BuildContext context) {
    final isLoading =
        ref.watch(mapViewModelProvider.select((state) => state.isLoading));
    final error = ref.watch(mapViewModelProvider.select((state) => state.error));

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: isLoading
          ? _buildLoadingState()
          : error != null
              ? _buildErrorState(error)
              : _buildActiveMap(),
    );
  }

  Widget _buildActiveMap() {
    final nearbyProducts =
        ref.watch(mapViewModelProvider.select((state) => state.nearbyProducts));
    final searchRadius =
        ref.watch(mapViewModelProvider.select((state) => state.searchRadius));
    final userLocation =
        ref.watch(mapViewModelProvider.select((state) => state.userLocation));

    final categories = _extractCategories(nearbyProducts);
    final visibleProducts =
        _applyCategoryFilter(nearbyProducts, _selectedCategory);

    return _buildMapBody(
      categories: categories,
      visibleProducts: visibleProducts,
      searchRadius: searchRadius,
      userLocation: userLocation,
    );
  }

  Widget _buildMapBody({
    required List<String> categories,
    required List<MapProduct> visibleProducts,
    required double searchRadius,
    required LocationEntity? userLocation,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final safeTop = media.padding.top;
        final safeBottom = media.padding.bottom;
        final screenHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media.size.height;

        final sheetHeight = screenHeight * _sheetExtent;

        const controlsHeight = 160.0;
        const radiusHeight = 74.0;
        final topPanelHeight = categories.isEmpty ? 108.0 : 166.0;
        final minTop = safeTop + topPanelHeight + 10;

        final controlsTop = _clampDouble(
          screenHeight - sheetHeight - safeBottom - controlsHeight - 14,
          minTop,
          screenHeight - controlsHeight - safeBottom - 12,
        );

        final radiusTop = _clampDouble(
          screenHeight - sheetHeight - safeBottom - radiusHeight - 14,
          minTop,
          screenHeight - radiusHeight - safeBottom - 12,
        );

        return Stack(
          children: [
            _ProductsMapSection(
              products: visibleProducts,
              onControllerReady: (controller) {
                _mapController = controller;
              },
              onZoomChanged: (zoom) {
                _currentZoom = zoom;
              },
            ),
            const _MapReadabilityOverlay(),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _TopPanel(
                opacity: _headerOpacity,
                selectedCategory: _selectedCategory,
                categories: categories,
                searchRadius: searchRadius,
                visibleCount: visibleProducts.length,
                onCategorySelected: _onCategorySelected,
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              left: 14,
              top: radiusTop,
              child: _RadiusFloatingButton(
                searchRadius: searchRadius,
                onTap: _showRadiusSheet,
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              right: 14,
              top: controlsTop,
              child: MapControls(
                onMyLocationTap: () {
                  if (userLocation == null) return;
                  _mapController?.animateCamera(
                    gmap.CameraUpdate.newLatLngZoom(
                      gmap.LatLng(userLocation.latitude, userLocation.longitude),
                      15,
                    ),
                  );
                },
                onZoomIn: () {
                  _mapController?.animateCamera(gmap.CameraUpdate.zoomIn());
                },
                onZoomOut: () {
                  _mapController?.animateCamera(gmap.CameraUpdate.zoomOut());
                },
              ),
            ),
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.32,
              minChildSize: 0.16,
              maxChildSize: 0.82,
              snap: true,
              snapSizes: const [0.16, 0.32, 0.56, 0.82],
              builder: (context, scrollController) {
                return _ProductsListSection(
                  products: visibleProducts,
                  controller: _mapController,
                  currentZoom: _currentZoom,
                  scrollController: scrollController,
                );
              },
            ),
          ],
        );
      },
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
              color: primaryOrange.withValues(alpha: 0.1),
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
            'Buscando donaciones cercanas...',
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
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFECACA)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  size: 42,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No pudimos cargar tu ubicacion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: textGray600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(mapViewModelProvider.notifier).initialize();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Reintentar',
                    style: TextStyle(fontWeight: FontWeight.w800),
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

class _TopPanel extends StatelessWidget {
  final Animation<double> opacity;
  final String? selectedCategory;
  final List<String> categories;
  final double searchRadius;
  final int visibleCount;
  final ValueChanged<String?> onCategorySelected;

  const _TopPanel({
    required this.opacity,
    required this.selectedCategory,
    required this.categories,
    required this.searchRadius,
    required this.visibleCount,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryOrange,
                            primaryOrange.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.explore_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Explora donaciones',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: textGray900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$visibleCount resultados - radio ${(searchRadius / 1000).toStringAsFixed(1)} km',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textGray600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: primaryYellow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$visibleCount',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: textGray900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 8),
                _CategoryChipsRow(
                  categories: categories,
                  selectedCategory: selectedCategory,
                  onCategorySelected: onCategorySelected,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChipsRow extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;

  const _CategoryChipsRow({
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _CategoryChip(
              label: 'Todos',
              selected: selectedCategory == null,
              onTap: () => onCategorySelected(null),
            ),
            const SizedBox(width: 8),
            ...categories.map(
              (category) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CategoryChip(
                  label: category,
                  selected: selectedCategory == category,
                  onTap: () => onCategorySelected(category),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? primaryOrange : const Color(0xFFF6F7F9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? primaryOrange : borderGray100,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : textGray900,
            ),
          ),
        ),
      ),
    );
  }
}

class _RadiusFloatingButton extends StatelessWidget {
  final double searchRadius;
  final VoidCallback onTap;

  const _RadiusFloatingButton({
    required this.searchRadius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: primaryOrange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Radio',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textGray600,
                    ),
                  ),
                  Text(
                    '${(searchRadius / 1000).toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 13,
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
}

class _MapReadabilityOverlay extends StatelessWidget {
  const _MapReadabilityOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.16),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.08),
            ],
            stops: const [0.0, 0.18, 0.7, 1.0],
          ),
        ),
      ),
    );
  }
}

class _RadiusSelectorSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchRadius =
        ref.watch(mapViewModelProvider.select((state) => state.searchRadius));
    final productsCount = ref.watch(
      mapViewModelProvider.select((state) => state.nearbyProducts.length),
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
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  size: 20,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Radio de busqueda',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                  Text(
                    '$productsCount resultado${productsCount == 1 ? '' : 's'}',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(10),
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
          const SizedBox(height: 22),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: primaryOrange,
              inactiveTrackColor: const Color(0xFFF0F0F0),
              thumbColor: primaryOrange,
              overlayColor: primaryOrange.withValues(alpha: 0.15),
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
                ref.read(mapViewModelProvider.notifier).updateSearchRadius(value);
              },
            ),
          ),
          const SizedBox(height: 8),
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
        onTap: () =>
            ref.read(mapViewModelProvider.notifier).updateSearchRadius(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primaryOrange : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primaryOrange.withValues(alpha: 0.3),
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

class _ProductsListSection extends ConsumerWidget {
  final List<MapProduct> products;
  final gmap.GoogleMapController? controller;
  final double currentZoom;
  final ScrollController scrollController;

  const _ProductsListSection({
    required this.products,
    required this.controller,
    required this.currentZoom,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedProductId = ref.watch(
      mapViewModelProvider.select((state) {
        final selected = state.selectedProduct;
        if (selected == null) return null;
        final isVisible = products.any((product) => product.id == selected.id);
        return isVisible ? selected.id : null;
      }),
    );

    return ProductListSheet(
      products: products,
      selectedProductId: selectedProductId,
      scrollController: scrollController,
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

typedef _MapOverlayWatch = ({
  MapProduct? selectedProduct,
  double searchRadius,
  double? userLat,
  double? userLng,
});

class _ProductsMapSection extends ConsumerStatefulWidget {
  final List<MapProduct> products;
  final void Function(gmap.GoogleMapController controller) onControllerReady;
  final void Function(double zoom) onZoomChanged;

  const _ProductsMapSection({
    required this.products,
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

  bool _overlayUpdateScheduled = false;
  Set<gmap.Marker>? _pendingMarkers;
  Set<gmap.Circle>? _pendingCircles;

  List<MapProduct> _lastProducts = const [];
  MapProduct? _lastSelected;
  double _lastRadius = -1;
  double? _lastUserLat;
  double? _lastUserLng;
  String? _lastOverlaysSignature;

  ProviderSubscription<_MapOverlayWatch>? _sub;

  @override
  void initState() {
    super.initState();
    final initialState = ref.read(mapViewModelProvider);
    _syncFrom(
      selected: initialState.selectedProduct,
      radius: initialState.searchRadius,
      userLat: initialState.userLocation?.latitude,
      userLng: initialState.userLocation?.longitude,
    );
    _sub = ref.listenManual(
      mapViewModelProvider.select(
        (state) => (
          selectedProduct: state.selectedProduct,
          searchRadius: state.searchRadius,
          userLat: state.userLocation?.latitude,
          userLng: state.userLocation?.longitude,
        ),
      ),
      (prev, next) {
        _syncFrom(
          selected: next.selectedProduct,
          radius: next.searchRadius,
          userLat: next.userLat,
          userLng: next.userLng,
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant _ProductsMapSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.products, widget.products)) {
      final state = ref.read(mapViewModelProvider);
      _syncFrom(
        selected: state.selectedProduct,
        radius: state.searchRadius,
        userLat: state.userLocation?.latitude,
        userLng: state.userLocation?.longitude,
      );
    }
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  void _syncFrom({
    required MapProduct? selected,
    required double radius,
    required double? userLat,
    required double? userLng,
  }) {
    if (!mounted) return;

    final products = widget.products;
    final selectedId = selected?.id;
    if (selectedId != null && !products.any((p) => p.id == selectedId)) {
      selected = null;
    }

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

    if (!(productsChanged ||
        selectedChanged ||
        radiusChanged ||
        userChanged)) {
      return;
    }

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
          fillColor: primaryOrange.withValues(alpha: 0.1),
          strokeColor: primaryOrange.withValues(alpha: 0.3),
          strokeWidth: 2,
        ),
      );
    }

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
      minMaxZoomPreference: const gmap.MinMaxZoomPreference(6, 18),
      zoomControlsEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}

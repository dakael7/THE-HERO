import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/map_providers.dart';
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
    final mapState = ref.watch(mapViewModelProvider);

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
      body: mapState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            )
          : mapState.error != null
              ? _buildErrorState(mapState.error!)
              : Column(
                  children: [
                    // Map Section (65%)
                    Expanded(flex: 6, child: _buildMapSection(mapState)),

                    // Radius slider + label
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: const BoxDecoration(color: Colors.white),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.radar, size: 18, color: textGray600),
                              const SizedBox(width: 8),
                              Text(
                                'Radio de búsqueda: ${(mapState.searchRadius / 1000).toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: textGray900,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: mapState.searchRadius.clamp(1000, 15000),
                            min: 1000,
                            max: 15000,
                            divisions: 8,
                            activeColor: primaryOrange,
                            onChanged: (value) {
                              ref
                                  .read(mapViewModelProvider.notifier)
                                  .updateSearchRadius(value);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Product List Section (35%)
                    Expanded(
                      flex: 4,
                      child: RepaintBoundary(
                        child: ProductListSheet(
                          products: mapState.nearbyProducts,
                          selectedProduct: mapState.selectedProduct,
                          onProductTap: (product) {
                            ref
                                .read(mapViewModelProvider.notifier)
                                .selectProduct(product);
                            _mapController?.animateCamera(
                              gmap.CameraUpdate.newLatLngZoom(
                                _toGmap(product.location),
                                _currentZoom,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMapSection(mapState) {
    final selected = mapState.selectedProduct;
    final userLoc = mapState.userLocation;

    final initialTarget = mapState.mapCenter != null
        ? _toGmap(mapState.mapCenter!)
        : (userLoc != null
            ? gmap.LatLng(userLoc.latitude, userLoc.longitude)
            : const gmap.LatLng(-33.4489, -70.6693));

    final productMarkers = mapState.nearbyProducts.map<gmap.Marker>((product) {
      final isSelected = selected?.id == product.id;
      return gmap.Marker(
        markerId: gmap.MarkerId(product.id),
        position: gmap.LatLng(product.location.latitude, product.location.longitude),
        onTap: () {
          ref.read(mapViewModelProvider.notifier).selectProduct(product);
          _mapController?.animateCamera(
            gmap.CameraUpdate.newLatLngZoom(
              gmap.LatLng(product.location.latitude, product.location.longitude),
              _currentZoom,
            ),
          );
        },
        icon: isSelected
            ? gmap.BitmapDescriptor.defaultMarkerWithHue(gmap.BitmapDescriptor.hueOrange)
            : gmap.BitmapDescriptor.defaultMarker,
      );
    }).toSet();

    final userMarker = userLoc == null
        ? <gmap.Marker>{}
        : {
            gmap.Marker(
              markerId: const gmap.MarkerId('user'),
              position: gmap.LatLng(userLoc.latitude, userLoc.longitude),
              icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                gmap.BitmapDescriptor.hueAzure,
              ),
            ),
          };

    final circles = userLoc == null
        ? <gmap.Circle>{}
        : {
            gmap.Circle(
              circleId: const gmap.CircleId('search-radius'),
              center: gmap.LatLng(userLoc.latitude, userLoc.longitude),
              radius: mapState.searchRadius,
              fillColor: primaryOrange.withOpacity(0.12),
              strokeColor: primaryOrange.withOpacity(0.32),
              strokeWidth: 2,
            ),
          };

    return Stack(
      children: [
        gmap.GoogleMap(
          initialCameraPosition: gmap.CameraPosition(
            target: initialTarget,
            zoom: mapState.currentZoom,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          onCameraMove: (pos) {
            _currentZoom = pos.zoom;
          },
          onTap: (_) => ref.read(mapViewModelProvider.notifier).selectProduct(null),
          markers: {...productMarkers, ...userMarker},
          circles: circles,
          zoomControlsEnabled: false,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        ),
        // Map Controls Overlay
        Positioned(
          right: 16,
          bottom: 16,
          child: MapControls(
            onMyLocationTap: () {
              ref.read(mapViewModelProvider.notifier).centerOnUser();
              if (mapState.userLocation != null) {
                _mapController?.animateCamera(
                  gmap.CameraUpdate.newLatLngZoom(
                    gmap.LatLng(
                      mapState.userLocation!.latitude,
                      mapState.userLocation!.longitude,
                    ),
                    15,
                  ),
                );
              }
            },
            onZoomIn: () {
              _mapController?.animateCamera(
                gmap.CameraUpdate.zoomIn(),
              );
            },
            onZoomOut: () {
              _mapController?.animateCamera(
                gmap.CameraUpdate.zoomOut(),
              );
            },
          ),
        ),

      ],
    );
  }

  gmap.LatLng _toGmap(LatLng latLng) => gmap.LatLng(latLng.latitude, latLng.longitude);

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

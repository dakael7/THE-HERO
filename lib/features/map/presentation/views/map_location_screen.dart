import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/map_providers.dart';
import '../widgets/map_controls.dart';
import '../widgets/product_list_sheet.dart';
import '../widgets/custom_markers.dart';

class MapLocationScreen extends ConsumerStatefulWidget {
  const MapLocationScreen({super.key});

  @override
  ConsumerState<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends ConsumerState<MapLocationScreen> {
  final MapController _mapController = MapController();
  late final http.BaseClient _tileHttpClient;

  @override
  void initState() {
    super.initState();
    _tileHttpClient = _OsmSafeHttpClient(http.Client());
    // Initialize map on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapViewModelProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _tileHttpClient.close();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapViewModelProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        title: const Text(
          'Mapa de Productos',
          style: TextStyle(color: textGray900, fontWeight: FontWeight.w600),
        ),
        backgroundColor: primaryYellow,
        elevation: 0,
      ),
      body: mapState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : mapState.error != null
          ? _buildErrorState(mapState.error!)
          : Column(
              children: [
                // Map Section (60%)
                Expanded(flex: 6, child: _buildMapSection(mapState)),

                // Product List Section (40%)
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
                        // Animate map to product location
                        _mapController.move(
                          product.location,
                          _mapController.zoom,
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
    return Stack(
      children: [
        // Optimización: RepaintBoundary para aislar repaints del mapa
        RepaintBoundary(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapState.mapCenter ??
                  (mapState.userLocation != null
                      ? LatLng(
                          mapState.userLocation!.latitude,
                          mapState.userLocation!.longitude,
                        )
                      : const LatLng(-33.4489, -70.6693)), // Santiago default
              initialZoom: mapState.currentZoom,
              minZoom: 5.0,
              maxZoom: 18.0,
            ),
            children: [
              // OpenStreetMap Tiles
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.the_hero',
                tileProvider: NetworkTileProvider(httpClient: _tileHttpClient),
                tileUpdateTransformer: TileUpdateTransformers.throttle(
                  const Duration(milliseconds: 200),
                ),
                maxZoom: 19,
              ),

              // User Location Marker
              if (mapState.userLocation != null)
                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: LatLng(
                        mapState.userLocation!.latitude,
                        mapState.userLocation!.longitude,
                      ),
                      width: 60,
                      height: 60,
                      child: RepaintBoundary(child: buildUserMarker()),
                    ),
                  ],
                ),

              // Product Markers
              MarkerLayer(
                markers: mapState.nearbyProducts.map<Marker>((product) {
                  final isSelected = mapState.selectedProduct?.id == product.id;
                  return Marker(
                    point: product.location,
                    width: isSelected ? 70 : 50,
                    height: isSelected ? 70 : 50,
                    child: RepaintBoundary(
                      child: GestureDetector(
                        onTap: () {
                          ref
                              .read(mapViewModelProvider.notifier)
                              .selectProduct(product);
                          _mapController.move(
                            product.location,
                            _mapController.zoom,
                          );
                        },
                        child: buildProductMarker(
                          product: product,
                          isSelected: isSelected,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Search Radius Circle
              if (mapState.userLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(
                        mapState.userLocation!.latitude,
                        mapState.userLocation!.longitude,
                      ),
                      radius: mapState.searchRadius,
                      useRadiusInMeter: true,
                      color: primaryOrange.withOpacity(0.1),
                      borderColor: primaryOrange.withOpacity(0.3),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
            ],
          ),
        ), // Close RepaintBoundary
        // Map Controls Overlay
        Positioned(
          right: 16,
          bottom: 16,
          child: MapControls(
            onMyLocationTap: () {
              ref.read(mapViewModelProvider.notifier).centerOnUser();
              if (mapState.userLocation != null) {
                _mapController.move(
                  LatLng(
                    mapState.userLocation!.latitude,
                    mapState.userLocation!.longitude,
                  ),
                  15.0,
                );
              }
            },
            onZoomIn: () {
              _mapController.move(
                _mapController.center,
                _mapController.zoom + 1,
              );
            },
            onZoomOut: () {
              _mapController.move(
                _mapController.center,
                _mapController.zoom - 1,
              );
            },
          ),
        ),
      ],
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

class _OsmSafeHttpClient extends http.BaseClient {
  _OsmSafeHttpClient(this._inner);

  final http.Client _inner;

  static final Uint8List _transparentPng = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      if (response.statusCode == 200) return response;
      await response.stream.drain();
      return _transparentPngResponse(request);
    } on http.ClientException {
      return _transparentPngResponse(request);
    } catch (_) {
      return _transparentPngResponse(request);
    }
  }

  http.StreamedResponse _transparentPngResponse(http.BaseRequest request) {
    return http.StreamedResponse(
      Stream<List<int>>.value(_transparentPng),
      200,
      contentLength: _transparentPng.length,
      request: request,
      headers: const {'content-type': 'image/png'},
    );
  }

  @override
  void close() {
    _inner.close();
  }
}

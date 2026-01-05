import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../domain/usecases/get_current_location_usecase.dart';
import '../state/map_state.dart';
import '../providers/map_providers.dart';

class MapViewModel extends Notifier<MapState> {
  late final GetCurrentLocationUseCase getCurrentLocation;

  @override
  MapState build() {
    getCurrentLocation = ref.read(getCurrentLocationUseCaseProvider);
    return const MapState();
  }

  /// Initialize map by getting user location
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final location = await getCurrentLocation();

      state = state.copyWith(
        userLocation: location,
        mapCenter: LatLng(location.latitude, location.longitude),
        hasLocationPermission: true,
        isLoading: false,
      );

      // Load nearby products
      await _loadNearbyProducts();
    } on LocationServiceDisabledException {
      state = state.copyWith(
        isLoading: false,
        error: 'Por favor activa los servicios de ubicación',
      );
    } on LocationPermissionDeniedException {
      state = state.copyWith(
        isLoading: false,
        error: 'Necesitamos permiso de ubicación para mostrar el mapa',
        hasLocationPermission: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error al obtener ubicación: $e',
      );
    }
  }

  /// Load products within search radius
  Future<void> _loadNearbyProducts() async {
    // TODO: Implement when product repository has location support
    // For now, using mock data
    final mockProducts = _getMockProducts();

    // Calculate distances
    final productsWithDistance = mockProducts.map((product) {
      if (state.userLocation != null) {
        final distance = const Distance().as(
          LengthUnit.Meter,
          LatLng(state.userLocation!.latitude, state.userLocation!.longitude),
          product.location,
        );
        return product.copyWith(distanceFromUser: distance);
      }
      return product;
    }).toList();

    // Sort by distance
    productsWithDistance.sort((a, b) {
      if (a.distanceFromUser == null) return 1;
      if (b.distanceFromUser == null) return -1;
      return a.distanceFromUser!.compareTo(b.distanceFromUser!);
    });

    state = state.copyWith(nearbyProducts: productsWithDistance);
  }

  /// Select a product on the map
  void selectProduct(MapProduct? product) {
    state = state.copyWith(selectedProduct: product);

    if (product != null) {
      // Center map on selected product
      state = state.copyWith(mapCenter: product.location);
    }
  }

  /// Update search radius and reload products
  void updateSearchRadius(double radius) {
    state = state.copyWith(searchRadius: radius);
    _loadNearbyProducts();
  }

  /// Update map center when user pans
  void updateMapCenter(LatLng center) {
    if (state.mapCenter == center) return;
    state = state.copyWith(mapCenter: center);
  }

  /// Update zoom level
  void updateZoom(double zoom) {
    if (state.currentZoom == zoom) return;
    state = state.copyWith(currentZoom: zoom);
  }

  /// Center map on user location
  void centerOnUser() {
    if (state.userLocation != null) {
      state = state.copyWith(
        mapCenter: LatLng(
          state.userLocation!.latitude,
          state.userLocation!.longitude,
        ),
      );
    }
  }

  /// Mock products for testing
  /// TODO: Replace with actual product repository
  List<MapProduct> _getMockProducts() {
    if (state.userLocation == null) return [];

    final userLat = state.userLocation!.latitude;
    final userLng = state.userLocation!.longitude;

    return [
      MapProduct(
        id: '1',
        name: 'Bicicleta de montaña',
        category: 'Deportes',
        price: 150000,
        location: LatLng(userLat + 0.01, userLng + 0.01),
      ),
      MapProduct(
        id: '2',
        name: 'Laptop HP',
        category: 'Electrónica',
        price: 350000,
        location: LatLng(userLat - 0.005, userLng + 0.008),
      ),
      MapProduct(
        id: '3',
        name: 'Sofá 3 puestos',
        category: 'Muebles',
        price: 200000,
        location: LatLng(userLat + 0.008, userLng - 0.005),
      ),
      MapProduct(
        id: '4',
        name: 'iPhone 12',
        category: 'Electrónica',
        price: 400000,
        location: LatLng(userLat - 0.01, userLng - 0.01),
      ),
      MapProduct(
        id: '5',
        name: 'Mesa de comedor',
        category: 'Muebles',
        price: 120000,
        location: LatLng(userLat + 0.015, userLng),
      ),
    ];
  }
}

import 'package:latlong2/latlong.dart';
import '../../../../domain/entities/location_entity.dart';
import '../../../../domain/entities/offer.dart';

class MapState {
  final LocationEntity? userLocation;
  final List<MapProduct> nearbyProducts;
  final MapProduct? selectedProduct;
  final double searchRadius; // in meters
  final double currentZoom;
  final LatLng? mapCenter;
  final bool isLoading;
  final String? error;
  final bool hasLocationPermission;

  const MapState({
    this.userLocation,
    this.nearbyProducts = const [],
    this.selectedProduct,
    this.searchRadius = 5000, // 5km default
    this.currentZoom = 15.0,
    this.mapCenter,
    this.isLoading = false,
    this.error,
    this.hasLocationPermission = false,
  });

  MapState copyWith({
    LocationEntity? userLocation,
    List<MapProduct>? nearbyProducts,
    MapProduct? selectedProduct,
    double? searchRadius,
    double? currentZoom,
    LatLng? mapCenter,
    bool? isLoading,
    String? error,
    bool? hasLocationPermission,
  }) {
    return MapState(
      userLocation: userLocation ?? this.userLocation,
      nearbyProducts: nearbyProducts ?? this.nearbyProducts,
      selectedProduct: selectedProduct ?? this.selectedProduct,
      searchRadius: searchRadius ?? this.searchRadius,
      currentZoom: currentZoom ?? this.currentZoom,
      mapCenter: mapCenter ?? this.mapCenter,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasLocationPermission:
          hasLocationPermission ?? this.hasLocationPermission,
    );
  }
}

class MapProduct {
  final String id;
  final String name;
  final String category;
  final double price;
  final LatLng location;
  final Offer offer;
  final double? distanceFromUser;
  final String? imageUrl;

  const MapProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.location,
    required this.offer,
    this.distanceFromUser,
    this.imageUrl,
  });

  MapProduct copyWith({double? distanceFromUser}) {
    return MapProduct(
      id: id,
      name: name,
      category: category,
      price: price,
      location: location,
      offer: offer,
      distanceFromUser: distanceFromUser ?? this.distanceFromUser,
      imageUrl: imageUrl,
    );
  }
}

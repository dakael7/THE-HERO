import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../domain/entities/offer.dart';
import '../../../../domain/usecases/get_current_location_usecase.dart';
import '../../../../domain/providers/offers_usecase_providers.dart';
import '../providers/map_providers.dart';
import '../state/map_state.dart';

class MapViewModel extends Notifier<MapState> {
  StreamSubscription<List<Offer>>? _offersSub;
  List<Offer> _cachedOffers = [];

  @override
  MapState build() {
    ref.onDispose(() => _offersSub?.cancel());
    return const MapState();
  }

  /// Initialize map by getting user location
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final getCurrentLocation = ref.read(getCurrentLocationUseCaseProvider);
      final location = await getCurrentLocation();

      state = state.copyWith(
        userLocation: location,
        mapCenter: LatLng(location.latitude, location.longitude),
        hasLocationPermission: true,
        isLoading: false,
      );

      // Load nearby offers
      await _subscribeToOffers();
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
  Future<void> _subscribeToOffers() async {
    await _offersSub?.cancel();

    final offersUseCase = ref.read(getActiveOffersUseCaseProvider);

    _offersSub = offersUseCase.execute(limit: 120).listen((offers) {
      _cachedOffers = offers;
      _recomputeNearby();
    });
  }

  void _recomputeNearby() {
    if (state.userLocation == null) return;
    final userLatLng = LatLng(state.userLocation!.latitude, state.userLocation!.longitude);

    final products = _cachedOffers
        .where((offer) => offer.itemLocationSnapshot != null)
        .map((offer) {
          final snap = offer.itemLocationSnapshot!;
          final loc = LatLng(snap.latitude, snap.longitude);
          final distance = const Distance().as(
            LengthUnit.Meter,
            userLatLng,
            loc,
          );
          return MapProduct(
            id: offer.offerId,
            name: offer.title,
            category: offer.category,
            price: offer.price,
            location: loc,
            distanceFromUser: distance,
            imageUrl: offer.coverImageUrl,
          );
        })
        .where((mp) => mp.distanceFromUser == null || mp.distanceFromUser! <= state.searchRadius)
        .toList();

    products.sort((a, b) {
      if (a.distanceFromUser == null) return 1;
      if (b.distanceFromUser == null) return -1;
      return a.distanceFromUser!.compareTo(b.distanceFromUser!);
    });

    state = state.copyWith(nearbyProducts: products);
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
    _recomputeNearby();
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

}

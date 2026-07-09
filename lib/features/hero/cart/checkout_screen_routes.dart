part of 'checkout_screen.dart';

extension _CheckoutRouteLogic on _CheckoutScreenState {
  void _scheduleRoutesLoad({
    required List<CartItem> cartItems,
    required firestore.GeoPoint? deliveryGeo,
  }) {
    final delivery = deliveryGeo;
    if (!_isValidGeo(delivery)) return;

    final pickupGeos = cartItems
        .map((e) => e.pickupGeo)
        .where(_isValidGeo)
        .cast<firestore.GeoPoint>()
        .toList();
    if (pickupGeos.isEmpty) return;

    final uniquePickups = <String, firestore.GeoPoint>{};
    for (final geo in pickupGeos) {
      final key =
          '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
      uniquePickups[key] = geo;
    }

    final signature = [
      '${delivery!.latitude.toStringAsFixed(6)},${delivery.longitude.toStringAsFixed(6)}',
      ...uniquePickups.keys.toList()..sort(),
    ].join('|');

    _lastUniquePickups = uniquePickups;
    _lastDeliveryGeo = delivery;
    _lastComputedSignature = signature;

    if (signature == _lastRoutesSignature) return;
    _lastRoutesSignature = signature;

    _routesDebounce?.cancel();
    _routesDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;

      if (_isLoadingRoutes) {
        _pendingRoutes = (uniquePickups: uniquePickups, delivery: delivery);
        _pendingRoutesSignature = signature;
        return;
      }

      _loadRoutes(
        uniquePickups: uniquePickups,
        delivery: delivery,
        signature: signature,
      );
    });
  }

  Future<void> _loadRoutes({
    required Map<String, firestore.GeoPoint> uniquePickups,
    required firestore.GeoPoint delivery,
    required String signature,
  }) async {
    if (_isLoadingRoutes) return;

    _activeRoutesSignature = signature;

    setState(() {
      _isLoadingRoutes = true;
      _routesError = null;
    });

    ref.read(routeDistanceKmProvider.notifier).state = null;

    try {
      final trip = await _fetchOsrmTrip(
        pickupKeysToGeo: uniquePickups,
        delivery: LatLng(delivery.latitude, delivery.longitude),
      );
      if (!mounted) return;
      setState(() => _trip = trip);
      ref.read(routeDistanceKmProvider.notifier).state =
          (trip.distanceMeters / 1000.0);
    } catch (e) {
      if (!mounted) return;
      if (e is _RouteCalculationException) {
        debugPrint(
          'ðŸ§­ [Checkout] Route calculation failed: ${e.debugMessage}',
        );
      } else {
        debugPrint('ðŸ§­ [Checkout] Route calculation failed: $e');
      }
      setState(() => _routesError = e);
      ref.read(routeDistanceKmProvider.notifier).state = null;
    } finally {
      if (mounted) {
        setState(() => _isLoadingRoutes = false);

        final pending = _pendingRoutes;
        final pendingSig = _pendingRoutesSignature;
        _pendingRoutes = null;
        _pendingRoutesSignature = null;

        final activeSig = _activeRoutesSignature;
        _activeRoutesSignature = null;

        if (pending != null && pendingSig != null && pendingSig != activeSig) {
          _loadRoutes(
            uniquePickups: pending.uniquePickups,
            delivery: pending.delivery,
            signature: pendingSig,
          );
        }
      }
    }
  }

  Future<_OsrmTrip> _fetchOsrmTrip({
    required Map<String, firestore.GeoPoint> pickupKeysToGeo,
    required LatLng delivery,
  }) async {
    final apiKey = Env.placesApiKey;
    if (apiKey.trim().isEmpty) {
      throw _RouteCalculationException.service('Missing PLACES_API_KEY');
    }

    final pickupKeys = pickupKeysToGeo.keys.toList()..sort();
    if (pickupKeys.isEmpty) {
      throw _RouteCalculationException.noRoute('No pickup keys');
    }

    final originGeo = pickupKeysToGeo[pickupKeys.first]!;
    final origin = '${originGeo.latitude},${originGeo.longitude}';
    final destination = '${delivery.latitude},${delivery.longitude}';

    final intermediateKeys = pickupKeys.length > 1
        ? pickupKeys.sublist(1)
        : const <String>[];

    final waypointsParam = <String>[
      if (intermediateKeys.isNotEmpty) 'optimize:true',
      for (final key in intermediateKeys)
        '${pickupKeysToGeo[key]!.latitude},${pickupKeysToGeo[key]!.longitude}',
    ].join('|');

    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': origin,
        'destination': destination,
        if (intermediateKeys.isNotEmpty) 'waypoints': waypointsParam,
        'mode': 'driving',
        'key': apiKey,
      },
    );

    Future<http.Response> getRequest() {
      return http.get(url).timeout(const Duration(seconds: 15));
    }

    http.Response res;
    try {
      res = await getRequest();
    } on TimeoutException {
      try {
        res = await getRequest();
      } on TimeoutException catch (e) {
        throw _RouteCalculationException.timeout(e.toString());
      } on http.ClientException catch (e) {
        throw _RouteCalculationException.network(e.toString());
      } on PlatformException catch (e) {
        throw _RouteCalculationException.network(e.toString());
      } catch (e) {
        throw _RouteCalculationException.service(e.toString());
      }
    } on http.ClientException catch (e) {
      throw _RouteCalculationException.network(e.toString());
    } on PlatformException catch (e) {
      throw _RouteCalculationException.network(e.toString());
    } catch (e) {
      throw _RouteCalculationException.service(e.toString());
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _RouteCalculationException.service(
        'Directions statusCode=${res.statusCode}',
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final status = (json['status'] as String?) ?? '';
    if (status != 'OK') {
      if (status == 'ZERO_RESULTS') {
        throw _RouteCalculationException.noRoute(
          'Directions status=ZERO_RESULTS',
        );
      }
      throw _RouteCalculationException.service('Directions status=$status');
    }

    final routes = (json['routes'] as List?)?.cast<Map<String, dynamic>>();
    if (routes == null || routes.isEmpty) {
      throw _RouteCalculationException.noRoute('Directions: no routes');
    }

    final firstRoute = routes.first;
    final legsJson = (firstRoute['legs'] as List?)
        ?.cast<Map<String, dynamic>>();
    if (legsJson == null || legsJson.isEmpty) {
      throw _RouteCalculationException.noRoute('Directions: no legs');
    }

    var distanceMeters = 0.0;
    var durationSeconds = 0.0;
    final legs = <_OsrmLeg>[];
    for (final leg in legsJson) {
      final dist = (leg['distance'] as Map?)?['value'] as num?;
      final dur = (leg['duration'] as Map?)?['value'] as num?;
      final d = dist?.toDouble() ?? 0.0;
      final s = dur?.toDouble() ?? 0.0;
      distanceMeters += d;
      durationSeconds += s;
      legs.add(_OsrmLeg(distanceMeters: d, durationSeconds: s));
    }

    final polyStr =
        (firstRoute['overview_polyline'] as Map?)?['points'] as String?;
    if (polyStr == null || polyStr.trim().isEmpty) {
      throw _RouteCalculationException.noRoute('Directions: missing polyline');
    }

    final polylinePoints = _decodePolyline(polyStr);
    if (polylinePoints.isEmpty) {
      throw _RouteCalculationException.noRoute('Directions: empty polyline');
    }

    final waypointOrder =
        (firstRoute['waypoint_order'] as List?)
            ?.cast<num>()
            .map((e) => e.toInt())
            .toList() ??
        const <int>[];

    final orderedPickupKeys = <String>[pickupKeys.first];
    if (intermediateKeys.isNotEmpty) {
      if (waypointOrder.length == intermediateKeys.length) {
        for (final idx in waypointOrder) {
          if (idx >= 0 && idx < intermediateKeys.length) {
            orderedPickupKeys.add(intermediateKeys[idx]);
          }
        }
      } else {
        orderedPickupKeys.addAll(intermediateKeys);
      }
    }

    return _OsrmTrip(
      points: polylinePoints,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      orderedPickupKeys: orderedPickupKeys,
      legs: legs,
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  void _retryRoutesIfPossible() {
    final uniquePickups = _lastUniquePickups;
    final delivery = _lastDeliveryGeo;
    final signature = _lastComputedSignature;
    if (uniquePickups == null || delivery == null || signature == null) return;
    if (_isLoadingRoutes) return;

    _lastRoutesSignature = null;
    _loadRoutes(
      uniquePickups: uniquePickups,
      delivery: delivery,
      signature: signature,
    );
  }
}

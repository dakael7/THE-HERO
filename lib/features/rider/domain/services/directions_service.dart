import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class DirectionsPoint {
  final double latitude;
  final double longitude;

  const DirectionsPoint({required this.latitude, required this.longitude});
}

class DirectionsRoute {
  final List<DirectionsPoint> path;
  final double distanceMeters;
  final int durationSeconds;

  const DirectionsRoute({
    required this.path,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// Google Directions service (with stub fallback if API key is missing).
class DirectionsService {
  // Provide the API key via --dart-define=GOOGLE_MAPS_API_KEY=XXXX or inject your own source.
  final String apiKey;

  DirectionsService({String? apiKey})
      : apiKey = apiKey ?? const String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  Future<DirectionsRoute> getRoute({
    required double pickupLat,
    required double pickupLng,
    required double deliveryLat,
    required double deliveryLng,
  }) async {
    if (apiKey.isEmpty) {
      return _fallbackRoute(pickupLat, pickupLng, deliveryLat, deliveryLng);
    }

    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$pickupLat,$pickupLng'
      '&destination=$deliveryLat,$deliveryLng'
      '&mode=driving'
      '&key=$apiKey',
    );

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        return _fallbackRoute(pickupLat, pickupLng, deliveryLat, deliveryLng);
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final routes = (data['routes'] as List?) ?? [];
      if (routes.isEmpty) {
        return _fallbackRoute(pickupLat, pickupLng, deliveryLat, deliveryLng);
      }

      final route = routes.first as Map<String, dynamic>;
      final legs = (route['legs'] as List?) ?? [];
      final leg = legs.isNotEmpty ? legs.first as Map<String, dynamic> : <String, dynamic>{};

      final distanceMeters = (leg['distance']?['value'] as num?)?.toDouble();
      final durationSeconds = (leg['duration']?['value'] as num?)?.toInt();
      final overview = (route['overview_polyline']?['points'] as String?) ?? '';
      final decoded = overview.isNotEmpty ? _decodePolyline(overview) : <DirectionsPoint>[];

      if (decoded.isEmpty) {
        return _fallbackRoute(pickupLat, pickupLng, deliveryLat, deliveryLng);
      }

      return DirectionsRoute(
        path: decoded,
        distanceMeters: distanceMeters ??
            Distance().as(
              LengthUnit.Meter,
              LatLng(pickupLat, pickupLng),
              LatLng(deliveryLat, deliveryLng),
            ),
        durationSeconds: durationSeconds ??
            (Distance().as(
                      LengthUnit.Meter,
                      LatLng(pickupLat, pickupLng),
                      LatLng(deliveryLat, deliveryLng),
                    ) /
                    8.3)
                .round(),
      );
    } catch (_) {
      return _fallbackRoute(pickupLat, pickupLng, deliveryLat, deliveryLng);
    }
  }

  DirectionsRoute _fallbackRoute(
    double pickupLat,
    double pickupLng,
    double deliveryLat,
    double deliveryLng,
  ) {
    final distanceCalc = Distance();
    final distanceMeters = distanceCalc.as(
      LengthUnit.Meter,
      LatLng(pickupLat, pickupLng),
      LatLng(deliveryLat, deliveryLng),
    );
    final durationSeconds = (distanceMeters / 8.3).round();

    return DirectionsRoute(
      path: [
        DirectionsPoint(latitude: pickupLat, longitude: pickupLng),
        DirectionsPoint(latitude: deliveryLat, longitude: deliveryLng),
      ],
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  List<DirectionsPoint> _decodePolyline(String encoded) {
    final List<DirectionsPoint> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(DirectionsPoint(
        latitude: lat / 1e5,
        longitude: lng / 1e5,
      ));
    }

    return points;
  }
}

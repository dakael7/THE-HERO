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
      : apiKey = apiKey ??
            (const String.fromEnvironment(
                      'GOOGLE_DIRECTIONS_API_KEY',
                      defaultValue: '',
                    ).trim().isNotEmpty
                ? const String.fromEnvironment('GOOGLE_DIRECTIONS_API_KEY')
                : (const String.fromEnvironment('PLACES_API_KEY', defaultValue: '')
                            .trim()
                            .isNotEmpty
                        ? const String.fromEnvironment('PLACES_API_KEY')
                        : const String.fromEnvironment('GOOGLE_MAPS_API_KEY')));

  Future<DirectionsRoute> getRoute({
    required double pickupLat,
    required double pickupLng,
    required double deliveryLat,
    required double deliveryLng,
    double? waypointLat,
    double? waypointLng,
    List<DirectionsPoint>? waypoints,
  }) async {
    if (apiKey.isEmpty) {
      // ignore: avoid_print
      print(
        '⚠️ Directions fallback (no apiKey) '
        'origin=$pickupLat,$pickupLng '
        'waypoint=${(waypointLat != null && waypointLng != null) ? '$waypointLat,$waypointLng' : '-'} '
        'destination=$deliveryLat,$deliveryLng',
      );
      return _fallbackRoute(
        pickupLat,
        pickupLng,
        deliveryLat,
        deliveryLng,
        waypointLat: waypointLat,
        waypointLng: waypointLng,
        waypoints: waypoints,
      );
    }

    final singleWaypoint = (waypointLat != null && waypointLng != null)
        ? DirectionsPoint(latitude: waypointLat, longitude: waypointLng)
        : null;

    final mergedWaypoints = <DirectionsPoint>[];
    if (waypoints != null && waypoints.isNotEmpty) {
      mergedWaypoints.addAll(waypoints);
    }
    if (singleWaypoint != null) {
      mergedWaypoints.add(singleWaypoint);
    }

    // Google Directions API: waypoint limits depend on plan. Keep a conservative cap.
    final cappedWaypoints =
        mergedWaypoints.length > 23 ? mergedWaypoints.take(23).toList() : mergedWaypoints;
    final hasWaypoint = cappedWaypoints.isNotEmpty;

    Uri _buildUri({required String mode, required bool useViaWaypoint}) {
      final waypointParam = !hasWaypoint
          ? ''
          : (() {
              final wp = cappedWaypoints
                  .map(
                    (p) =>
                        '${useViaWaypoint ? 'via:' : ''}${p.latitude},${p.longitude}',
                  )
                  .join('|');
              return '&waypoints=$wp';
            })();

      return Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$pickupLat,$pickupLng'
        '&destination=$deliveryLat,$deliveryLng'
        '$waypointParam'
        '&mode=$mode'
        '&alternatives=false'
        '&language=es'
        '&region=ve'
        '&key=$apiKey',
      );
    }

    Future<DirectionsRoute?> _try({required String mode, required bool useViaWaypoint}) async {
      final uri = _buildUri(mode: mode, useViaWaypoint: useViaWaypoint);
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        // ignore: avoid_print
        print(
          '⚠️ Directions HTTP ${res.statusCode} mode=$mode via=$useViaWaypoint '
          'origin=$pickupLat,$pickupLng '
          'waypoint=${hasWaypoint ? '$waypointLat,$waypointLng' : '-'} '
          'destination=$deliveryLat,$deliveryLng',
        );
        return null;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final status = data['status']?.toString();
      if (status != null && status != 'OK') {
        final message = data['error_message']?.toString();
        // ignore: avoid_print
        print(
          '⚠️ Directions API status=$status mode=$mode via=$useViaWaypoint '
          'origin=$pickupLat,$pickupLng '
          'waypoint=${hasWaypoint ? '${cappedWaypoints.length} stops' : '-'} '
          'destination=$deliveryLat,$deliveryLng '
          'message=${message ?? ''}',
        );
        return null;
      }

      final routes = (data['routes'] as List?) ?? [];
      if (routes.isEmpty) {
        return null;
      }

      final route = routes.first as Map<String, dynamic>;
      final legs = (route['legs'] as List?) ?? [];
      final totalDistanceMeters = legs
          .map((l) => (l as Map<String, dynamic>)['distance']?['value'] as num?)
          .whereType<num>()
          .fold<double>(0.0, (sum, v) => sum + v.toDouble());
      final totalDurationSeconds = legs
          .map((l) => (l as Map<String, dynamic>)['duration']?['value'] as num?)
          .whereType<num>()
          .fold<int>(0, (sum, v) => sum + v.toInt());

      final overview = (route['overview_polyline']?['points'] as String?) ?? '';
      final decoded = overview.isNotEmpty ? _decodePolyline(overview) : <DirectionsPoint>[];
      if (decoded.isEmpty) {
        return null;
      }

      // ignore: avoid_print
      print(
        '✅ Directions OK mode=$mode via=$useViaWaypoint '
        'origin=$pickupLat,$pickupLng '
        'waypoint=${hasWaypoint ? '${cappedWaypoints.length} stops' : '-'} '
        'destination=$deliveryLat,$deliveryLng '
        'points=${decoded.length}',
      );

      return DirectionsRoute(
        path: decoded,
        distanceMeters: totalDistanceMeters > 0
            ? totalDistanceMeters
            : (() {
                final d = Distance();
                if (hasWaypoint) {
                  final points = <LatLng>[LatLng(pickupLat, pickupLng)];
                  for (final wp in cappedWaypoints) {
                    points.add(LatLng(wp.latitude, wp.longitude));
                  }
                  points.add(LatLng(deliveryLat, deliveryLng));
                  var sum = 0.0;
                  for (var i = 0; i < points.length - 1; i++) {
                    sum += d.as(LengthUnit.Meter, points[i], points[i + 1]);
                  }
                  return sum;
                }
                return d.as(
                  LengthUnit.Meter,
                  LatLng(pickupLat, pickupLng),
                  LatLng(deliveryLat, deliveryLng),
                );
              })(),
        durationSeconds: totalDurationSeconds > 0
            ? totalDurationSeconds
            : (() {
                final d = Distance();
                final meters = hasWaypoint
                    ? (() {
                        final points = <LatLng>[LatLng(pickupLat, pickupLng)];
                        for (final wp in cappedWaypoints) {
                          points.add(LatLng(wp.latitude, wp.longitude));
                        }
                        points.add(LatLng(deliveryLat, deliveryLng));
                        var sum = 0.0;
                        for (var i = 0; i < points.length - 1; i++) {
                          sum += d.as(LengthUnit.Meter, points[i], points[i + 1]);
                        }
                        return sum;
                      })()
                    : d.as(
                        LengthUnit.Meter,
                        LatLng(pickupLat, pickupLng),
                        LatLng(deliveryLat, deliveryLng),
                      );
                return (meters / 8.3).round();
              })(),
      );
    }

    try {
      // When using waypoints, ZERO_RESULTS is common with strict 'via:'.
      // Try progressively looser requests.
      final attempts = <({String mode, bool via})>[
        (mode: 'driving', via: true),
        (mode: 'driving', via: false),
      ];

      for (final a in attempts) {
        final route = await _try(mode: a.mode, useViaWaypoint: a.via);
        if (route != null) return route;
        if (!hasWaypoint) break;
      }
    } catch (_) {
      // fallthrough
    }

    // ignore: avoid_print
    print(
      '⚠️ Directions fallback (api failed) '
      'origin=$pickupLat,$pickupLng '
      'waypoint=${(waypointLat != null && waypointLng != null) ? '$waypointLat,$waypointLng' : '-'} '
      'destination=$deliveryLat,$deliveryLng',
    );
    return _fallbackRoute(
      pickupLat,
      pickupLng,
      deliveryLat,
      deliveryLng,
      waypointLat: waypointLat,
      waypointLng: waypointLng,
      waypoints: waypoints,
    );
  }

  DirectionsRoute _fallbackRoute(
    double pickupLat,
    double pickupLng,
    double deliveryLat,
    double deliveryLng,
    {
    double? waypointLat,
    double? waypointLng,
    List<DirectionsPoint>? waypoints,
  }
  ) {
    final distanceCalc = Distance();
    final wLat = waypointLat;
    final wLng = waypointLng;
    final hasWaypoint = wLat != null && wLng != null;

    final mergedWaypoints = <DirectionsPoint>[];
    if (waypoints != null && waypoints.isNotEmpty) {
      mergedWaypoints.addAll(waypoints);
    }
    if (hasWaypoint) {
      mergedWaypoints.add(DirectionsPoint(latitude: wLat, longitude: wLng));
    }

    final segments = <List<DirectionsPoint>>[];
    if (mergedWaypoints.isNotEmpty) {
      var prev = DirectionsPoint(latitude: pickupLat, longitude: pickupLng);
      for (final wp in mergedWaypoints) {
        segments.add([prev, wp]);
        prev = wp;
      }
      segments.add(
        [
          prev,
          DirectionsPoint(latitude: deliveryLat, longitude: deliveryLng),
        ],
      );
    } else {
      segments.add(
        [
          DirectionsPoint(latitude: pickupLat, longitude: pickupLng),
          DirectionsPoint(latitude: deliveryLat, longitude: deliveryLng),
        ],
      );
    }

    final distanceMeters = segments.fold<double>(0.0, (sum, seg) {
      final a = seg.first;
      final b = seg.last;
      return sum +
          distanceCalc.as(
            LengthUnit.Meter,
            LatLng(a.latitude, a.longitude),
            LatLng(b.latitude, b.longitude),
          );
    });
    final durationSeconds = (distanceMeters / 8.3).round();

    return DirectionsRoute(
      path: segments.expand((s) => s).toList(),
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

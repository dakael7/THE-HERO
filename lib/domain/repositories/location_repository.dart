import 'package:latlong2/latlong.dart';
import '../entities/location_entity.dart';

abstract class LocationRepository {
  /// Get current user location
  Future<LocationEntity> getCurrentLocation();

  /// Stream of location updates
  Stream<LocationEntity> getLocationStream();

  /// Check if location permissions are granted
  Future<bool> checkPermissions();

  /// Request location permissions
  Future<bool> requestPermissions();

  /// Calculate distance between two points in meters
  double calculateDistance(LatLng point1, LatLng point2);

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled();
}

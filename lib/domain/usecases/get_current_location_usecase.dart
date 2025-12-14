import '../entities/location_entity.dart';
import '../repositories/location_repository.dart';

class GetCurrentLocationUseCase {
  final LocationRepository repository;

  const GetCurrentLocationUseCase({required this.repository});

  Future<LocationEntity> call() async {
    // Check if location services are enabled
    final isEnabled = await repository.isLocationServiceEnabled();
    if (!isEnabled) {
      throw LocationServiceDisabledException();
    }

    // Check permissions
    final hasPermission = await repository.checkPermissions();
    if (!hasPermission) {
      // Try to request permissions
      final granted = await repository.requestPermissions();
      if (!granted) {
        throw LocationPermissionDeniedException();
      }
    }

    // Get current location
    return await repository.getCurrentLocation();
  }
}

class LocationServiceDisabledException implements Exception {
  @override
  String toString() => 'Location services are disabled';
}

class LocationPermissionDeniedException implements Exception {
  @override
  String toString() => 'Location permission was denied';
}

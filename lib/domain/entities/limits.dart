import 'vehicle.dart';

class Limits {
  final double maxDistanceKm;
  final double maxWeightKg;

  Limits({
    required this.maxDistanceKm,
    required this.maxWeightKg,
  });

  factory Limits.fromVehicleType(VehicleType vehicleType) {
    switch (vehicleType) {
      case VehicleType.bicycle:
        return Limits(maxDistanceKm: 3, maxWeightKg: 7);
      case VehicleType.motorcycle:
        return Limits(maxDistanceKm: 8, maxWeightKg: 10);
      case VehicleType.car:
        return Limits(maxDistanceKm: double.infinity, maxWeightKg: 25);
      case VehicleType.truck:
        return Limits(maxDistanceKm: double.infinity, maxWeightKg: 80);
    }
  }

  bool canHandleDelivery({
    required double distanceKm,
    required double weightKg,
  }) {
    return distanceKm <= maxDistanceKm && weightKg <= maxWeightKg;
  }

  Limits copyWith({
    double? maxDistanceKm,
    double? maxWeightKg,
  }) {
    return Limits(
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      maxWeightKg: maxWeightKg ?? this.maxWeightKg,
    );
  }
}

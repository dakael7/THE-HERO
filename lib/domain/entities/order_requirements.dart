import 'vehicle.dart';

class OrderRequirements {
  final double weightKg;
  final VehicleType requiredVehicle;
  final double estimatedDistanceKm;

  OrderRequirements({
    required this.weightKg,
    required this.requiredVehicle,
    required this.estimatedDistanceKm,
  });

  static VehicleType calculateRequiredVehicle(double weightKg) {
    if (weightKg <= 7.0) {
      return VehicleType.bicycle;
    } else if (weightKg <= 10.0) {
      return VehicleType.motorcycle;
    } else if (weightKg <= 25.0) {
      return VehicleType.car;
    } else if (weightKg <= 80.0) {
      return VehicleType.truck;
    } else {
      throw Exception('Pedido excede capacidad máxima (80kg)');
    }
  }

  static List<VehicleType> getCompatibleVehicles(VehicleType riderVehicle) {
    switch (riderVehicle) {
      case VehicleType.bicycle:
        return [VehicleType.bicycle];
      case VehicleType.motorcycle:
        return [VehicleType.bicycle, VehicleType.motorcycle];
      case VehicleType.car:
        return [VehicleType.bicycle, VehicleType.motorcycle, VehicleType.car];
      case VehicleType.truck:
        return [VehicleType.bicycle, VehicleType.motorcycle, VehicleType.car, VehicleType.truck];
    }
  }

  bool isCompatibleWith(VehicleType riderVehicle) {
    return getCompatibleVehicles(riderVehicle).contains(requiredVehicle);
  }

  OrderRequirements copyWith({
    double? weightKg,
    VehicleType? requiredVehicle,
    double? estimatedDistanceKm,
  }) {
    return OrderRequirements(
      weightKg: weightKg ?? this.weightKg,
      requiredVehicle: requiredVehicle ?? this.requiredVehicle,
      estimatedDistanceKm: estimatedDistanceKm ?? this.estimatedDistanceKm,
    );
  }
}

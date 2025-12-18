import '../../domain/entities/order_requirements.dart';
import '../../domain/entities/vehicle.dart';

class OrderRequirementsModel {
  final double weightKg;
  final String requiredVehicle;
  final double estimatedDistanceKm;

  OrderRequirementsModel({
    required this.weightKg,
    required this.requiredVehicle,
    required this.estimatedDistanceKm,
  });

  factory OrderRequirementsModel.fromJson(Map<String, dynamic> json) {
    return OrderRequirementsModel(
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0.0,
      requiredVehicle: json['requiredVehicle'] as String? ?? 'bicycle',
      estimatedDistanceKm: (json['estimatedDistanceKm'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weightKg': weightKg,
      'requiredVehicle': requiredVehicle,
      'estimatedDistanceKm': estimatedDistanceKm,
    };
  }

  OrderRequirements toEntity() {
    return OrderRequirements(
      weightKg: weightKg,
      requiredVehicle: _stringToVehicleType(requiredVehicle),
      estimatedDistanceKm: estimatedDistanceKm,
    );
  }

  factory OrderRequirementsModel.fromEntity(OrderRequirements entity) {
    return OrderRequirementsModel(
      weightKg: entity.weightKg,
      requiredVehicle: entity.requiredVehicle.name,
      estimatedDistanceKm: entity.estimatedDistanceKm,
    );
  }

  static VehicleType _stringToVehicleType(String value) {
    switch (value.toLowerCase()) {
      case 'bicycle':
        return VehicleType.bicycle;
      case 'motorcycle':
        return VehicleType.motorcycle;
      case 'car':
        return VehicleType.car;
      case 'truck':
        return VehicleType.truck;
      default:
        return VehicleType.bicycle;
    }
  }
}

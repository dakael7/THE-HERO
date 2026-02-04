enum VehicleType {
  bicycle,
  motorcycle,
  car,
  truck;

  String get displayName {
    switch (this) {
      case VehicleType.bicycle:
        return 'Bicicleta';
      case VehicleType.motorcycle:
        return 'Moto';
      case VehicleType.car:
        return 'Auto';
      case VehicleType.truck:
        return 'Camión';
    }
  }

  static VehicleType fromString(String value) {
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
        throw ArgumentError('Tipo de vehículo inválido: $value');
    }
  }
}

/// Entidad que representa el vehículo de un rider
class Vehicle {
  final VehicleType type;
  final String? plateNumber; // Obligatorio si type != bicycle
  final String? model;
  final int? year;
  final String? color;

  Vehicle({
    required this.type,
    this.plateNumber,
    this.model,
    this.year,
    this.color,
  });

  /// Valida que los campos condicionales estén presentes
  bool get isValid {
    if (type == VehicleType.bicycle) {
      return true;
    }
    return (plateNumber != null && plateNumber!.trim().isNotEmpty)
        && (color != null && color!.trim().isNotEmpty)
        && (model != null && model!.trim().isNotEmpty)
        && (year != null);
  }

  Vehicle copyWith({
    VehicleType? type,
    String? plateNumber,
    String? model,
    int? year,
    String? color,
  }) {
    return Vehicle(
      type: type ?? this.type,
      plateNumber: plateNumber ?? this.plateNumber,
      model: model ?? this.model,
      year: year ?? this.year,
      color: color ?? this.color,
    );
  }
}

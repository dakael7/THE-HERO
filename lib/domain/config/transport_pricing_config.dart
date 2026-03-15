import '../entities/vehicle.dart';

class TransportPricingConfig {
  /// Precio por kilómetro para cada tipo de vehículo
  static const Map<VehicleType, double> pricePerKm = {
    VehicleType.bicycle: 500.0,
    VehicleType.motorcycle: 650.0,
    VehicleType.car: 1000.0,
    VehicleType.truck: 1500.0,
  };

  /// Cobro mínimo por tipo de vehículo
  static const Map<VehicleType, double> minimumCharge = {
    VehicleType.bicycle: 2000.0,
    VehicleType.motorcycle: 3000.0,
    VehicleType.car: 4500.0,
    VehicleType.truck: 10000.0,
  };

  /// Distancia máxima de cobertura por tipo de vehículo (en km)
  static const Map<VehicleType, double> maxDistanceKm = {
    VehicleType.bicycle: 3.5,
    VehicleType.motorcycle: 10.0,
    VehicleType.car: double.infinity,
    VehicleType.truck: double.infinity,
  };

  /// Precio reducido por km después de 30 km (solo para auto y camión)
  static const Map<VehicleType, double> reducedPricePerKmAfter30 = {
    VehicleType.car: 800.0,
    VehicleType.truck: 1200.0,
  };

  /// Distancia a partir de la cual se aplica precio reducido
  static const double distanceThresholdForDiscount = 30.0;

  /// Obtiene el precio por km para un tipo de vehículo
  static double getPricePerKm(VehicleType vehicleType) {
    return pricePerKm[vehicleType] ?? 0.0;
  }

  /// Obtiene el cobro mínimo para un tipo de vehículo
  static double getMinimumCharge(VehicleType vehicleType) {
    return minimumCharge[vehicleType] ?? 0.0;
  }

  /// Obtiene la distancia máxima para un tipo de vehículo
  static double getMaxDistance(VehicleType vehicleType) {
    return maxDistanceKm[vehicleType] ?? double.infinity;
  }

  /// Obtiene el precio reducido por km después de 30 km (si aplica)
  static double? getReducedPricePerKm(VehicleType vehicleType) {
    return reducedPricePerKmAfter30[vehicleType];
  }

  /// Verifica si un tipo de vehículo tiene descuento por distancia
  static bool hasDistanceDiscount(VehicleType vehicleType) {
    return reducedPricePerKmAfter30.containsKey(vehicleType);
  }
}

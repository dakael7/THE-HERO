import '../entities/vehicle.dart';
import '../config/transport_pricing_config.dart';

/// Resultado del cálculo de tarifa de envío
class DeliveryFeeResult {
  final double fee;
  final double distanceKm;
  final VehicleType vehicleType;
  final bool minimumChargeApplied;
  final bool distanceDiscountApplied;
  final String breakdown;

  const DeliveryFeeResult({
    required this.fee,
    required this.distanceKm,
    required this.vehicleType,
    required this.minimumChargeApplied,
    required this.distanceDiscountApplied,
    required this.breakdown,
  });
}

/// Servicio para calcular tarifas de envío
class DeliveryFeeCalculator {
  /// Calcula la tarifa de envío basada en el tipo de vehículo y la distancia
  static DeliveryFeeResult calculateFee({
    required VehicleType vehicleType,
    required double distanceKm,
  }) {
    // Validar que la distancia no exceda el máximo del vehículo
    final maxDistance = TransportPricingConfig.getMaxDistance(vehicleType);
    final effectiveDistanceKm =
        distanceKm > maxDistance ? maxDistance : distanceKm;

    final minimumCharge = TransportPricingConfig.getMinimumCharge(vehicleType);
    double calculatedFee = 0.0;
    bool minimumChargeApplied = false;
    bool distanceDiscountApplied = false;
    String breakdown = '';

    // Calcular tarifa base
    if (effectiveDistanceKm <=
            TransportPricingConfig.distanceThresholdForDiscount ||
        !TransportPricingConfig.hasDistanceDiscount(vehicleType)) {
      // Tarifa normal para toda la distancia
      final pricePerKm = TransportPricingConfig.getPricePerKm(vehicleType);
      calculatedFee = effectiveDistanceKm * pricePerKm;
      breakdown =
          '${effectiveDistanceKm.toStringAsFixed(1)} km × \$${pricePerKm.toStringAsFixed(0)} = \$${calculatedFee.toStringAsFixed(0)}';
    } else {
      // Aplicar descuento por distancia (solo para auto y camión)
      final pricePerKm = TransportPricingConfig.getPricePerKm(vehicleType);
      final reducedPrice = TransportPricingConfig.getReducedPricePerKm(
        vehicleType,
      )!;

      // Primeros 30 km a precio normal
      final normalDistanceFee =
          TransportPricingConfig.distanceThresholdForDiscount * pricePerKm;

      // Distancia adicional a precio reducido
      final extraDistance =
          effectiveDistanceKm -
          TransportPricingConfig.distanceThresholdForDiscount;
      final reducedDistanceFee = extraDistance * reducedPrice;

      calculatedFee = normalDistanceFee + reducedDistanceFee;
      distanceDiscountApplied = true;

      breakdown =
          '30 km × \$${pricePerKm.toStringAsFixed(0)} + ${extraDistance.toStringAsFixed(1)} km × \$${reducedPrice.toStringAsFixed(0)} = \$${calculatedFee.toStringAsFixed(0)}';
    }

    // Aplicar cobro mínimo si la tarifa calculada es menor
    double finalFee = calculatedFee;
    if (calculatedFee < minimumCharge) {
      finalFee = minimumCharge;
      minimumChargeApplied = true;
      breakdown += ' (Cobro mínimo: \$${minimumCharge.toStringAsFixed(0)})';
    }

    return DeliveryFeeResult(
      fee: finalFee,
      distanceKm: effectiveDistanceKm,
      vehicleType: vehicleType,
      minimumChargeApplied: minimumChargeApplied,
      distanceDiscountApplied: distanceDiscountApplied,
      breakdown: breakdown,
    );
  }

  /// Calcula la tarifa de envío con validación de distancia máxima
  static DeliveryFeeResult? tryCalculateFee({
    required VehicleType vehicleType,
    required double distanceKm,
  }) {
    try {
      return calculateFee(vehicleType: vehicleType, distanceKm: distanceKm);
    } catch (e) {
      return null;
    }
  }

  /// Obtiene una estimación de tarifa cuando no se conoce la distancia exacta
  static double estimateFee({
    required VehicleType vehicleType,
    double estimatedDistanceKm = 5.0,
  }) {
    try {
      final result = calculateFee(
        vehicleType: vehicleType,
        distanceKm: estimatedDistanceKm,
      );
      return result.fee;
    } catch (e) {
      // Si falla, retornar el cobro mínimo
      return TransportPricingConfig.getMinimumCharge(vehicleType);
    }
  }
}

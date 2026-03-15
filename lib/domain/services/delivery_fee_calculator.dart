import '../entities/vehicle.dart';
import '../config/transport_pricing_config.dart';
import '../config/pricing_config_provider.dart';

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
  /// Calcula la tarifa usando los valores hardcodeados en [TransportPricingConfig]
  static DeliveryFeeResult calculateFee({
    required VehicleType vehicleType,
    required double distanceKm,
  }) {
    final discount = TransportPricingConfig.hasDistanceDiscount(vehicleType)
        ? TransportPricingConfig.getReducedPricePerKm(vehicleType)
        : null;

    return _compute(
      vehicleType: vehicleType,
      distanceKm: distanceKm,
      maxDistance: TransportPricingConfig.getMaxDistance(vehicleType),
      minimumCharge: TransportPricingConfig.getMinimumCharge(vehicleType),
      pricePerKm: TransportPricingConfig.getPricePerKm(vehicleType),
      discountThresholdKm:
          TransportPricingConfig.hasDistanceDiscount(vehicleType)
          ? TransportPricingConfig.distanceThresholdForDiscount
          : null,
      reducedPricePerKm: discount,
    );
  }

  /// Calcula la tarifa usando un [PricingConfig] remoto.
  static DeliveryFeeResult calculateFeeWith({
    required VehicleType vehicleType,
    required double distanceKm,
    required PricingConfig config,
  }) {
    final discount = config.getDistanceDiscount(vehicleType);
    return _compute(
      vehicleType: vehicleType,
      distanceKm: distanceKm,
      maxDistance: config.getMaxDistance(vehicleType),
      minimumCharge: config.getMinimumCharge(vehicleType),
      pricePerKm: config.getPricePerKm(vehicleType),
      discountThresholdKm: discount.thresholdKm,
      reducedPricePerKm: discount.reducedPricePerKm,
    );
  }

  static DeliveryFeeResult _compute({
    required VehicleType vehicleType,
    required double distanceKm,
    required double maxDistance,
    required double minimumCharge,
    required double pricePerKm,
    required double? discountThresholdKm,
    required double? reducedPricePerKm,
  }) {
    final effectiveDistanceKm = distanceKm > maxDistance
        ? maxDistance
        : distanceKm;

    double calculatedFee = 0.0;
    bool minimumChargeApplied = false;
    bool distanceDiscountApplied = false;
    String breakdown = '';

    final threshold = discountThresholdKm;
    final reduced = reducedPricePerKm;
    final hasDiscount = threshold != null && reduced != null;

    if (!hasDiscount || effectiveDistanceKm <= threshold) {
      calculatedFee = effectiveDistanceKm * pricePerKm;
      breakdown =
          '${effectiveDistanceKm.toStringAsFixed(1)} km × \$${pricePerKm.toStringAsFixed(0)} = \$${calculatedFee.toStringAsFixed(0)}';
    } else {
      final normalDistanceFee = threshold * pricePerKm;
      final extraDistance = effectiveDistanceKm - threshold;
      final reducedDistanceFee = extraDistance * reduced;
      calculatedFee = normalDistanceFee + reducedDistanceFee;
      distanceDiscountApplied = true;

      breakdown =
          '${threshold.toStringAsFixed(0)} km × \$${pricePerKm.toStringAsFixed(0)} + ${extraDistance.toStringAsFixed(1)} km × \$${reduced.toStringAsFixed(0)} = \$${calculatedFee.toStringAsFixed(0)}';
    }

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
      return TransportPricingConfig.getMinimumCharge(vehicleType);
    }
  }
}

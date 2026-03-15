/// Resultado del cálculo de comisiones para riders
class RiderCommissionResult {
  final double deliveryFee;
  final double serviceFee;
  final double taxDeduction;
  final double netEarnings;
  final String breakdown;

  const RiderCommissionResult({
    required this.deliveryFee,
    required this.serviceFee,
    required this.taxDeduction,
    required this.netEarnings,
    required this.breakdown,
  });
}

class RiderCommissionCalculator {
  /// Default comisión fija (fallback local).
  static const double serviceFeeCLP = 2000.0;

  /// Default porcentaje de descuento (fallback local) — 0..1.
  static const double taxPercentage = 0.07;

  /// Calcula la comisión usando los defaults hardcodeados (retrocompatible).
  static RiderCommissionResult calculateCommission({
    required double deliveryFee,
  }) {
    return calculateCommissionWith(
      deliveryFee: deliveryFee,
      serviceFeeCLP: serviceFeeCLP,
      taxPercentage: taxPercentage,
    );
  }

  /// Calcula la comisión con valores personalizados (para remote config).
  static RiderCommissionResult calculateCommissionWith({
    required double deliveryFee,
    required double serviceFeeCLP,
    required double taxPercentage,
  }) {
    final serviceFee = serviceFeeCLP;

    final netDeliveryFee = (deliveryFee - serviceFee).clamp(
      0.0,
      double.infinity,
    );
    final taxDeduction = netDeliveryFee * taxPercentage;

    final netEarnings = netDeliveryFee - taxDeduction;

    final taxPercent = (taxPercentage * 100).toStringAsFixed(0);

    final breakdown =
        '''
Tarifa de envío: \$${deliveryFee.toStringAsFixed(0)}
Comisión de servicio: -\$${serviceFee.toStringAsFixed(0)}
Descuento ($taxPercent% sobre envío neto): -\$${taxDeduction.toStringAsFixed(0)}
━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ganancia neta: \$${netEarnings.toStringAsFixed(0)}
''';

    return RiderCommissionResult(
      deliveryFee: deliveryFee,
      serviceFee: serviceFee,
      taxDeduction: taxDeduction,
      netEarnings: netEarnings,
      breakdown: breakdown,
    );
  }

  static double calculateTotalNetEarnings(List<double> deliveryFees) {
    double total = 0.0;
    for (final fee in deliveryFees) {
      final result = calculateCommission(deliveryFee: fee);
      total += result.netEarnings;
    }
    return total;
  }

  static Map<String, double> getSummary(List<double> deliveryFees) {
    double totalDeliveryFees = 0.0;
    double totalServiceFees = 0.0;
    double totalTaxDeductions = 0.0;
    double totalNetEarnings = 0.0;

    for (final fee in deliveryFees) {
      final result = calculateCommission(deliveryFee: fee);
      totalDeliveryFees += result.deliveryFee;
      totalServiceFees += result.serviceFee;
      totalTaxDeductions += result.taxDeduction;
      totalNetEarnings += result.netEarnings;
    }

    return {
      'totalDeliveryFees': totalDeliveryFees,
      'totalServiceFees': totalServiceFees,
      'totalTaxDeductions': totalTaxDeductions,
      'totalNetEarnings': totalNetEarnings,
      'deliveryCount': deliveryFees.length.toDouble(),
    };
  }

  static double getTotalCommissionPercentage() {
    return taxPercentage * 100;
  }

  static double calculateMinimumFeeForEarnings(double desiredEarnings) {
    return (desiredEarnings + serviceFeeCLP) / (1 - taxPercentage);
  }
}

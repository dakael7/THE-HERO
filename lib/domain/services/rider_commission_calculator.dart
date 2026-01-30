/// Resultado del cálculo de comisiones para riders
class RiderCommissionResult {
  final double deliveryFee; // Tarifa total de envío
  final double serviceFee; // Comisión de servicio fija ($2,000)
  final double taxDeduction; // Descuento por impuestos (14.5%)
  final double netEarnings; // Ganancia neta del rider
  final String breakdown; // Desglose detallado

  const RiderCommissionResult({
    required this.deliveryFee,
    required this.serviceFee,
    required this.taxDeduction,
    required this.netEarnings,
    required this.breakdown,
  });
}

/// Servicio para calcular comisiones de riders
class RiderCommissionCalculator {
  /// Comisión de servicio fija
  static const double serviceFeeCLP = 2000.0;

  /// Porcentaje de descuento por impuestos (14.5%)
  static const double taxPercentage = 0.145;

  /// Calcula las comisiones y ganancia neta del rider
  static RiderCommissionResult calculateCommission({
    required double deliveryFee,
  }) {
    // Comisión de servicio fija
    const serviceFee = serviceFeeCLP;

    // Descuento por impuestos (14.5% del total)
    final taxDeduction = deliveryFee * taxPercentage;

    // Ganancia neta = Tarifa - Comisión - Impuestos
    final netEarnings = deliveryFee - serviceFee - taxDeduction;

    // Crear desglose detallado
    final breakdown =
        '''
Tarifa de envío: \$${deliveryFee.toStringAsFixed(0)}
Comisión de servicio: -\$${serviceFee.toStringAsFixed(0)}
Impuestos (14.5%): -\$${taxDeduction.toStringAsFixed(0)}
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

  /// Calcula el total de ganancias netas de múltiples entregas
  static double calculateTotalNetEarnings(List<double> deliveryFees) {
    double total = 0.0;
    for (final fee in deliveryFees) {
      final result = calculateCommission(deliveryFee: fee);
      total += result.netEarnings;
    }
    return total;
  }

  /// Obtiene un resumen de comisiones para múltiples entregas
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

  /// Calcula el porcentaje de comisión total (servicio + impuestos)
  static double getTotalCommissionPercentage() {
    // Comisión de servicio como porcentaje (varía según tarifa)
    // + 14.5% de impuestos
    // Para una tarifa promedio de 10,000: 2000/10000 = 20% + 14.5% = 34.5%
    // Pero es variable, así que retornamos solo el componente fijo
    return taxPercentage * 100; // 14.5%
  }

  /// Calcula la tarifa mínima recomendada para que el rider gane al menos X
  static double calculateMinimumFeeForEarnings(double desiredEarnings) {
    // netEarnings = deliveryFee - serviceFee - (deliveryFee * taxPercentage)
    // netEarnings = deliveryFee * (1 - taxPercentage) - serviceFee
    // deliveryFee = (netEarnings + serviceFee) / (1 - taxPercentage)
    return (desiredEarnings + serviceFeeCLP) / (1 - taxPercentage);
  }
}

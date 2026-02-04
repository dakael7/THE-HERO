import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/order_requirements.dart';
import '../../../domain/services/delivery_fee_calculator.dart';
import 'cart_provider.dart';

class CartSummary {
  final double subtotal;
  final double shippingCost;
  final double serviceFee;
  final double tax;
  final double total;
  final double totalWeight;
  final String? shippingBreakdown;

  const CartSummary({
    required this.subtotal,
    required this.shippingCost,
    required this.serviceFee,
    required this.tax,
    required this.total,
    required this.totalWeight,
    this.shippingBreakdown,
  });
}

final cartSummaryProvider = Provider<CartSummary>((ref) {
  final cartItems = ref.watch(cartProvider);

  double subtotal = 0.0;
  double totalWeight = 0.0;

  for (final item in cartItems) {
    subtotal += item.price * item.quantity;
    totalWeight += item.weight * item.quantity;
  }

  // Calcular tipo de vehículo requerido basado en el peso total
  final requiredVehicle = (() {
    if (totalWeight <= 0) return null;
    try {
      return OrderRequirements.calculateRequiredVehicle(totalWeight);
    } catch (_) {
      return null;
    }
  })();

  // Calcular costo de envío dinámicamente
  // Usamos una distancia estimada de 5 km si no tenemos la distancia real
  // Esto se actualizará cuando el usuario ingrese su dirección
  double shippingCost = 0.0;
  String? shippingBreakdown;

  if (requiredVehicle == null && totalWeight > 0) {
    shippingBreakdown =
        'No se pudo calcular el tipo de vehículo para el peso total (${totalWeight.toStringAsFixed(2)} kg).';
  }

  if (requiredVehicle != null && cartItems.isNotEmpty) {
    const estimatedDistanceKm = 5.0;
    final feeResult = DeliveryFeeCalculator.tryCalculateFee(
      vehicleType: requiredVehicle,
      distanceKm: estimatedDistanceKm,
    );

    if (feeResult != null) {
      shippingCost = feeResult.fee;
      shippingBreakdown = feeResult.breakdown;
    } else {
      shippingCost = DeliveryFeeCalculator.estimateFee(
        vehicleType: requiredVehicle,
        estimatedDistanceKm: estimatedDistanceKm,
      );
      shippingBreakdown =
          'Estimación por defecto no disponible (distancia ${estimatedDistanceKm.toStringAsFixed(1)} km excede el máximo).';
    }
  }

  // Comisión de servicio fija de $2,000 CLP
  const serviceFee = 2000.0;
  const taxPercentage = 0.19;

  final subtotalWithFees = subtotal + shippingCost + serviceFee;
  final tax = subtotalWithFees * taxPercentage;
  final total = subtotalWithFees + tax;

  return CartSummary(
    subtotal: subtotal,
    shippingCost: shippingCost,
    serviceFee: serviceFee,
    tax: tax,
    total: total,
    totalWeight: totalWeight,
    shippingBreakdown: shippingBreakdown,
  );
});

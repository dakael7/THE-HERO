import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cart_provider.dart';

class CartSummary {
  final double subtotal;
  final double shippingCost;
  final double serviceFee;
  final double tax;
  final double total;
  final double totalWeight;

  const CartSummary({
    required this.subtotal,
    required this.shippingCost,
    required this.serviceFee,
    required this.tax,
    required this.total,
    required this.totalWeight,
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

  const shippingCost = 1500.0;
  const serviceFeePercentage = 0.05;
  const taxPercentage = 0.19;

  final serviceFee = subtotal * serviceFeePercentage;
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
  );
});

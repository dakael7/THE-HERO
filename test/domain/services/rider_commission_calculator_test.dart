import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/domain/services/rider_commission_calculator.dart';

void main() {
  test('does not wipe out low app delivery fees by default', () {
    final result = RiderCommissionCalculator.calculateCommission(
      deliveryFee: 1500,
    );

    expect(result.serviceFee, 0);
    expect(result.netEarnings, 1395);
  });

  test('respects an explicit zero service fee', () {
    final result = RiderCommissionCalculator.calculateCommissionWith(
      deliveryFee: 3000,
      serviceFeeCLP: 0,
      taxPercentage: 0.07,
    );

    expect(result.serviceFee, 0);
    expect(result.netEarnings, 2790);
  });
}

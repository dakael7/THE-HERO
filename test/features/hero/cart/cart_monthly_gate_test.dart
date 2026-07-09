import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/features/hero/cart/cart_monthly_gate.dart';

void main() {
  test('monthly cart order limit grows by three per donated item', () {
    expect(cartMonthlyOrderLimitForDonations(0), 3);
    expect(cartMonthlyOrderLimitForDonations(1), 6);
    expect(cartMonthlyOrderLimitForDonations(2), 9);
    expect(cartMonthlyOrderLimitForDonations(-1), 3);
  });
}

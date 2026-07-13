import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/features/hero/cart/cart_monthly_gate.dart';

void main() {
  test('weekly cart order limit grows by three per donation', () {
    expect(cartWeeklyOrderLimitForDonations(0), 3);
    expect(cartWeeklyOrderLimitForDonations(1), 6);
    expect(cartWeeklyOrderLimitForDonations(2), 9);
    expect(cartWeeklyOrderLimitForDonations(-1), 3);
  });
}

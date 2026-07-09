import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/features/hero/cart/checkout_coupon.dart';

void main() {
  test('percent coupon is capped to the checkout amount', () {
    final coupon = CheckoutCoupon.fromFirestore(
      id: 'SAVE150',
      data: const {'active': true, 'type': 'percent', 'value': 150},
    );

    expect(coupon.discountFor(1200), 1200);
    expect(coupon.toOrderJson(1200)['type'], 'percent');
  });

  test('fixed coupon does not discount inactive or negative base', () {
    final coupon = CheckoutCoupon.fromFirestore(
      id: 'SHIP',
      data: const {'active': false, 'type': 'fixed', 'value': 800},
    );

    expect(coupon.discountFor(1200), 0);
    expect(coupon.discountFor(-1), 0);
  });
}

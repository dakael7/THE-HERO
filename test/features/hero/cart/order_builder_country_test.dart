import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/data/models/order_model.dart';
import 'package:the_hero/features/hero/cart/cart_item.dart';
import 'package:the_hero/features/hero/cart/cart_summary_provider.dart';
import 'package:the_hero/features/hero/cart/order_builder.dart';

void main() {
  test('buildOrderFromCart stores normalized country code', () {
    final order = OrderBuilder.buildOrderFromCart(
      cartItems: const [
        CartItem(
          offerId: 'offer-1',
          name: 'Mesa',
          condition: 'used',
          price: 0,
          imageUrl: '',
          pickupCountryCode: 'CL',
        ),
      ],
      cartSummary: const CartSummary(
        subtotal: 0,
        shippingCost: 1000,
        serviceFee: 0,
        tax: 0,
        total: 1000,
        totalWeight: 1,
      ),
      heroId: 'hero-1',
      countryCode: ' cl ',
      delivery: OrderBuilder.createDelivery(
        address: 'Santiago',
        recipientName: 'Hero',
        recipientPhone: '+56000000000',
      ),
    );

    expect(order.countryCode, 'CL');
    expect(OrderModel.fromEntity(order).toJson()['countryCode'], 'CL');
  });
}

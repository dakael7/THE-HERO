import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/pickup_schedule.dart';
import '../../../domain/entities/concierge_info.dart';

class CartItem {
  final String offerId;
  final String name;
  final String condition;
  final int quantity;
  final double price;
  final double weight;
  final String imageUrl;
  final PickupSchedule? pickupSchedule;
  final bool useConcierge;
  final ConciergeInfo? conciergeInfo;

  const CartItem({
    required this.offerId,
    required this.name,
    required this.condition,
    this.quantity = 1,
    required this.price,
    this.weight = 0.5,
    required this.imageUrl,
    this.pickupSchedule,
    this.useConcierge = false,
    this.conciergeInfo,
  });

  CartItem copyWith({int? quantity}) {
    return CartItem(
      offerId: offerId,
      name: name,
      condition: condition,
      quantity: quantity ?? this.quantity,
      price: price,
      weight: weight,
      imageUrl: imageUrl,
      pickupSchedule: pickupSchedule,
      useConcierge: useConcierge,
      conciergeInfo: conciergeInfo,
    );
  }

  // Convert CartItem to OrderItem
  OrderItem toOrderItem() {
    return OrderItem(
      offerId: offerId,
      titleSnapshot: name,
      unitPriceSnapshot: price,
      qty: quantity,
      weightSnapshot: weight,
      imageUrlSnapshot: imageUrl,
    );
  }
}

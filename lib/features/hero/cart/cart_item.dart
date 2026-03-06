import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/pickup_schedule.dart';
import '../../../domain/entities/concierge_info.dart';

class CartItem {
  final String offerId;
  final String? sellerHeroId;
  final String name;
  final String condition;
  final int quantity;
  final int? availableQty;
  final double price;
  final double weight;
  final String imageUrl;
  final firestore.GeoPoint? pickupGeo;
  final String? pickupAddressSnapshot;
  final String? pickupCountryCode;
  final PickupSchedule? pickupSchedule;
  final bool useConcierge;
  final ConciergeInfo? conciergeInfo;
  final bool allowInPersonPickup;

  const CartItem({
    required this.offerId,
    this.sellerHeroId,
    required this.name,
    required this.condition,
    this.quantity = 1,
    this.availableQty,
    required this.price,
    this.weight = 0.5,
    required this.imageUrl,
    this.pickupGeo,
    this.pickupAddressSnapshot,
    this.pickupCountryCode,
    this.pickupSchedule,
    this.useConcierge = false,
    this.conciergeInfo,
    this.allowInPersonPickup = false,
  });

  CartItem copyWith({int? quantity, int? availableQty}) {
    return CartItem(
      offerId: offerId,
      sellerHeroId: sellerHeroId,
      name: name,
      condition: condition,
      quantity: quantity ?? this.quantity,
      availableQty: availableQty ?? this.availableQty,
      price: price,
      weight: weight,
      imageUrl: imageUrl,
      pickupGeo: pickupGeo,
      pickupAddressSnapshot: pickupAddressSnapshot,
      pickupCountryCode: pickupCountryCode,
      pickupSchedule: pickupSchedule,
      useConcierge: useConcierge,
      conciergeInfo: conciergeInfo,
      allowInPersonPickup: allowInPersonPickup,
    );
  }

  // Convert CartItem to OrderItem
  OrderItem toOrderItem() {
    return OrderItem(
      offerId: offerId,
      sellerHeroIdSnapshot: sellerHeroId?.trim() ?? '',
      titleSnapshot: name,
      unitPriceSnapshot: price,
      qty: quantity,
      weightSnapshot: weight,
      imageUrlSnapshot: imageUrl,
    );
  }
}

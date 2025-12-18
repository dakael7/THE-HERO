import 'package:cloud_firestore/cloud_firestore.dart';

class OrderDelivery {
  final GeoPoint geo;
  final String addressSnapshot;
  final String recipientName;
  final String recipientPhone;
  final String instructions;

  OrderDelivery({
    required this.geo,
    required this.addressSnapshot,
    required this.recipientName,
    required this.recipientPhone,
    this.instructions = '',
  });

  OrderDelivery copyWith({
    GeoPoint? geo,
    String? addressSnapshot,
    String? recipientName,
    String? recipientPhone,
    String? instructions,
  }) {
    return OrderDelivery(
      geo: geo ?? this.geo,
      addressSnapshot: addressSnapshot ?? this.addressSnapshot,
      recipientName: recipientName ?? this.recipientName,
      recipientPhone: recipientPhone ?? this.recipientPhone,
      instructions: instructions ?? this.instructions,
    );
  }
}

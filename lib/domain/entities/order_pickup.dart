import 'package:cloud_firestore/cloud_firestore.dart';

class OrderPickup {
  final GeoPoint geo;
  final String geohash;
  final String addressSnapshot;
  final String contactName;
  final String contactPhone;
  final String instructions;

  OrderPickup({
    required this.geo,
    required this.geohash,
    required this.addressSnapshot,
    required this.contactName,
    required this.contactPhone,
    this.instructions = '',
  });

  OrderPickup copyWith({
    GeoPoint? geo,
    String? geohash,
    String? addressSnapshot,
    String? contactName,
    String? contactPhone,
    String? instructions,
  }) {
    return OrderPickup(
      geo: geo ?? this.geo,
      geohash: geohash ?? this.geohash,
      addressSnapshot: addressSnapshot ?? this.addressSnapshot,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      instructions: instructions ?? this.instructions,
    );
  }
}

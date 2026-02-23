import 'package:cloud_firestore/cloud_firestore.dart';

class OrderPickupStop {
  final GeoPoint geo;
  final String addressSnapshot;
  final List<String> offerIds;

  OrderPickupStop({
    required this.geo,
    this.addressSnapshot = '',
    required this.offerIds,
  });

  OrderPickupStop copyWith({
    GeoPoint? geo,
    String? addressSnapshot,
    List<String>? offerIds,
  }) {
    return OrderPickupStop(
      geo: geo ?? this.geo,
      addressSnapshot: addressSnapshot ?? this.addressSnapshot,
      offerIds: offerIds ?? this.offerIds,
    );
  }
}

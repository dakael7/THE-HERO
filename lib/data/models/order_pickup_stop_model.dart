import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../domain/entities/order_pickup_stop.dart';

class OrderPickupStopModel {
  final firestore.GeoPoint geo;
  final String addressSnapshot;
  final List<String> offerIds;

  OrderPickupStopModel({
    required this.geo,
    this.addressSnapshot = '',
    required this.offerIds,
  });

  factory OrderPickupStopModel.fromJson(Map<String, dynamic> json) {
    firestore.GeoPoint geo;
    final geoData = json['geo'];
    if (geoData is firestore.GeoPoint) {
      geo = geoData;
    } else if (geoData is Map) {
      final lat = (geoData['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (geoData['longitude'] as num?)?.toDouble() ?? 0.0;
      geo = firestore.GeoPoint(lat, lng);
    } else {
      geo = const firestore.GeoPoint(0, 0);
    }

    return OrderPickupStopModel(
      geo: geo,
      addressSnapshot: json['addressSnapshot'] as String? ?? '',
      offerIds:
          (json['offerIds'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geo': {'latitude': geo.latitude, 'longitude': geo.longitude},
      'addressSnapshot': addressSnapshot,
      'offerIds': offerIds,
    };
  }

  OrderPickupStop toEntity() {
    return OrderPickupStop(
      geo: firestore.GeoPoint(geo.latitude, geo.longitude),
      addressSnapshot: addressSnapshot,
      offerIds: offerIds,
    );
  }

  factory OrderPickupStopModel.fromEntity(OrderPickupStop entity) {
    return OrderPickupStopModel(
      geo: firestore.GeoPoint(entity.geo.latitude, entity.geo.longitude),
      addressSnapshot: entity.addressSnapshot,
      offerIds: entity.offerIds,
    );
  }
}

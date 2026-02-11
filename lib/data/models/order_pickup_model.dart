import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/order_pickup.dart';

class OrderPickupModel {
  final GeoPoint geo;
  final String geohash;
  final String addressSnapshot;
  final String contactName;
  final String contactPhone;
  final String instructions;

  OrderPickupModel({
    required this.geo,
    required this.geohash,
    required this.addressSnapshot,
    required this.contactName,
    required this.contactPhone,
    this.instructions = '',
  });

  factory OrderPickupModel.fromJson(Map<String, dynamic> json) {
    // Handle both GeoPoint and Map formats
    GeoPoint geo;
    final geoData = json['geo'];
    if (geoData is GeoPoint) {
      geo = geoData;
    } else if (geoData is Map) {
      final lat = (geoData['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (geoData['longitude'] as num?)?.toDouble() ?? 0.0;
      geo = GeoPoint(lat, lng);
    } else {
      geo = const GeoPoint(0, 0);
    }

    return OrderPickupModel(
      geo: geo,
      geohash: json['geohash'] as String? ?? '',
      addressSnapshot: json['addressSnapshot'] as String? ?? '',
      contactName: json['contactName'] as String? ?? '',
      contactPhone: json['contactPhone'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geo': {'latitude': geo.latitude, 'longitude': geo.longitude},
      'geohash': geohash,
      'addressSnapshot': addressSnapshot,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'instructions': instructions,
    };
  }

  OrderPickup toEntity() {
    return OrderPickup(
      geo: geo,
      geohash: geohash,
      addressSnapshot: addressSnapshot,
      contactName: contactName,
      contactPhone: contactPhone,
      instructions: instructions,
    );
  }

  factory OrderPickupModel.fromEntity(OrderPickup entity) {
    return OrderPickupModel(
      geo: entity.geo,
      geohash: entity.geohash,
      addressSnapshot: entity.addressSnapshot,
      contactName: entity.contactName,
      contactPhone: entity.contactPhone,
      instructions: entity.instructions,
    );
  }
}

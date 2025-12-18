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
    return OrderPickupModel(
      geo: json['geo'] as GeoPoint? ?? const GeoPoint(0, 0),
      geohash: json['geohash'] as String? ?? '',
      addressSnapshot: json['addressSnapshot'] as String? ?? '',
      contactName: json['contactName'] as String? ?? '',
      contactPhone: json['contactPhone'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geo': geo,
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

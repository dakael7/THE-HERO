import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/order_delivery.dart';

class OrderDeliveryModel {
  final GeoPoint geo;
  final String addressSnapshot;
  final String recipientName;
  final String recipientPhone;
  final String instructions;
  final bool deliverToReception;

  OrderDeliveryModel({
    required this.geo,
    required this.addressSnapshot,
    required this.recipientName,
    required this.recipientPhone,
    this.instructions = '',
    this.deliverToReception = false,
  });

  factory OrderDeliveryModel.fromJson(Map<String, dynamic> json) {
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

    return OrderDeliveryModel(
      geo: geo,
      addressSnapshot: json['addressSnapshot'] as String? ?? '',
      recipientName: json['recipientName'] as String? ?? '',
      recipientPhone: json['recipientPhone'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      deliverToReception: json['deliverToReception'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geo': {'latitude': geo.latitude, 'longitude': geo.longitude},
      'addressSnapshot': addressSnapshot,
      'recipientName': recipientName,
      'recipientPhone': recipientPhone,
      'instructions': instructions,
      'deliverToReception': deliverToReception,
    };
  }

  OrderDelivery toEntity() {
    return OrderDelivery(
      geo: geo,
      addressSnapshot: addressSnapshot,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      instructions: instructions,
      deliverToReception: deliverToReception,
    );
  }

  factory OrderDeliveryModel.fromEntity(OrderDelivery entity) {
    return OrderDeliveryModel(
      geo: entity.geo,
      addressSnapshot: entity.addressSnapshot,
      recipientName: entity.recipientName,
      recipientPhone: entity.recipientPhone,
      instructions: entity.instructions,
      deliverToReception: entity.deliverToReception,
    );
  }
}

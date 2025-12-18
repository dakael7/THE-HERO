import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/order_delivery.dart';

class OrderDeliveryModel {
  final GeoPoint geo;
  final String addressSnapshot;
  final String recipientName;
  final String recipientPhone;
  final String instructions;

  OrderDeliveryModel({
    required this.geo,
    required this.addressSnapshot,
    required this.recipientName,
    required this.recipientPhone,
    this.instructions = '',
  });

  factory OrderDeliveryModel.fromJson(Map<String, dynamic> json) {
    return OrderDeliveryModel(
      geo: json['geo'] as GeoPoint? ?? const GeoPoint(0, 0),
      addressSnapshot: json['addressSnapshot'] as String? ?? '',
      recipientName: json['recipientName'] as String? ?? '',
      recipientPhone: json['recipientPhone'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geo': geo,
      'addressSnapshot': addressSnapshot,
      'recipientName': recipientName,
      'recipientPhone': recipientPhone,
      'instructions': instructions,
    };
  }

  OrderDelivery toEntity() {
    return OrderDelivery(
      geo: geo,
      addressSnapshot: addressSnapshot,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      instructions: instructions,
    );
  }

  factory OrderDeliveryModel.fromEntity(OrderDelivery entity) {
    return OrderDeliveryModel(
      geo: entity.geo,
      addressSnapshot: entity.addressSnapshot,
      recipientName: entity.recipientName,
      recipientPhone: entity.recipientPhone,
      instructions: entity.instructions,
    );
  }
}

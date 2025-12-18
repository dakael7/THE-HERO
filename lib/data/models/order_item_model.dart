import '../../domain/entities/order_item.dart';

class OrderItemModel {
  final String offerId;
  final String titleSnapshot;
  final double unitPriceSnapshot;
  final int qty;
  final double weightSnapshot;
  final String imageUrlSnapshot;

  OrderItemModel({
    required this.offerId,
    required this.titleSnapshot,
    required this.unitPriceSnapshot,
    required this.qty,
    required this.weightSnapshot,
    required this.imageUrlSnapshot,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      offerId: json['offerId'] as String? ?? '',
      titleSnapshot: json['titleSnapshot'] as String? ?? '',
      unitPriceSnapshot: (json['unitPriceSnapshot'] as num?)?.toDouble() ?? 0.0,
      qty: json['qty'] as int? ?? 0,
      weightSnapshot: (json['weightSnapshot'] as num?)?.toDouble() ?? 0.0,
      imageUrlSnapshot: json['imageUrlSnapshot'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offerId': offerId,
      'titleSnapshot': titleSnapshot,
      'unitPriceSnapshot': unitPriceSnapshot,
      'qty': qty,
      'weightSnapshot': weightSnapshot,
      'imageUrlSnapshot': imageUrlSnapshot,
    };
  }

  OrderItem toEntity() {
    return OrderItem(
      offerId: offerId,
      titleSnapshot: titleSnapshot,
      unitPriceSnapshot: unitPriceSnapshot,
      qty: qty,
      weightSnapshot: weightSnapshot,
      imageUrlSnapshot: imageUrlSnapshot,
    );
  }

  factory OrderItemModel.fromEntity(OrderItem entity) {
    return OrderItemModel(
      offerId: entity.offerId,
      titleSnapshot: entity.titleSnapshot,
      unitPriceSnapshot: entity.unitPriceSnapshot,
      qty: entity.qty,
      weightSnapshot: entity.weightSnapshot,
      imageUrlSnapshot: entity.imageUrlSnapshot,
    );
  }
}

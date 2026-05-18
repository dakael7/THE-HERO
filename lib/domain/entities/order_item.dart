class OrderItem {
  final String offerId;
  final String sellerHeroIdSnapshot;
  final String categorySnapshot;
  final String titleSnapshot;
  final double unitPriceSnapshot;
  final int qty;
  final double weightSnapshot;
  final String imageUrlSnapshot;

  OrderItem({
    required this.offerId,
    this.sellerHeroIdSnapshot = '',
    this.categorySnapshot = '',
    required this.titleSnapshot,
    required this.unitPriceSnapshot,
    required this.qty,
    required this.weightSnapshot,
    required this.imageUrlSnapshot,
  });

  double get totalPrice => unitPriceSnapshot * qty;
  double get totalWeight => weightSnapshot * qty;

  OrderItem copyWith({
    String? offerId,
    String? sellerHeroIdSnapshot,
    String? categorySnapshot,
    String? titleSnapshot,
    double? unitPriceSnapshot,
    int? qty,
    double? weightSnapshot,
    String? imageUrlSnapshot,
  }) {
    return OrderItem(
      offerId: offerId ?? this.offerId,
      sellerHeroIdSnapshot: sellerHeroIdSnapshot ?? this.sellerHeroIdSnapshot,
      categorySnapshot: categorySnapshot ?? this.categorySnapshot,
      titleSnapshot: titleSnapshot ?? this.titleSnapshot,
      unitPriceSnapshot: unitPriceSnapshot ?? this.unitPriceSnapshot,
      qty: qty ?? this.qty,
      weightSnapshot: weightSnapshot ?? this.weightSnapshot,
      imageUrlSnapshot: imageUrlSnapshot ?? this.imageUrlSnapshot,
    );
  }
}

import 'offer_status.dart';

class Offer {
  final String offerId;
  final String heroId;
  final String title;
  final String description;
  final String category;
  final double price;
  final String currency;
  final int stock;
  final int availableQty;
  final String coverImageUrl;
  final List<String> imageUrls;
  final OfferStatus status;
  final List<String> searchKeywords;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final int viewCount;
  final int orderCount;

  Offer({
    required this.offerId,
    required this.heroId,
    required this.title,
    required this.description,
    required this.category,
    required this.price,
    required this.currency,
    required this.stock,
    required this.availableQty,
    required this.coverImageUrl,
    required this.imageUrls,
    required this.status,
    required this.searchKeywords,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.viewCount = 0,
    this.orderCount = 0,
  });

  bool get isPublished => status.isPublished;
  bool get isVisible => status.isVisible;
  bool get canBeEdited => status.canBeEdited;
  bool get isAvailable => availableQty > 0 && status == OfferStatus.active;
  bool get isSoldOut => availableQty == 0;

  Offer copyWith({
    String? offerId,
    String? heroId,
    String? title,
    String? description,
    String? category,
    double? price,
    String? currency,
    int? stock,
    int? availableQty,
    String? coverImageUrl,
    List<String>? imageUrls,
    OfferStatus? status,
    List<String>? searchKeywords,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? publishedAt,
    int? viewCount,
    int? orderCount,
  }) {
    return Offer(
      offerId: offerId ?? this.offerId,
      heroId: heroId ?? this.heroId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      stock: stock ?? this.stock,
      availableQty: availableQty ?? this.availableQty,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      viewCount: viewCount ?? this.viewCount,
      orderCount: orderCount ?? this.orderCount,
    );
  }
}

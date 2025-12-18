import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/offer.dart';
import '../../domain/entities/offer_status.dart';

class OfferModel {
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
  final String status;
  final List<String> searchKeywords;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final Timestamp? publishedAt;
  final int viewCount;
  final int orderCount;

  OfferModel({
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

  factory OfferModel.fromJson(Map<String, dynamic> json) {
    return OfferModel(
      offerId: json['offerId'] as String? ?? '',
      heroId: json['heroId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'CLP',
      stock: json['stock'] as int? ?? 0,
      availableQty: json['availableQty'] as int? ?? 0,
      coverImageUrl: json['coverImageUrl'] as String? ?? '',
      imageUrls: (json['imageUrls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      status: json['status'] as String? ?? 'draft',
      searchKeywords: (json['searchKeywords'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updatedAt'] as Timestamp? ?? Timestamp.now(),
      publishedAt: json['publishedAt'] as Timestamp?,
      viewCount: json['viewCount'] as int? ?? 0,
      orderCount: json['orderCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offerId': offerId,
      'heroId': heroId,
      'title': title,
      'description': description,
      'category': category,
      'price': price,
      'currency': currency,
      'stock': stock,
      'availableQty': availableQty,
      'coverImageUrl': coverImageUrl,
      'imageUrls': imageUrls,
      'status': status,
      'searchKeywords': searchKeywords,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'publishedAt': publishedAt,
      'viewCount': viewCount,
      'orderCount': orderCount,
    };
  }

  Offer toEntity() {
    return Offer(
      offerId: offerId,
      heroId: heroId,
      title: title,
      description: description,
      category: category,
      price: price,
      currency: currency,
      stock: stock,
      availableQty: availableQty,
      coverImageUrl: coverImageUrl,
      imageUrls: imageUrls,
      status: _stringToOfferStatus(status),
      searchKeywords: searchKeywords,
      createdAt: createdAt.toDate(),
      updatedAt: updatedAt.toDate(),
      publishedAt: publishedAt?.toDate(),
      viewCount: viewCount,
      orderCount: orderCount,
    );
  }

  factory OfferModel.fromEntity(Offer entity) {
    return OfferModel(
      offerId: entity.offerId,
      heroId: entity.heroId,
      title: entity.title,
      description: entity.description,
      category: entity.category,
      price: entity.price,
      currency: entity.currency,
      stock: entity.stock,
      availableQty: entity.availableQty,
      coverImageUrl: entity.coverImageUrl,
      imageUrls: entity.imageUrls,
      status: _offerStatusToString(entity.status),
      searchKeywords: entity.searchKeywords,
      createdAt: Timestamp.fromDate(entity.createdAt),
      updatedAt: Timestamp.fromDate(entity.updatedAt),
      publishedAt: entity.publishedAt != null ? Timestamp.fromDate(entity.publishedAt!) : null,
      viewCount: entity.viewCount,
      orderCount: entity.orderCount,
    );
  }

  static OfferStatus _stringToOfferStatus(String value) {
    switch (value.toLowerCase()) {
      case 'draft':
        return OfferStatus.draft;
      case 'active':
        return OfferStatus.active;
      case 'paused':
        return OfferStatus.paused;
      case 'sold_out':
      case 'soldout':
        return OfferStatus.soldOut;
      case 'archived':
        return OfferStatus.archived;
      default:
        return OfferStatus.draft;
    }
  }

  static String _offerStatusToString(OfferStatus status) {
    switch (status) {
      case OfferStatus.draft:
        return 'draft';
      case OfferStatus.active:
        return 'active';
      case OfferStatus.paused:
        return 'paused';
      case OfferStatus.soldOut:
        return 'sold_out';
      case OfferStatus.archived:
        return 'archived';
    }
  }
}

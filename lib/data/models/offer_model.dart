import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/offer.dart';
import '../../domain/entities/offer_status.dart';
import '../../domain/entities/offer_condition.dart';
import 'address_model.dart';

class OfferModel {
  final String offerId;
  final String heroId;
  final String title;
  final String description;
  final String category;
  final OfferCondition condition;
  final double price;
  final String currency;
  final int stock;
  final int availableQty;
  final double weight;
  final String coverImageUrl;
  final List<String> imageUrls;
  final String status;
  final List<String> searchKeywords;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final Timestamp? publishedAt;
  final int viewCount;
  final int orderCount;
  final double avgRating;
  final int ratingCount;
  final String? itemLocationId;
  final AddressModel? itemLocationSnapshot;

  OfferModel({
    required this.offerId,
    required this.heroId,
    required this.title,
    required this.description,
    required this.category,
    required this.condition,
    required this.price,
    required this.currency,
    required this.stock,
    required this.availableQty,
    required this.weight,
    required this.coverImageUrl,
    required this.imageUrls,
    required this.status,
    required this.searchKeywords,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.viewCount = 0,
    this.orderCount = 0,
    this.avgRating = 0.0,
    this.ratingCount = 0,
    this.itemLocationId,
    this.itemLocationSnapshot,
  });

  factory OfferModel.fromJson(Map<String, dynamic> json) {
    return OfferModel(
      offerId: json['offerId'] as String? ?? '',
      heroId: json['heroId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      condition: _stringToCondition(json['condition'] as String? ?? 'new'),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'CLP',
      stock: json['stock'] as int? ?? 0,
      availableQty: json['availableQty'] as int? ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 0.5,
      coverImageUrl: json['coverImageUrl'] as String? ?? '',
      imageUrls:
          (json['imageUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String? ?? 'draft',
      searchKeywords:
          (json['searchKeywords'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updatedAt'] as Timestamp? ?? Timestamp.now(),
      publishedAt: json['publishedAt'] as Timestamp?,
      viewCount: json['viewCount'] as int? ?? 0,
      orderCount: json['orderCount'] as int? ?? 0,
      avgRating: (json['avgRating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: json['ratingCount'] as int? ?? 0,
      itemLocationId: json['itemLocationId'] as String?,
      itemLocationSnapshot: json['itemLocationSnapshot'] != null
          ? AddressModel.fromJson(
              json['itemLocationSnapshot'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offerId': offerId,
      'heroId': heroId,
      'title': title,
      'description': description,
      'category': category,
      'condition': _conditionToString(condition),
      'price': price,
      'currency': currency,
      'stock': stock,
      'availableQty': availableQty,
      'weight': weight,
      'coverImageUrl': coverImageUrl,
      'imageUrls': imageUrls,
      'status': status,
      'searchKeywords': searchKeywords,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'publishedAt': publishedAt,
      'viewCount': viewCount,
      'orderCount': orderCount,
      'avgRating': avgRating,
      'ratingCount': ratingCount,
      'itemLocationId': itemLocationId,
      'itemLocationSnapshot': itemLocationSnapshot?.toJson(),
    };
  }

  Offer toEntity() {
    return Offer(
      offerId: offerId,
      heroId: heroId,
      title: title,
      description: description,
      category: category,
      condition: condition,
      price: price,
      currency: currency,
      stock: stock,
      availableQty: availableQty,
      weight: weight,
      coverImageUrl: coverImageUrl,
      imageUrls: imageUrls,
      status: _stringToOfferStatus(status),
      searchKeywords: searchKeywords,
      createdAt: createdAt.toDate(),
      updatedAt: updatedAt.toDate(),
      publishedAt: publishedAt?.toDate(),
      viewCount: viewCount,
      orderCount: orderCount,
      avgRating: avgRating,
      ratingCount: ratingCount,
      itemLocationId: itemLocationId,
      itemLocationSnapshot: itemLocationSnapshot?.toEntity(),
    );
  }

  factory OfferModel.fromEntity(Offer entity) {
    return OfferModel(
      offerId: entity.offerId,
      heroId: entity.heroId,
      title: entity.title,
      description: entity.description,
      category: entity.category,
      condition: entity.condition,
      price: entity.price,
      currency: entity.currency,
      stock: entity.stock,
      availableQty: entity.availableQty,
      weight: entity.weight,
      coverImageUrl: entity.coverImageUrl,
      imageUrls: entity.imageUrls,
      status: _offerStatusToString(entity.status),
      searchKeywords: entity.searchKeywords,
      createdAt: Timestamp.fromDate(entity.createdAt),
      updatedAt: Timestamp.fromDate(entity.updatedAt),
      publishedAt: entity.publishedAt != null
          ? Timestamp.fromDate(entity.publishedAt!)
          : null,
      viewCount: entity.viewCount,
      orderCount: entity.orderCount,
      avgRating: entity.avgRating,
      ratingCount: entity.ratingCount,
      itemLocationId: entity.itemLocationId,
      itemLocationSnapshot: entity.itemLocationSnapshot != null
          ? AddressModel.fromEntity(entity.itemLocationSnapshot!)
          : null,
    );
  }

  static OfferCondition _stringToCondition(String value) {
    switch (value.toLowerCase()) {
      case 'new':
      case 'nuevo':
        return OfferCondition.newProduct;
      case 'excellent':
      case 'excelente':
        return OfferCondition.excellent;
      case 'good':
      case 'good_condition':
      case 'buen':
        return OfferCondition.good;
      case 'used':
        return OfferCondition.used;
      default:
        return OfferCondition.newProduct;
    }
  }

  static String _conditionToString(OfferCondition condition) {
    switch (condition) {
      case OfferCondition.newProduct:
        return 'new';
      case OfferCondition.excellent:
        return 'excellent';
      case OfferCondition.good:
        return 'good';
      case OfferCondition.used:
        return 'used';
    }
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

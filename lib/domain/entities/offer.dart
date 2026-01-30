import 'offer_status.dart';
import 'offer_condition.dart';
import 'address.dart';
import 'pickup_schedule.dart';
import 'concierge_info.dart';

class Offer {
  final String offerId;
  final String heroId;
  final String title;
  final String description;
  final String category;
  final OfferCondition condition;
  final bool? isInGoodState;
  final bool? worksCorrectly;
  final double price;
  final String currency;
  final int stock;
  final int availableQty;
  final double weight; 
  final String coverImageUrl;
  final List<String> imageUrls;
  final OfferStatus status;
  final List<String> searchKeywords;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final int viewCount;
  final int orderCount;
  final double avgRating;
  final int ratingCount;

  /// Location from which the item will be picked up/shipped.
  /// Optional id to a stored location (e.g., user address), plus a snapshot for history.
  final String? itemLocationId;
  final Address? itemLocationSnapshot;

  /// Pickup schedule configuration
  final PickupSchedule? pickupSchedule;
  final bool useConcierge;
  final ConciergeInfo? conciergeInfo;

  Offer({
    required this.offerId,
    required this.heroId,
    required this.title,
    required this.description,
    required this.category,
    required this.condition,
    this.isInGoodState,
    this.worksCorrectly,
    required this.price,
    required this.currency,
    required this.stock,
    required this.availableQty,
    this.weight = 0.5,
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
    this.pickupSchedule,
    this.useConcierge = false,
    this.conciergeInfo,
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
    OfferCondition? condition,
    bool? isInGoodState,
    bool? worksCorrectly,
    double? price,
    String? currency,
    int? stock,
    int? availableQty,
    double? weight,
    String? coverImageUrl,
    List<String>? imageUrls,
    OfferStatus? status,
    List<String>? searchKeywords,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? publishedAt,
    int? viewCount,
    int? orderCount,
    double? avgRating,
    int? ratingCount,
    String? itemLocationId,
    Address? itemLocationSnapshot,
    PickupSchedule? pickupSchedule,
    bool? useConcierge,
    ConciergeInfo? conciergeInfo,
  }) {
    return Offer(
      offerId: offerId ?? this.offerId,
      heroId: heroId ?? this.heroId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      condition: condition ?? this.condition,
      isInGoodState: isInGoodState ?? this.isInGoodState,
      worksCorrectly: worksCorrectly ?? this.worksCorrectly,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      stock: stock ?? this.stock,
      availableQty: availableQty ?? this.availableQty,
      weight: weight ?? this.weight,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      viewCount: viewCount ?? this.viewCount,
      orderCount: orderCount ?? this.orderCount,
      avgRating: avgRating ?? this.avgRating,
      ratingCount: ratingCount ?? this.ratingCount,
      itemLocationId: itemLocationId ?? this.itemLocationId,
      itemLocationSnapshot: itemLocationSnapshot ?? this.itemLocationSnapshot,
      pickupSchedule: pickupSchedule ?? this.pickupSchedule,
      useConcierge: useConcierge ?? this.useConcierge,
      conciergeInfo: conciergeInfo ?? this.conciergeInfo,
    );
  }
}

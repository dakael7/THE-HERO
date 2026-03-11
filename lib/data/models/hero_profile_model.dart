import '../../domain/entities/hero_profile.dart';

class HeroProfileModel {
  final bool isActive;
  final int completedOrders;
  final double rating;
  final int totalRatings;
  final double totalSpent;

  HeroProfileModel({
    this.isActive = true,
    this.completedOrders = 0,
    this.rating = 0.0,
    this.totalRatings = 0,
    this.totalSpent = 0.0,
  });

  factory HeroProfileModel.fromJson(Map<String, dynamic> json) {
    return HeroProfileModel(
      isActive: json['isActive'] as bool? ?? true,
      completedOrders: (json['completedOrders'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalRatings: (json['totalRatings'] as num?)?.toInt() ?? 0,
      totalSpent: (json['totalSpent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isActive': isActive,
      'completedOrders': completedOrders,
      'rating': rating,
      'totalRatings': totalRatings,
      'totalSpent': totalSpent,
    };
  }

  HeroProfile toEntity() {
    return HeroProfile(
      isActive: isActive,
      completedOrders: completedOrders,
      rating: rating,
      totalRatings: totalRatings,
      totalSpent: totalSpent,
    );
  }

  factory HeroProfileModel.fromEntity(HeroProfile entity) {
    return HeroProfileModel(
      isActive: entity.isActive,
      completedOrders: entity.completedOrders,
      rating: entity.rating,
      totalRatings: entity.totalRatings,
      totalSpent: entity.totalSpent,
    );
  }
}

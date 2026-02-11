import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/favorite.dart';

class FavoriteModel {
  final String userId;
  final String offerId;
  final Timestamp createdAt;

  const FavoriteModel({
    required this.userId,
    required this.offerId,
    required this.createdAt,
  });

  factory FavoriteModel.fromJson(Map<String, dynamic> json) {
    return FavoriteModel(
      userId: json['userId'] as String,
      offerId: json['offerId'] as String,
      createdAt: json['createdAt'] as Timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {'userId': userId, 'offerId': offerId, 'createdAt': createdAt};
  }

  Favorite toEntity() {
    return Favorite(
      userId: userId,
      offerId: offerId,
      createdAt: createdAt.toDate(),
    );
  }

  factory FavoriteModel.fromEntity(Favorite favorite) {
    return FavoriteModel(
      userId: favorite.userId,
      offerId: favorite.offerId,
      createdAt: Timestamp.fromDate(favorite.createdAt),
    );
  }
}

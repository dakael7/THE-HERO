import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/offer_comment.dart';

class OfferCommentModel {
  final String commentId;
  final String offerId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String text;
  final String? reply;
  final String? replyBy;
  final Timestamp? repliedAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  OfferCommentModel({
    required this.commentId,
    required this.offerId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.text,
    this.reply,
    this.replyBy,
    this.repliedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  // From Firestore JSON
  factory OfferCommentModel.fromJson(Map<String, dynamic> json) {
    return OfferCommentModel(
      commentId: json['commentId'] as String? ?? '',
      offerId: json['offerId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      userAvatarUrl: json['userAvatarUrl'] as String?,
      text: json['text'] as String? ?? '',
      reply: json['reply'] as String?,
      replyBy: json['replyBy'] as String?,
      repliedAt: json['repliedAt'] as Timestamp?,
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  // To Firestore JSON
  Map<String, dynamic> toJson() {
    return {
      'commentId': commentId,
      'offerId': offerId,
      'userId': userId,
      'userName': userName,
      'userAvatarUrl': userAvatarUrl,
      'text': text,
      'reply': reply,
      'replyBy': replyBy,
      'repliedAt': repliedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  // To Entity
  OfferComment toEntity() {
    return OfferComment(
      commentId: commentId,
      offerId: offerId,
      userId: userId,
      userName: userName,
      userAvatarUrl: userAvatarUrl,
      text: text,
      reply: reply,
      replyBy: replyBy,
      repliedAt: repliedAt?.toDate(),
      createdAt: createdAt.toDate(),
      updatedAt: updatedAt.toDate(),
    );
  }

  // From Entity
  factory OfferCommentModel.fromEntity(OfferComment entity) {
    return OfferCommentModel(
      commentId: entity.commentId,
      offerId: entity.offerId,
      userId: entity.userId,
      userName: entity.userName,
      userAvatarUrl: entity.userAvatarUrl,
      text: entity.text,
      reply: entity.reply,
      replyBy: entity.replyBy,
      repliedAt: entity.repliedAt != null
          ? Timestamp.fromDate(entity.repliedAt!)
          : null,
      createdAt: Timestamp.fromDate(entity.createdAt),
      updatedAt: Timestamp.fromDate(entity.updatedAt),
    );
  }
}

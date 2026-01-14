class OfferComment {
  final String commentId;
  final String offerId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String text;
  final String? reply;
  final String? replyBy;
  final DateTime? repliedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  OfferComment({
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

  OfferComment copyWith({
    String? commentId,
    String? offerId,
    String? userId,
    String? userName,
    String? userAvatarUrl,
    String? text,
    String? reply,
    String? replyBy,
    DateTime? repliedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OfferComment(
      commentId: commentId ?? this.commentId,
      offerId: offerId ?? this.offerId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      text: text ?? this.text,
      reply: reply ?? this.reply,
      replyBy: replyBy ?? this.replyBy,
      repliedAt: repliedAt ?? this.repliedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class Favorite {
  final String userId;
  final String offerId;
  final DateTime createdAt;

  const Favorite({
    required this.userId,
    required this.offerId,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Favorite &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          offerId == other.offerId;

  @override
  int get hashCode => userId.hashCode ^ offerId.hashCode;
}

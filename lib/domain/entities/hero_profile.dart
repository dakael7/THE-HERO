/// Entidad que representa el perfil de un Hero (comprador)
class HeroProfile {
  final bool isActive;
  final int completedOrders;
  final double rating;
  final double totalSpent;

  HeroProfile({
    this.isActive = true,
    this.completedOrders = 0,
    this.rating = 0.0,
    this.totalSpent = 0.0,
  });

  HeroProfile copyWith({
    bool? isActive,
    int? completedOrders,
    double? rating,
    double? totalSpent,
  }) {
    return HeroProfile(
      isActive: isActive ?? this.isActive,
      completedOrders: completedOrders ?? this.completedOrders,
      rating: rating ?? this.rating,
      totalSpent: totalSpent ?? this.totalSpent,
    );
  }
}

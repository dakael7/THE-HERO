enum OfferCondition {
  newProduct,
  excellent,
  good,
  used;

  String get displayName {
    switch (this) {
      case OfferCondition.newProduct:
        return 'Nuevo';
      case OfferCondition.excellent:
        return 'Excelente estado';
      case OfferCondition.good:
        return 'Buen estado';
      case OfferCondition.used:
        return 'Usado';
    }
  }
}

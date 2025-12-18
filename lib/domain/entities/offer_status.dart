enum OfferStatus {
  draft,
  active,
  paused,
  soldOut,
  archived;

  String get displayName {
    switch (this) {
      case OfferStatus.draft:
        return 'Borrador';
      case OfferStatus.active:
        return 'Activo';
      case OfferStatus.paused:
        return 'Pausado';
      case OfferStatus.soldOut:
        return 'Agotado';
      case OfferStatus.archived:
        return 'Archivado';
    }
  }

  bool get isPublished => this == OfferStatus.active;
  bool get isVisible => this == OfferStatus.active;
  bool get canBeEdited => this != OfferStatus.archived;
}

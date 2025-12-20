enum ChatType {
  heroRider,
  heroSeller;

  static ChatType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'hero_rider':
      case 'hero-rider':
      case 'herorider':
      case 'buyer_rider':
      case 'buyer-rider':
      case 'buyerrider':
        return ChatType.heroRider;
      case 'hero_seller':
      case 'hero-seller':
      case 'heroseller':
      case 'buyer_seller':
      case 'buyer-seller':
      case 'buyerseller':
        return ChatType.heroSeller;
      default:
        throw ArgumentError('Tipo de chat inválido: $value');
    }
  }

  String get jsonValue {
    switch (this) {
      case ChatType.heroRider:
        return 'hero_rider';
      case ChatType.heroSeller:
        return 'hero_seller';
    }
  }
}

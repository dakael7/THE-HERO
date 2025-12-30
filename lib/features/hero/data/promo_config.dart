/// Configuración de banners promocionales
/// Para agregar/cambiar imágenes, simplemente edita la lista [promoItems]
class PromoConfig {
  static const List<PromoItem> promoItems = [
    PromoItem(
      imagePath: 'assets/promo1.png',
      title: 'Ofertas Especiales',
      subtitle: 'Descubre las mejores ofertas',
      onTapRoute: null, // null = no navega
    ),
    PromoItem(
      imagePath: 'assets/promo2.png',
      title: 'Nuevos Productos',
      subtitle: 'Explora lo más reciente',
      onTapRoute: null,
    ),
    PromoItem(
      imagePath: 'assets/promo3.png',
      title: 'Envío Gratis',
      subtitle: 'En compras mayores a 50',
      onTapRoute: null,
    ),
  ];

  /// Duración del auto-scroll del carrusel (en segundos)
  static const int autoScrollDuration = 5;
}

class PromoItem {
  final String imagePath;
  final String? title;
  final String? subtitle;
  final String? onTapRoute;

  const PromoItem({
    required this.imagePath,
    this.title,
    this.subtitle,
    this.onTapRoute,
  });
}

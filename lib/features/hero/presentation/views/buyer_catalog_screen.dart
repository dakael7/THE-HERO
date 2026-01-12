import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/offer.dart';
import '../../../../domain/entities/offer_condition.dart';
import '../../../../domain/entities/user.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../cart/cart_provider.dart';
import '../../../offers/presentation/providers/offers_provider.dart';
import '../widgets/product_card.dart';

class BuyerCatalogScreen extends ConsumerWidget {
  const BuyerCatalogScreen({super.key});

  Color _conditionColor(OfferCondition condition) {
    switch (condition) {
      case OfferCondition.newProduct:
        return const Color(0xFF0EA5E9);
      case OfferCondition.excellent:
        return const Color(0xFF10B981);
      case OfferCondition.good:
        return const Color(0xFFF59E0B);
      case OfferCondition.used:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerAsync = ref.watch(profileProvider);
    final offersAsync = ref.watch(
      activeOffersProvider(OffersFilter(limit: 40)),
    );

    return Scaffold(
      backgroundColor: backgroundWhite,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Catálogo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: offersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (error, _) => _ErrorState(
          message: 'No se pudo cargar el catálogo',
          onRetry: () => ref.invalidate(
            activeOffersProvider(OffersFilter(limit: 40)),
          ),
        ),
        data: (offers) {
          if (offers.isEmpty) {
            return const _EmptyState();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderGray100),
                  boxShadow: [
                    BoxShadow(
                      color: textGray900.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ...offers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final offer = entry.value;
                      final isLast = index == offers.length - 1;
                      return Column(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OfferDetailScreen(offer: offer),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              child: ProductCard(
                                name: offer.title,
                                condition: offer.condition.displayName,
                                colorCondition: _conditionColor(offer.condition),
                                price: offer.price,
                                weight: 0.5,
                                showShadow: false,
                                sellerName: _sellerNameFor(offer, sellerAsync),
                              ),
                            ),
                          ),
                          if (!isLast)
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: borderGray100,
                              indent: 16,
                              endIndent: 16,
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _sellerNameFor(Offer offer, AsyncValue<User?> sellerAsync) {
    return sellerAsync.maybeWhen(
      data: (user) {
        if (user != null && user.id == offer.heroId) {
          return user.fullName;
        }
        return 'Vendedor';
      },
      orElse: () => 'Vendedor',
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: borderGray100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textGray700),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textGray700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.search_off, size: 56, color: textGray600),
            SizedBox(height: 12),
            Text(
              'No hay productos activos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Cuando se publiquen ofertas activas aparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: textGray700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 56, color: primaryOrange),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: backgroundWhite,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Reintentar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfferDetailScreen extends ConsumerWidget {
  const OfferDetailScreen({super.key, required this.offer});

  final Offer offer;

  Color _conditionColor(OfferCondition condition) {
    switch (condition) {
      case OfferCondition.newProduct:
        return const Color(0xFF0EA5E9);
      case OfferCondition.excellent:
        return const Color(0xFF10B981);
      case OfferCondition.good:
        return const Color(0xFFF59E0B);
      case OfferCondition.used:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeColor = _conditionColor(offer.condition);
    final priceText = '\$${offer.price.toStringAsFixed(0)} CLP';
    final isAsset = offer.coverImageUrl.startsWith('assets/');
    final galleryImages = <String>{
      if (offer.coverImageUrl.isNotEmpty) offer.coverImageUrl,
      ...offer.imageUrls,
    }.toList();
    final soldCount = offer.orderCount;
    final viewsCount = offer.viewCount;
    const weight = 0.5;
    final sellerAsync = ref.watch(profileProvider);

    String sellerName = 'Vendedor';
    sellerAsync.whenData((user) {
      if (user != null && user.id == offer.heroId) {
        sellerName = user.fullName;
      }
    });

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Detalle del producto',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: borderGray100,
              height: 220,
              child: isAsset
                  ? Image.asset(
                      offer.coverImageUrl,
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      offer.coverImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Image.asset(
                          'assets/logo_hero.png',
                          fit: BoxFit.contain,
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (galleryImages.length > 1) ...[
            const Text(
              'Imágenes',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: galleryImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final imageUrl = galleryImages[index];
                  final isAssetThumb = imageUrl.startsWith('assets/');
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 140,
                      color: borderGray100,
                      child: isAssetThumb
                          ? Image.asset(
                              imageUrl,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Image.asset(
                                  'assets/logo_hero.png',
                                  fit: BoxFit.contain,
                                );
                              },
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: badgeColor.withOpacity(0.25)),
                ),
                child: Text(
                  offer.condition.displayName,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 18,
                color: textGray600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Publicado por: $sellerName',
                  style: const TextStyle(
                    fontSize: 13,
                    color: textGray600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            priceText,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.star,
                size: 18,
                color: Color(0xFFFFB800),
              ),
              const SizedBox(width: 6),
              const Text(
                '4.8',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '(${soldCount > 0 ? '$soldCount vendidos' : 'Sin ventas aún'})',
                style: const TextStyle(
                  fontSize: 13,
                  color: textGray600,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.remove_red_eye_outlined,
                size: 16,
                color: textGray600,
              ),
              const SizedBox(width: 4),
              Text(
                '${viewsCount > 0 ? viewsCount : 0} vistas',
                style: const TextStyle(
                  fontSize: 13,
                  color: textGray600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Pill(icon: Icons.category_outlined, label: offer.category),
              _Pill(
                icon: Icons.visibility_outlined,
                label: 'Estado: ${offer.status.displayName}',
              ),
              _Pill(
                icon: Icons.inventory_2_outlined,
                label: offer.stock > 0
                    ? 'Stock: ${offer.availableQty}/${offer.stock}'
                    : 'Sin stock',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Descripción',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            offer.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: textGray700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: const [
              Icon(
                Icons.local_shipping_outlined,
                size: 18,
                color: textGray600,
              ),
              SizedBox(width: 6),
              Text(
                'Peso estimado: 0.5 kg',
                style: TextStyle(
                  fontSize: 13,
                  color: textGray600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                ref.read(cartProvider.notifier).addItem(
                      name: offer.title,
                      condition: offer.condition.displayName,
                      price: offer.price,
                      weight: weight,
                    );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Agregar al carrito',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: backgroundWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

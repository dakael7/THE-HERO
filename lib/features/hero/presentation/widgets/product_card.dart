import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/providers/favorites_providers.dart';
import '../../../offers/presentation/widgets/star_rating_widget.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../cart/cart_provider.dart';

class ProductCard extends ConsumerWidget {
  final String offerId;
  final String name;
  final String? sellerHeroId;
  final String condition;
  final Color colorCondition;
  final String category;
  final int availableQty;
  final int viewCount;
  final int orderCount;
  final double weight;
  final firestore.GeoPoint? pickupGeo;
  final String? pickupAddressSnapshot;
  final String? pickupCountryCode;
  final bool allowInPersonPickup;
  final bool showShadow;
  final String? sellerName;
  final String? imageUrl;
  final double avgRating;
  final int ratingCount;

  const ProductCard({
    super.key,
    required this.offerId,
    required this.name,
    this.sellerHeroId,
    required this.condition,
    required this.colorCondition,
    required this.category,
    required this.availableQty,
    required this.viewCount,
    required this.orderCount,
    this.weight = 0.5,
    this.pickupGeo,
    this.pickupAddressSnapshot,
    this.pickupCountryCode,
    this.allowInPersonPickup = false,
    this.showShadow = true,
    this.sellerName,
    this.imageUrl,
    this.avgRating = 0.0,
    this.ratingCount = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final userId = ref.watch(profileProvider).maybeWhen(
                data: (user) => user?.id,
                orElse: () => null,
              );

          final maxWidth = constraints.maxWidth;
          final dpr = MediaQuery.of(context).devicePixelRatio;

          // Imagen cuadrada: ocupa ~42% del ancho de la card
          final imageSize = (maxWidth * 0.42).clamp(130.0, 200.0);
          final targetCacheSize = (imageSize * dpr).round();

          return Container(
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.zero,
              boxShadow: showShadow
                  ? [
                      BoxShadow(
                        color: textGray900.withValues(alpha: 0.07),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                        spreadRadius: 0,
                      ),
                    ]
                  : const [],
            ),
            clipBehavior: Clip.none,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Imagen grande a la izquierda ──────────────────────────
                  Stack(
                    children: [
                      SizedBox(
                        width: imageSize,
                        child: _ProductImage(
                          imageUrl: imageUrl,
                          targetCacheSize: targetCacheSize,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _FavoriteButton(
                          offerId: offerId,
                          userId: userId,
                          ref: ref,
                        ),
                      ),
                    ],
                  ),

                  // ── Contenido derecho ─────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textGray900,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.store_mall_directory_outlined,
                                size: 12,
                                color: textGray600,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  sellerName != null &&
                                          sellerName!.trim().isNotEmpty
                                      ? sellerName!
                                      : 'Vendedor',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: textGray600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _Chip(label: category),
                              _Chip(label: 'x$availableQty disponibles'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (ratingCount > 0) ...[
                            Row(
                              children: [
                                StarRatingWidget(
                                  rating: avgRating,
                                  size: 12.0,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '($ratingCount)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: textGray600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Row(
                            children: [
                              _StatItem(
                                icon: Icons.remove_red_eye_outlined,
                                value: '$viewCount',
                              ),
                              const SizedBox(width: 10),
                              _StatItem(
                                icon: Icons.volunteer_activism_outlined,
                                value: '$orderCount',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: GestureDetector(
                              onTap: () =>
                                  _handleAddToCart(context, ref, userId),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryOrange,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryOrange.withValues(
                                        alpha: 0.28,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_shopping_cart_rounded,
                                      color: backgroundWhite,
                                      size: 15,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Agregar al carrito',
                                      style: TextStyle(
                                        color: backgroundWhite,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ), // Row
            ), // IntrinsicHeight
          );
        },
      ),
    );
  }

  void _handleAddToCart(
    BuildContext context,
    WidgetRef ref,
    String? userId,
  ) {
    final sellerId = sellerHeroId?.trim();
    if (userId != null &&
        sellerId != null &&
        sellerId.isNotEmpty &&
        sellerId == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No puedes agregar al carrito tus propias donaciones. Puedes gestionarlas desde "Mis donaciones".',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final pickupCc = pickupCountryCode?.trim();
    if (pickupCc == null || pickupCc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este producto no tiene país de retiro configurado. El checkout se bloqueará hasta que el vendedor actualice la ubicación de la publicación.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }

    ref.read(cartProvider.notifier).addItem(
          offerId: offerId,
          name: name,
          condition: condition,
          price: 0.0,
          weight: weight,
          imageUrl: imageUrl ?? '',
          availableQty: availableQty,
          pickupGeo: pickupGeo,
          pickupAddressSnapshot: pickupAddressSnapshot,
          pickupCountryCode: pickupCountryCode,
          sellerHeroId: sellerHeroId,
          allowInPersonPickup: allowInPersonPickup,
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets privados
// ─────────────────────────────────────────────────────────────────────────────

class _ProductImage extends StatelessWidget {
  final String? imageUrl;
  final int targetCacheSize;

  const _ProductImage({
    required this.imageUrl,
    required this.targetCacheSize,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = imageUrl?.trim() ?? '';

    Widget child;
    if (resolved.isEmpty) {
      child = const Center(
        child: Icon(Icons.image, color: textGray600, size: 44),
      );
    } else if (resolved.startsWith('assets/')) {
      child = Image.asset(resolved, fit: BoxFit.cover);
    } else {
      child = Image.network(
        resolved,
        fit: BoxFit.cover,
        cacheWidth: targetCacheSize,
        cacheHeight: targetCacheSize,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: textGray600,
            size: 44,
          ),
        ),
      );
    }

    return Container(
      color: borderGray100,
      child: child,
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  final String offerId;
  final String? userId;
  final WidgetRef ref;

  const _FavoriteButton({
    required this.offerId,
    required this.userId,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteIdsAsync = userId == null
        ? const AsyncValue<List<String>>.data(<String>[])
        : ref.watch(favoriteOfferIdsProvider(userId!));

    final isFavorite = favoriteIdsAsync.maybeWhen(
      data: (ids) => ids.contains(offerId),
      orElse: () => false,
    );

    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: userId == null
            ? null
            : () async {
                try {
                  await ref
                      .read(favoritesNotifierProvider.notifier)
                      .toggleFavorite(userId!, offerId);
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No se pudo actualizar favoritos'),
                    ),
                  );
                }
              },
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? const Color(0xFFDC2626) : textGray600,
            size: 17,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: borderGray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textGray900,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatItem({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: textGray600),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textGray600,
          ),
        ),
      ],
    );
  }
}
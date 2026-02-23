import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../domain/providers/favorites_providers.dart';
import '../../../offers/presentation/widgets/star_rating_widget.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../cart/cart_provider.dart';

const double paddingNormal = 16.0;

class ProductCard extends ConsumerWidget {
  final String offerId;
  final String name;
  final String condition;
  final Color colorCondition;
  final String category;
  final int availableQty;
  final int viewCount;
  final int orderCount;
  final double weight;
  final firestore.GeoPoint? pickupGeo;
  final bool showShadow;
  final String? sellerName;
  final String? imageUrl;
  final double avgRating;
  final int ratingCount;

  const ProductCard({
    super.key,
    required this.offerId,
    required this.name,
    required this.condition,
    required this.colorCondition,
    required this.category,
    required this.availableQty,
    required this.viewCount,
    required this.orderCount,
    this.weight = 0.5,
    this.pickupGeo,
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
          final isMobile = ResponsiveUtils.isMobile(context);
          final maxWidth = constraints.maxWidth;
          final rawImageSize = isMobile ? maxWidth * 0.34 : maxWidth * 0.26;
          final imageSize = rawImageSize.clamp(120.0, 220.0);
          final padding = ResponsiveUtils.responsivePadding(
            context,
            mobilePadding: paddingNormal - 2,
            tabletPadding: 18.0,
            desktopPadding: 22.0,
          );
          final nameFontSize = ResponsiveUtils.responsiveFontSize(
            context,
            mobileSize: 16,
            tabletSize: 17,
            desktopSize: 18,
          );
          final conditionFontSize = ResponsiveUtils.responsiveFontSize(
            context,
            mobileSize: 10,
            tabletSize: 11,
            desktopSize: 12,
          );
          final conditionPadding = ResponsiveUtils.responsivePadding(
            context,
            mobilePadding: 8.0,
            tabletPadding: 9.0,
            desktopPadding: 10.0,
          );

          return Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(16),
              boxShadow: showShadow
                  ? [
                      BoxShadow(
                        color: textGray900.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: primaryOrange.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      width: imageSize,
                      height: imageSize,
                      decoration: BoxDecoration(
                        color: borderGray100,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: textGray900.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Builder(
                        builder: (context) {
                          final resolved = imageUrl?.trim() ?? '';

                          if (resolved.isEmpty) {
                            return const Center(
                              child: Icon(
                                Icons.image,
                                color: textGray600,
                                size: 40,
                              ),
                            );
                          }

                          final isAsset = resolved.startsWith('assets/');

                          Widget imageWidget;
                          if (isAsset) {
                            imageWidget = Image.asset(
                              resolved,
                              fit: BoxFit.cover,
                            );
                          } else {
                            imageWidget = Image.network(
                              resolved,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return const Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: textGray600,
                                    size: 42,
                                  ),
                                );
                              },
                            );
                          }

                          return AspectRatio(
                            aspectRatio: 1,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: imageSize,
                                height: imageSize,
                                child: imageWidget,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Consumer(
                        builder: (context, ref, _) {
                          final userAsync = ref.watch(profileProvider);
                          final userId = userAsync.maybeWhen(
                            data: (user) => user?.id,
                            orElse: () => null,
                          );

                          final favoriteIdsAsync = userId == null
                              ? const AsyncValue<List<String>>.data(<String>[])
                              : ref.watch(
                                  favoriteOfferIdsProvider(userId),
                                );

                          final isFavorite = favoriteIdsAsync.maybeWhen(
                            data: (ids) => ids.contains(offerId),
                            orElse: () => false,
                          );

                          return Material(
                            color: Colors.white.withValues(alpha: 0.95),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: userId == null
                                  ? null
                                  : () async {
                                      try {
                                        await ref
                                            .read(
                                              favoritesNotifierProvider
                                                  .notifier,
                                            )
                                            .toggleFavorite(userId, offerId);
                                      } catch (_) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No se pudo actualizar favoritos',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Icon(
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFavorite
                                      ? const Color(0xFFDC2626)
                                      : textGray600,
                                  size: 18,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(width: padding),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: nameFontSize,
                          fontWeight: FontWeight.w700,
                          color: textGray900,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: padding * 0.4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 14,
                            color: textGray600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              sellerName != null && sellerName!.trim().isNotEmpty
                                  ? 'Publicado por: ${sellerName!}'
                                  : 'Publicado por: vendedor',
                              style: const TextStyle(
                                fontSize: 12,
                                color: textGray600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: padding * 0.5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: borderGray100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: borderGray100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Disponibles: $availableQty',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (ratingCount > 0) ...[
                        SizedBox(height: padding * 0.3),
                        Row(
                          children: [
                            StarRatingWidget(rating: avgRating, size: 14.0),
                            const SizedBox(width: 4),
                            Text(
                              '($ratingCount)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: textGray600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: padding * 0.6),
                      Row(
                        children: [
                          Icon(
                            Icons.remove_red_eye_outlined,
                            size: 16,
                            color: textGray600.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$viewCount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: textGray600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.volunteer_activism_outlined,
                            size: 16,
                            color: textGray600.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$orderCount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: textGray600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: padding * 0.6),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: conditionPadding,
                              vertical: conditionPadding * 0.5,
                            ),
                            decoration: BoxDecoration(
                              color: colorCondition.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              condition,
                              style: TextStyle(
                                fontSize: conditionFontSize,
                                fontWeight: FontWeight.w700,
                                color: colorCondition,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: padding * 0.6),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: () {
                            ref
                                .read(cartProvider.notifier)
                                .addItem(
                                  offerId: offerId,
                                  name: name,
                                  condition: condition,
                                  price: 0.0,
                                  weight: weight,
                                  imageUrl: imageUrl ?? '',
                                  pickupGeo: pickupGeo,
                                );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: padding * 0.9,
                              vertical: padding * 0.6,
                            ),
                            decoration: BoxDecoration(
                              color: primaryOrange,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryOrange.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Agregar al carrito',
                              style: TextStyle(
                                color: backgroundWhite,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

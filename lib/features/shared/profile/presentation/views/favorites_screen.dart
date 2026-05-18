import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/providers/favorites_providers.dart';
import '../../../../offers/presentation/providers/offers_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../../../../hero/presentation/widgets/product_card.dart';
import '../../../../../domain/entities/offer_condition.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Favoritos',
        icon: Icons.favorite_border,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
        },
      ),
      body: userId == null
          ? const Center(child: Text('Usuario no encontrado'))
          : Builder(
              builder: (context) {
                final uid = userId!;
                final favoriteIdsAsync = ref.watch(
                  favoriteOfferIdsProvider(uid),
                );

                return favoriteIdsAsync.when(
                  data: (favoriteIds) {
                    if (favoriteIds.isEmpty) {
                      return _buildEmptyState();
                    }

                    // Get all active offers
                    final allOffersAsync = ref.watch(
                      activeOffersProvider(OffersFilter(limit: 100)),
                    );

                    return allOffersAsync.when(
                      data: (allOffers) {
                        // Filter to only show favorite offers
                        final favoriteOffers = allOffers
                            .where((offer) => favoriteIds.contains(offer.offerId))
                            .where((offer) => offer.heroId != uid)
                            .toList();

                        if (favoriteOffers.isEmpty) {
                          return _buildEmptyState();
                        }

                        return RefreshIndicator(
                          color: primaryOrange,
                          onRefresh: () async {
                            ref.invalidate(favoriteOfferIdsProvider);
                            ref.invalidate(activeOffersProvider);
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: favoriteOffers.length,
                            itemBuilder: (context, index) {
                              final offer = favoriteOffers[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ProductCard(
                                  offerId: offer.offerId,
                                  name: offer.title,
                                  sellerHeroId: offer.heroId,
                                  moderationStatus: offer.moderationStatus,
                                  condition: offer.condition.name,
                                  colorCondition:
                                      offer.condition == OfferCondition.newProduct
                                      ? Colors.green
                                      : offer.condition ==
                                            OfferCondition.excellent
                                      ? Colors.blue
                                      : Colors.orange,
                                  category: offer.category,
                                  availableQty: offer.availableQty,
                                  viewCount: offer.viewCount,
                                  orderCount: offer.orderCount,
                                  weight: offer.weight,
                                  pickupGeo: offer.itemLocationSnapshot?.geopoint,
                                  pickupAddressSnapshot:
                                      offer.itemLocationSnapshot?.fullAddress,
                                  pickupCountryCode:
                                      offer.itemLocationSnapshot?.countryCode,
                                  allowInPersonPickup: offer.allowInPersonPickup,
                                  imageUrl: offer.displayImageUrl,
                                  avgRating: offer.avgRating,
                                  ratingCount: offer.ratingCount,
                                  sellerHeroRating: ref
                                      .watch(userByIdStreamProvider(offer.heroId))
                                      .maybeWhen(
                                        data: (u) =>
                                            (u?.heroProfile?.rating) ?? 0.0,
                                        orElse: () => null,
                                      ),
                                  sellerHeroRatingCount: ref
                                      .watch(userByIdStreamProvider(offer.heroId))
                                      .maybeWhen(
                                        data: (u) =>
                                            (u?.heroProfile?.totalRatings) ?? 0,
                                        orElse: () => null,
                                      ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: primaryOrange),
                      ),
                      error: (error, stack) =>
                          Center(child: Text('Error: $error')),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: primaryOrange),
                  ),
                  error: (error, stack) => Center(child: Text('Error: $error')),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.favorite_border,
                size: 34,
                color: primaryOrange,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Aún no tienes favoritos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Marca productos como favoritos para encontrarlos rápido.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textGray600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

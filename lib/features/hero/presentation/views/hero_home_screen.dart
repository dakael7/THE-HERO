import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/hero_header.dart';
import '../widgets/hero_bottom_nav.dart';
import '../widgets/hero_fab.dart';
import '../widgets/hero_admob_native.dart';
import '../viewmodels/hero_home_viewmodel.dart';
import 'buyer_catalog_screen.dart';
import '../../../shared/profile/presentation/views/profile_screen.dart'
    as profile;
import '../../../shared/profile/presentation/views/my_products_screen.dart';
import '../../../shared/profile/presentation/views/donation_questions_screen.dart';
import '../../../shared/notifications/presentation/views/notifications_screen.dart';
import '../../../map/presentation/views/map_location_screen.dart';
import '../providers/catalog_filters_provider.dart';
import '../widgets/catalog_filter_widgets.dart';
import '../widgets/product_card.dart';
import '../../../../domain/entities/offer_condition.dart';
import '../../../../domain/entities/user.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;
const double spacingSmall = paddingNormal / 2;
const double spacingSection = paddingNormal / 4;
const double spacingButtonV = paddingNormal * 0.75;
const double spacingButtonH = paddingNormal * 1.25;
const double spacingScreenBottom = paddingLarge * 4;

class HeroHomeScreen extends ConsumerStatefulWidget {
  const HeroHomeScreen({super.key});

  @override
  ConsumerState<HeroHomeScreen> createState() => _HeroHomeScreenState();
}

class _HeroHomeScreenState extends ConsumerState<HeroHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(heroHomeViewModelProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchExpandedChanged(bool expanded) {
    setState(() {
      _isSearchExpanded = expanded;
    });

    if (expanded) {
      _scrollController.animateTo(
        80.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: backgroundGray50,
        resizeToAvoidBottomInset: false,
        body: Consumer(
          builder: (context, ref, _) {
            final selectedIndex = ref.watch(
              heroHomeViewModelProvider.select(
                (state) => state.selectedNavIndex,
              ),
            );

            if (selectedIndex == 4) {
              return WillPopScope(
                onWillPop: () async {
                  ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
                  return false;
                },
                child: profile.ProfileScreen(
                  isRiderProfile: false,
                  onBackPressed: () {
                    ref
                        .read(heroHomeViewModelProvider.notifier)
                        .selectNavItem(0);
                  },
                ),
              );
            }

            if (selectedIndex == 3) {
              return const NotificationsScreen();
            }

            if (selectedIndex == 1) {
              return const MapLocationScreen();
            }

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                HeroHeader(onSearchExpandedChanged: _onSearchExpandedChanged),
                if (_isSearchExpanded)
                  const SliverFillRemaining(child: HeroSearchContent())
                else
                  SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: paddingNormal),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: paddingNormal,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const HeroAdMobNative(height: 160),
                            const SizedBox(height: paddingNormal),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: paddingNormal,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final scale =
                                (width / 390.0).clamp(0.88, 1.10).toDouble();
                            final cardPadding =
                                (14.0 * scale).clamp(12.0, 16.0).toDouble();
                            final titleSize =
                                (15.0 * scale).clamp(13.0, 16.0).toDouble();
                            final bodySize =
                                (12.5 * scale).clamp(11.0, 13.0).toDouble();
                            final buttonVPadding =
                                (11.0 * scale).clamp(10.0, 12.0).toDouble();
                            final iconSize =
                                (18.0 * scale).clamp(16.0, 20.0).toDouble();
                            final cornerRadius =
                                (16.0 * scale).clamp(14.0, 18.0).toDouble();
                            final cardHeight =
                                (174.0 * scale).clamp(160.0, 190.0).toDouble();

                            final publishCard = SizedBox(
                              height: cardHeight,
                              child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(cardPadding),
                                decoration: BoxDecoration(
                                  color: backgroundWhite,
                                  borderRadius:
                                      BorderRadius.circular(cornerRadius),
                                  border: Border.all(
                                    color: borderGray100,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          textGray900.withValues(alpha: 0.05),
                                      blurRadius: 12,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Sé un Hero',
                                      style: TextStyle(
                                        fontSize: titleSize,
                                        fontWeight: FontWeight.w900,
                                        color: textGray900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Dona tus productos',
                                      style: TextStyle(
                                        fontSize: bodySize,
                                        color: textGray700,
                                      ),
                                    ),
                                    const Spacer(),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const DonationQuestionsScreen(),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryOrange,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                            vertical: buttonVPadding,
                                            horizontal: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          elevation: 0,
                                        ),
                                        icon: Icon(
                                          Icons.volunteer_activism,
                                          size: iconSize,
                                        ),
                                        label: const Text(
                                          'Dona tus productos',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            final myDonationsCard = SizedBox(
                              height: cardHeight,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: backgroundWhite,
                                  borderRadius:
                                      BorderRadius.circular(cornerRadius),
                                  border: Border.all(
                                    color: borderGray100,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          textGray900.withValues(alpha: 0.05),
                                      blurRadius: 12,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(cornerRadius),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    borderRadius:
                                        BorderRadius.circular(cornerRadius),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const MyProductsScreen(),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.all(cardPadding),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: EdgeInsets.all(
                                              (10.0 * scale)
                                                  .clamp(7.0, 10.0)
                                                  .toDouble(),
                                            ),
                                            decoration: BoxDecoration(
                                              color: primaryOrange.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Icon(
                                              Icons.inventory_2_outlined,
                                              color: primaryOrange,
                                              size: (24.0 * scale)
                                                  .clamp(20.0, 26.0)
                                                  .toDouble(),
                                            ),
                                          ),
                                          SizedBox(
                                            height: (8.0 * scale)
                                                .clamp(6.0, 8.0)
                                                .toDouble(),
                                          ),
                                          Text(
                                            'Mis Donaciones',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: titleSize,
                                              fontWeight: FontWeight.w800,
                                              color: textGray900,
                                            ),
                                          ),
                                          SizedBox(
                                            height: (6.0 * scale)
                                                .clamp(4.0, 6.0)
                                                .toDouble(),
                                          ),
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.topLeft,
                                              child: Text(
                                                'Publica y edita tus productos',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: bodySize,
                                                  color: textGray700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const Align(
                                            alignment: Alignment.centerRight,
                                            child: Icon(
                                              Icons.chevron_right_rounded,
                                              color: primaryOrange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );

                            return Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: publishCard),
                                    const SizedBox(width: 12),
                                    Expanded(child: myDonationsCard),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const _CatalogSection(),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: spacingScreenBottom),
                    ]),
                  ),
              ],
            );
          },
        ),
        bottomNavigationBar: _isSearchExpanded ? null : const HeroBottomNav(),
        floatingActionButton: _isSearchExpanded ? null : const HeroFAB(),
        floatingActionButtonLocation: const _CenterDockedWithOffset(44.0),
      ),
    );
  }
}

class _CenterDockedWithOffset extends FloatingActionButtonLocation {
  const _CenterDockedWithOffset(this.dy);

  final double dy;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final base = FloatingActionButtonLocation.centerDocked
        .getOffset(scaffoldGeometry);
    return Offset(base.dx, base.dy + dy);
  }
}

/// Catalog section widget integrated in home
class _CatalogSection extends ConsumerWidget {
  const _CatalogSection();

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

  String _sellerNameFor(AsyncValue<User?> sellerAsync) {
    return sellerAsync.maybeWhen(
      data: (user) => user?.fullName ?? 'Vendedor',
      orElse: () => 'Vendedor',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersAsync = ref.watch(filteredOffersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Catálogo de productos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textGray900,
          ),
        ),
        const SizedBox(height: 12),
        const CategoryFilterChips(),
        const SizedBox(height: 12),
        Row(
          children: const [
            SortOptionsButton(),
          ],
        ),
        const ActiveFiltersIndicator(),
        offersAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error al cargar productos: $error',
              style: const TextStyle(color: textGray600),
              textAlign: TextAlign.center,
            ),
          ),
          data: (offers) {
            if (offers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No se encontraron productos',
                    style: TextStyle(color: textGray600),
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${offers.length} producto${offers.length != 1 ? 's' : ''} encontrado${offers.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: textGray600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: backgroundWhite,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderGray100),
                    boxShadow: [
                      BoxShadow(
                        color: textGray900.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: offers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final offer = entry.value;
                      final isLast = index == offers.length - 1;

                      return Column(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OfferDetailScreen(offer: offer),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              child: ProductCard(
                                offerId: offer.offerId,
                                name: offer.title,
                                sellerHeroId: offer.heroId,
                                condition: offer.condition.displayName,
                                colorCondition: _conditionColor(offer.condition),
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
                                showShadow: false,
                                imageUrl: offer.coverImageUrl,
                                avgRating: offer.avgRating,
                                ratingCount: offer.ratingCount,
                                sellerName: _sellerNameFor(
                                  ref.watch(
                                      userByIdStreamProvider(offer.heroId)),
                                ),
                                sellerHeroRating: ref
                                    .watch(
                                        userByIdStreamProvider(offer.heroId))
                                    .maybeWhen(
                                      data: (u) =>
                                          (u?.heroProfile?.rating) ?? 0.0,
                                      orElse: () => null,
                                    ),
                                sellerHeroRatingCount: ref
                                    .watch(
                                        userByIdStreamProvider(offer.heroId))
                                    .maybeWhen(
                                      data: (u) =>
                                          (u?.heroProfile?.totalRatings) ?? 0,
                                      orElse: () => null,
                                    ),
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
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
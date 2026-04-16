import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/hero_header.dart';
import '../widgets/hero_bottom_nav.dart';
import '../widgets/hero_fab.dart';
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
import '../../../../domain/entities/offer.dart';
import '../../../../domain/entities/offer_condition.dart';
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
  bool _isLoadingMore = false;
  bool _pendingLoadMore = false;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isSearchExpanded) return;

    final position = _scrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;

    if (distanceToBottom > 320) return;
    if (_isLoadingMore) return;

    _isLoadingMore = true;

    if (!_pendingLoadMore) {
      _pendingLoadMore = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(catalogPaginationProvider.notifier).loadMore();
        _pendingLoadMore = false;
      });
    }

    Future<void>.delayed(const Duration(milliseconds: 350)).then((_) {
      if (!mounted) return;
      _isLoadingMore = false;
    });
  }

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
      ref.read(catalogPaginationProvider.notifier).reset();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchExpandedChanged(bool expanded) {
    setState(() => _isSearchExpanded = expanded);
    _scrollController.animateTo(
      expanded ? 80.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
                  onBackPressed: () => ref
                      .read(heroHomeViewModelProvider.notifier)
                      .selectNavItem(0),
                ),
              );
            }
            if (selectedIndex == 3) return const NotificationsScreen();
            if (selectedIndex == 1) return const MapLocationScreen();

            return ScrollConfiguration(
              behavior: const _NoStretchScrollBehavior(),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                // KEY FIX: cacheExtent keeps off-screen widgets alive so they
                // are never torn down while their ref.watch() is still active.
                cacheExtent: 1200,
                slivers: [
                  HeroHeader(onSearchExpandedChanged: _onSearchExpandedChanged),

                  if (_isSearchExpanded)
                    const SliverFillRemaining(child: HeroSearchContent())
                  else ...[
                    // ── Spacing ────────────────────────────────────────────────
                    const SliverToBoxAdapter(
                      child: SizedBox(height: paddingNormal),
                    ),

                    // ── Action cards row (Dona / Mis Donaciones) ───────────────
                    // Wrapped in a RepaintBoundary so the card row never
                    // repaints when the list below scrolls.
                    SliverToBoxAdapter(
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: paddingNormal),
                          child: _ActionCardsRow(),
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    // ── Catalog header + filters ───────────────────────────────
                    // Static widgets that never change — isolated so they are
                    // not rebuilt when the offer list updates.
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: paddingNormal),
                        child: _CatalogHeader(),
                      ),
                    ),

                    // ── Offer list ─────────────────────────────────────────────
                    // Each offer is its own sliver item so Flutter's sliver
                    // reconciler can add/remove items at the end without
                    // touching the existing ones.
                    const _CatalogSliverList(),

                    // ── Bottom padding ─────────────────────────────────────────
                    const SliverToBoxAdapter(
                      child: SizedBox(height: spacingScreenBottom),
                    ),
                  ],
                ],
              ),
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

class _NoStretchScrollBehavior extends ScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActionCardsRow  —  stateless, only rebuilds when constraints change
// ─────────────────────────────────────────────────────────────────────────────

class _ActionCardsRow extends StatelessWidget {
  const _ActionCardsRow();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = (width / 390.0).clamp(0.88, 1.10).toDouble();
        final cardPadding = (14.0 * scale).clamp(12.0, 16.0).toDouble();
        final titleSize = (15.0 * scale).clamp(13.0, 16.0).toDouble();
        final bodySize = (12.5 * scale).clamp(11.0, 13.0).toDouble();
        final buttonVPadding = (11.0 * scale).clamp(10.0, 12.0).toDouble();
        final iconSize = (18.0 * scale).clamp(16.0, 20.0).toDouble();
        final cornerRadius = (16.0 * scale).clamp(14.0, 18.0).toDouble();
        final cardHeight = (174.0 * scale).clamp(160.0, 190.0).toDouble();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PublishCard(
                height: cardHeight,
                cardPadding: cardPadding,
                titleSize: titleSize,
                bodySize: bodySize,
                buttonVPadding: buttonVPadding,
                iconSize: iconSize,
                cornerRadius: cornerRadius,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MyDonationsCard(
                height: cardHeight,
                cardPadding: cardPadding,
                titleSize: titleSize,
                bodySize: bodySize,
                cornerRadius: cornerRadius,
                scale: scale,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PublishCard extends StatelessWidget {
  const _PublishCard({
    required this.height,
    required this.cardPadding,
    required this.titleSize,
    required this.bodySize,
    required this.buttonVPadding,
    required this.iconSize,
    required this.cornerRadius,
  });

  final double height;
  final double cardPadding;
  final double titleSize;
  final double bodySize;
  final double buttonVPadding;
  final double iconSize;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(cornerRadius),
          border: Border.all(color: borderGray100, width: 1),
          boxShadow: [
            BoxShadow(
              color: textGray900.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              style: TextStyle(fontSize: bodySize, color: textGray700),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DonationQuestionsScreen(),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    vertical: buttonVPadding,
                    horizontal: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: Icon(Icons.volunteer_activism, size: iconSize),
                label: const Text(
                  'Dona tus productos',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyDonationsCard extends StatelessWidget {
  const _MyDonationsCard({
    required this.height,
    required this.cardPadding,
    required this.titleSize,
    required this.bodySize,
    required this.cornerRadius,
    required this.scale,
  });

  final double height;
  final double cardPadding;
  final double titleSize;
  final double bodySize;
  final double cornerRadius;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(cornerRadius),
          border: Border.all(color: borderGray100, width: 1),
          boxShadow: [
            BoxShadow(
              color: textGray900.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(cornerRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(cornerRadius),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyProductsScreen()),
            ),
            child: Padding(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(
                        (10.0 * scale).clamp(7.0, 10.0).toDouble()),
                    decoration: BoxDecoration(
                      color: primaryOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: primaryOrange,
                      size: (24.0 * scale).clamp(20.0, 26.0).toDouble(),
                    ),
                  ),
                  SizedBox(
                      height: (8.0 * scale).clamp(6.0, 8.0).toDouble()),
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
                      height: (6.0 * scale).clamp(4.0, 6.0).toDouble()),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'Publica y edita tus productos',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: bodySize, color: textGray700),
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Icon(Icons.chevron_right_rounded,
                        color: primaryOrange),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CatalogHeader  —  title + filters, never rebuilt by list changes
// ─────────────────────────────────────────────────────────────────────────────

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catálogo de productos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textGray900,
          ),
        ),
        SizedBox(height: 12),
        CategoryFilterChips(),
        SizedBox(height: 12),
        Row(children: [SortOptionsButton()]),
        ActiveFiltersIndicator(),
        SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CatalogSliverList
//
// Uses a true SliverList so each offer item is a first-class sliver.
// Flutter's sliver reconciler matches items by their ValueKey and only
// mounts/unmounts items that actually enter/leave the viewport — items that
// stay on screen are NEVER rebuilt just because the list length changed.
// ─────────────────────────────────────────────────────────────────────────────

class _CatalogSliverList extends ConsumerWidget {
  const _CatalogSliverList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersAsync = ref.watch(filteredOffersProvider);

    final List<Offer> offers = offersAsync.maybeWhen(
      data: (list) => list,
      orElse: () => offersAsync.asData?.value ?? const [],
    );

    final bool isFirstLoad = offersAsync.isLoading && offers.isEmpty;
    final bool isLoadingMore = offersAsync.isLoading && offers.isNotEmpty;

    // ── First load spinner ─────────────────────────────────────────────────
    if (isFirstLoad) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(color: primaryOrange)),
        ),
      );
    }

    // ── Error (no cached data) ─────────────────────────────────────────────
    if (offersAsync.hasError && offers.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Error al cargar productos: ${offersAsync.error}',
            style: const TextStyle(color: textGray600),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // ── Empty state ────────────────────────────────────────────────────────
    if (offers.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No se encontraron productos',
              style: TextStyle(color: textGray600),
            ),
          ),
        ),
      );
    }

    // ── Offer list as a MultiSliver so we can append the spinner sliver ───
    return _OfferSliverGroup(
      offers: offers,
      isLoadingMore: isLoadingMore,
    );
  }
}

class _OfferSliverGroup extends StatelessWidget {
  const _OfferSliverGroup({
    required this.offers,
    required this.isLoadingMore,
  });

  final List<Offer> offers;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    // We can't return multiple slivers from one widget without a multi-sliver
    // package, so we wrap everything in a single SliverMainAxisGroup-like
    // approach using a SliverPadding that wraps a SliverList.
    // The container card decoration is drawn by the first/last item
    // themselves via a custom clip, keeping each item independently stable.
    return SliverMainAxisGroup(
      slivers: [
        // Count label
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: paddingNormal, vertical: 4),
            child: Text(
              '${offers.length} producto${offers.length != 1 ? 's' : ''} '
              'encontrado${offers.length != 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 13,
                color: textGray600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        // Card container + items
        SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: paddingNormal),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final offer = offers[index];
                final isLast = index == offers.length - 1;
                final isFirst = index == 0;

                // Clip the first and last items to match the card's rounded
                // corners. The container background/shadow is on the sliver
                // padding wrapper below.
                return _OfferListItem(
                  key: ValueKey<String>(offer.offerId),
                  offer: offer,
                  isFirst: isFirst,
                  isLast: isLast,
                  totalCount: offers.length,
                );
              },
              childCount: offers.length,
              // Stable key function so Flutter reuses elements by offerId
              // instead of by index when the list grows.
              findChildIndexCallback: (key) {
                final valueKey = key as ValueKey<String>;
                final idx = offers.indexWhere(
                  (o) => o.offerId == valueKey.value,
                );
                return idx == -1 ? null : idx;
              },
            ),
          ),
        ),

        // Bottom pagination spinner
        if (isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: primaryOrange,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OfferListItem  —  self-contained ConsumerWidget per row
// ─────────────────────────────────────────────────────────────────────────────

class _OfferListItem extends ConsumerWidget {
  const _OfferListItem({
    super.key,
    required this.offer,
    required this.isFirst,
    required this.isLast,
    required this.totalCount,
  });

  final Offer offer;
  final bool isFirst;
  final bool isLast;
  final int totalCount;

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
    final sellerAsync = ref.watch(userByIdStreamProvider(offer.heroId));

    final sellerName = sellerAsync.maybeWhen(
      data: (user) => user?.fullName ?? 'Vendedor',
      orElse: () => 'Vendedor',
    );
    final sellerRating = sellerAsync.maybeWhen(
      data: (u) => (u?.heroProfile?.rating) ?? 0.0,
      orElse: () => null,
    );
    final sellerRatingCount = sellerAsync.maybeWhen(
      data: (u) => (u?.heroProfile?.totalRatings) ?? 0,
      orElse: () => null,
    );

    // Rounded corners only on first/last items to match the card look
    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(18) : Radius.zero,
      bottom: isLast ? const Radius.circular(18) : Radius.zero,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: borderRadius,
        border: Border(
          left: const BorderSide(color: borderGray100),
          right: const BorderSide(color: borderGray100),
          top: isFirst
              ? const BorderSide(color: borderGray100)
              : BorderSide.none,
          bottom: const BorderSide(color: borderGray100),
        ),
        boxShadow: isFirst
            ? [
                BoxShadow(
                  color: textGray900.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => OfferDetailScreen(offer: offer)),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: ProductCard(
                key: ValueKey<String>('product_${offer.offerId}'),
                offerId: offer.offerId,
                name: offer.title,
                sellerHeroId: offer.heroId,
                moderationStatus: offer.moderationStatus,
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
                sellerName: sellerName,
                sellerHeroRating: sellerRating,
                sellerHeroRatingCount: sellerRatingCount,
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
      ),
    );
  }
}

class _CenterDockedWithOffset extends FloatingActionButtonLocation {
  const _CenterDockedWithOffset(this.dy);

  final double dy;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final base =
        FloatingActionButtonLocation.centerDocked.getOffset(scaffoldGeometry);
    return Offset(base.dx, base.dy + dy);
  }
}
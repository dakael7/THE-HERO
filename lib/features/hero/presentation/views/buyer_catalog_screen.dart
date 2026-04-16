import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/weight_utils.dart';
import '../../../../domain/providers/favorites_providers.dart';
import '../../../../domain/entities/offer.dart';
import '../../../../domain/entities/offer_condition.dart';
import '../../../../domain/entities/user.dart';
import '../../../offers/presentation/providers/offer_comments_provider.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../moderation/presentation/widgets/report_offer_bottom_sheet.dart';
import '../../../moderation/presentation/widgets/report_user_bottom_sheet.dart';
import '../../cart/checkout_screen.dart';
import '../../cart/cart_provider.dart';
import '../../../offers/presentation/providers/offers_provider.dart';
import '../providers/catalog_filters_provider.dart';
import '../widgets/catalog_filter_widgets.dart';
import '../widgets/product_card.dart';

// ─────────────────────────────────────────────
//  BUYER CATALOG SCREEN
// ─────────────────────────────────────────────
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
    final offersAsync = ref.watch(filteredOffersProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: offersAsync.when(
        loading: () => const _LoadingState(),
        error: (error, _) => _ErrorState(
          message: 'No se pudo cargar el catálogo',
          onRetry: () => ref.invalidate(activeOffersProvider(OffersFilter())),
        ),
        data: (offers) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── SLIVER APP BAR ──
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                elevation: 0,
                backgroundColor: primaryOrangeLight,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Catálogo',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: textGray900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      if (offers.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: textGray900,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${offers.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: primaryOrangeLight,
                            ),
                          ),
                        ),
                    ],
                  ),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primaryOrangeLight, primaryOrange],
                      ),
                    ),
                    child: Positioned.fill(
                      child: Opacity(
                        opacity: 0.04,
                        child: CustomPaint(painter: _GridPatternPainter()),
                      ),
                    ),
                  ),
                ),
              ),

              // ── SEARCH BAR ──
              SliverToBoxAdapter(
                child: Container(
                  color: primaryOrangeLight,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const CatalogSearchBar(),
                  ),
                ),
              ),

              // ── WAVE DIVIDER ──
              SliverToBoxAdapter(
                child: Container(
                  height: 20,
                  decoration: const BoxDecoration(
                    color: primaryOrangeLight,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                ),
              ),

              // ── FILTERS ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                  child: Column(
                    children: [
                      const CategoryFilterChips(),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: const [SortOptionsButton()],
                        ),
                      ),
                      const ActiveFiltersIndicator(),
                    ],
                  ),
                ),
              ),

              // ── RESULTS COUNT / EMPTY STATE ──
              if (offers.isEmpty)
                const SliverFillRemaining(child: _EmptyState())
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          decoration: BoxDecoration(
                            color: primaryOrange,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${offers.length} producto${offers.length != 1 ? 's' : ''} encontrado${offers.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: textGray600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── PRODUCT LIST ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final offer = offers[index];
                        final sellerAsync =
                            ref.watch(userByIdStreamProvider(offer.heroId));
                        final sellerName = _sellerNameFor(sellerAsync);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OfferDetailScreen(offer: offer),
                                ),
                              );
                            },
                            child: ProductCard(
                              offerId: offer.offerId,
                              name: offer.title,
                              sellerHeroId: offer.heroId,
                              moderationStatus: offer.moderationStatus,
                              condition: offer.condition.displayName,
                              colorCondition:
                                  _conditionColor(offer.condition),
                              category: offer.category,
                              availableQty: offer.availableQty,
                              viewCount: offer.viewCount,
                              orderCount: offer.orderCount,
                              weight: offer.weight,
                              pickupGeo:
                                  offer.itemLocationSnapshot?.geopoint,
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
                              sellerHeroRating: sellerAsync.maybeWhen(
                                data: (u) =>
                                    (u?.heroProfile?.rating) ?? 0.0,
                                orElse: () => null,
                              ),
                              sellerHeroRatingCount: sellerAsync.maybeWhen(
                                data: (u) =>
                                    (u?.heroProfile?.totalRatings) ?? 0,
                                orElse: () => null,
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: offers.length,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _sellerNameFor(AsyncValue<User?> sellerAsync) {
    return sellerAsync.maybeWhen(
      data: (user) => user?.fullName ?? 'Vendedor',
      orElse: () => 'Vendedor',
    );
  }
}

// ─────────────────────────────────────────────
//  PILL WIDGET
// ─────────────────────────────────────────────
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.accent = false});
  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent ? backgroundWhite : borderGray100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent ? primaryOrange : borderGray100,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent ? primaryOrange : textGray600),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent ? primaryOrange : textGray600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  LOADING STATE
// ─────────────────────────────────────────────
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: backgroundGray50,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: primaryOrange,
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              'Cargando catálogo...',
              style: TextStyle(
                fontSize: 14,
                color: textGray600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  EMPTY STATE
// ─────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: borderGray100,
                shape: BoxShape.circle,
                border: Border.all(color: primaryOrange, width: 2),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 42,
                color: primaryOrange,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sin productos activos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textGray900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando se publiquen ofertas activas\naparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: textGray600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  ERROR STATE
// ─────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: borderGray100,
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFFFCCCC), width: 2),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 42,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Reintentar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  GRID PATTERN PAINTER
// ─────────────────────────────────────────────
class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;
    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPatternPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════
//  OFFER DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════
class OfferDetailScreen extends ConsumerStatefulWidget {
  const OfferDetailScreen({super.key, required this.offer});

  final Offer offer;

  @override
  ConsumerState<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends ConsumerState<OfferDetailScreen> {
  bool _incremented = false;
  int _optimisticViewsDelta = 0;
  PageController? _galleryController;
  int _galleryIndex = 0;

  // ── Cart button state ──
  int _cartQuantity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeIncrementView();
    });
  }

  @override
  void dispose() {
    _galleryController?.dispose();
    super.dispose();
  }

  Future<void> _maybeIncrementView() async {
    if (!mounted || _incremented) return;
    final userAsync = ref.read(profileProvider);
    final userId = userAsync.maybeWhen(
          data: (user) => user?.id,
          orElse: () => null,
        );

    if (userId != null && userId == widget.offer.heroId) {
      _incremented = true;
      return;
    }
    try {
      await ref.read(incrementViewCountProvider(widget.offer.offerId).future);
      if (!mounted) return;
      setState(() {
        _incremented = true;
        _optimisticViewsDelta = 1;
      });
    } catch (_) {
      _incremented = true;
    }
  }

  Widget _buildOfferImage(String imageUrl, {BoxFit fit = BoxFit.cover}) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) {
      return Image.asset('assets/logo_hero.png', fit: BoxFit.contain);
    }
    if (trimmed.startsWith('assets/')) {
      return Image.asset(trimmed, fit: fit);
    }
    return Image.network(
      trimmed,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          Image.asset('assets/logo_hero.png', fit: BoxFit.contain),
    );
  }

  void _openFullScreenGallery(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return;
    final controller = PageController(initialPage: initialIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: images.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Center(
                      child: _buildOfferImage(images[index],
                          fit: BoxFit.contain),
                    ),
                  );
                },
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _conditionColor(OfferCondition condition) {
    switch (condition) {
      case OfferCondition.newProduct:
        return primaryOrange;
      case OfferCondition.excellent:
        return primaryOrange;
      case OfferCondition.good:
        return textGray600;
      case OfferCondition.used:
        return textGray900;
    }
  }

  // ── Cart helpers ──────────────────────────────────────────────
  void _addToCart() {
    final offer = widget.offer;

    final maxQty = offer.availableQty;
    final currentUserId = ref.read(profileProvider).maybeWhen(
          data: (user) => user?.id,
          orElse: () => null,
        );

    final currentUser = ref.read(profileProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    if (currentUser != null && currentUser.isSuspended) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu cuenta está suspendida. No puedes agregar productos al carrito en este momento.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (currentUserId != null && offer.heroId == currentUserId) {
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

    final pickupCc = offer.itemLocationSnapshot?.countryCode?.trim();
    if (pickupCc == null || pickupCc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este producto no tiene país de retiro configurado.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }

    ref.read(cartProvider.notifier).addItem(
          offerId: offer.offerId,
          name: offer.title,
          condition: offer.condition.displayName,
          price: 0.0,
          weight: offer.weight,
          imageUrl: offer.coverImageUrl,
          availableQty: offer.availableQty,
          pickupGeo: offer.itemLocationSnapshot?.geopoint,
          pickupAddressSnapshot:
              offer.itemLocationSnapshot?.displayAddressMultiline,
          pickupCountryCode: offer.itemLocationSnapshot?.countryCode,
          sellerHeroId: offer.heroId,
          allowInPersonPickup: offer.allowInPersonPickup,
        );

    setState(() => _cartQuantity++);
  }

  void _incrementCart() {
    _addToCart();
  }

  void _decrementCart() {
    if (_cartQuantity <= 0) return;
    ref.read(cartProvider.notifier).removeOneItem(widget.offer.offerId);
    setState(() => _cartQuantity--);
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final badgeColor = _conditionColor(offer.condition);
    const priceText = 'Donación';
    final coverUrl = offer.coverImageUrl.trim();
    final hasCover = coverUrl.isNotEmpty;

    final currentUserId = ref.watch(profileProvider).maybeWhen(
          data: (user) => user?.id,
          orElse: () => null,
        );

    String normalizeImageKey(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return '';
      if (trimmed.startsWith('assets/')) return trimmed;
      Uri? uri;
      try {
        uri = Uri.parse(trimmed);
      } catch (_) {
        return trimmed;
      }
      if (uri.scheme.isEmpty || uri.host.isEmpty) return trimmed;
      return uri.replace(query: '', fragment: '').toString();
    }

    final galleryImages = <String>[];
    final seen = <String>{};
    final coverKey = hasCover ? normalizeImageKey(coverUrl) : '';
    if (hasCover && coverKey.isNotEmpty && seen.add(coverKey)) {
      galleryImages.add(coverUrl);
    }
    for (final raw in offer.imageUrls) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      final key = normalizeImageKey(url);
      if (key.isEmpty) continue;
      if (coverKey.isNotEmpty && key == coverKey) continue;
      if (seen.add(key)) galleryImages.add(url);
    }

    final thumbnailImages = hasCover && galleryImages.isNotEmpty
        ? galleryImages.skip(1).toList()
        : galleryImages;

    _galleryController ??= PageController(initialPage: _galleryIndex);

    final showConditionChip = offer.condition != OfferCondition.newProduct;
    final soldCount = offer.orderCount;
    final viewsCount = offer.viewCount + _optimisticViewsDelta;
    final location = offer.itemLocationSnapshot;

    final sellerProfileAsync =
        ref.watch(userByIdStreamProvider(offer.heroId));
    final sellerName = sellerProfileAsync.maybeWhen(
      data: (user) => user?.fullName ?? 'Vendedor',
      orElse: () => 'Vendedor',
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── SLIVER APP BAR WITH GALLERY ──
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            elevation: 0,
            backgroundColor: primaryOrangeLight,
            foregroundColor: textGray900,
            actions: [
              Consumer(
                builder: (context, ref, _) {
                  final userAsync = ref.watch(profileProvider);
                  final userId = userAsync.maybeWhen(
                    data: (user) => user?.id,
                    orElse: () => null,
                  );

                  final canReport = userId != null && userId != widget.offer.heroId;
                  final favoriteIdsAsync = userId == null
                      ? const AsyncValue<List<String>>.data(<String>[])
                      : ref.watch(favoriteOfferIdsProvider(userId));
                  final isFavorite = favoriteIdsAsync.maybeWhen(
                    data: (ids) => ids.contains(offer.offerId),
                    orElse: () => false,
                  );

                  return Row(
                    children: [
                      if (canReport)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: backgroundWhite.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              tooltip: 'Reportar publicación',
                              onPressed: () => showReportOfferSheet(
                                context,
                                offerId: widget.offer.offerId,
                                offerTitle: widget.offer.title,
                              ),
                              icon: const Icon(
                                Icons.flag_outlined,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: backgroundWhite.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: isFavorite
                                ? 'Quitar de favoritos'
                                : 'Agregar a favoritos',
                            onPressed: userId == null
                                ? null
                                : () async {
                                    try {
                                      await ref
                                          .read(favoritesNotifierProvider.notifier)
                                          .toggleFavorite(userId, offer.offerId);
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'No se pudo actualizar favoritos'),
                                        ),
                                      );
                                    }
                                  },
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: isFavorite ? primaryOrange : textGray900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gallery
                  galleryImages.isEmpty
                      ? Container(
                          color: borderGray100,
                          child: const Center(
                            child: Icon(Icons.image_outlined,
                                size: 64, color: textGray600),
                          ),
                        )
                      : GestureDetector(
                          onTap: () => _openFullScreenGallery(
                            context,
                            images: galleryImages,
                            initialIndex: _galleryIndex,
                          ),
                          child: PageView.builder(
                            controller: _galleryController,
                            itemCount: galleryImages.length,
                            onPageChanged: (index) {
                              if (!mounted) return;
                              setState(() => _galleryIndex = index);
                            },
                            itemBuilder: (context, index) {
                              return _buildOfferImage(galleryImages[index]);
                            },
                          ),
                        ),

                  // Bottom gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Counter badge
                  if (galleryImages.length > 1)
                    Positioned(
                      top: 90,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_galleryIndex + 1} / ${galleryImages.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),

                  // Dot indicators
                  if (galleryImages.length > 1)
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(galleryImages.length, (i) {
                          final active = i == _galleryIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin:
                                const EdgeInsets.symmetric(horizontal: 3),
                            height: 6,
                            width: active ? 20 : 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? primaryOrange
                                  : backgroundWhite.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                    ),

                  // Condition badge
                  if (showConditionChip)
                    Positioned(
                      bottom: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          offer.condition.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── CONTENT ──
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── MAIN INFO CARD ──
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: backgroundWhite,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              offer.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: primaryOrange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              priceText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: borderGray100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                              color: textGray600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sellerName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (currentUserId != null &&
                              currentUserId != offer.heroId)
                            IconButton(
                              tooltip: 'Reportar usuario',
                              onPressed: () => showReportUserSheet(
                                context,
                                reportedUserId: offer.heroId,
                                reportedRole: 'hero',
                                relatedOfferId: offer.offerId,
                              ),
                              icon: const Icon(
                                Icons.flag_outlined,
                                color: Colors.red,
                                size: 20,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      const Divider(color: borderGray100, height: 1),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          if (offer.ratingCount > 0) ...[
                            _StatBadge(
                              icon: Icons.star_rounded,
                              label: offer.avgRating.toStringAsFixed(1),
                              iconColor: primaryOrange,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _StatBadge(
                            icon: Icons.shopping_bag_outlined,
                            label: soldCount > 0
                                ? '$soldCount vendidos'
                                : 'Sin ventas',
                            iconColor: primaryOrange,
                          ),
                          const SizedBox(width: 8),
                          _StatBadge(
                            icon: Icons.visibility_outlined,
                            label: '${viewsCount > 0 ? viewsCount : 0}',
                            iconColor: primaryOrange,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── THUMBNAIL GALLERY ──
                if (thumbnailImages.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'Galería',
                    icon: Icons.photo_library_outlined,
                  ),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: thumbnailImages.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final imageUrl = thumbnailImages[index];
                        final targetIndex = hasCover ? (index + 1) : index;
                        final selected = _galleryIndex == targetIndex;
                        return GestureDetector(
                          onTap: () {
                            _galleryController?.animateToPage(
                              targetIndex,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                            if (!mounted) return;
                            setState(() => _galleryIndex = targetIndex);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? primaryOrange
                                    : Colors.transparent,
                                width: selected ? 2.5 : 0,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: primaryOrange
                                            .withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(selected ? 12 : 14),
                              child: _buildOfferImage(imageUrl),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── DETAILS PILLS ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(
                        icon: Icons.category_outlined,
                        label: offer.category,
                        accent: true,
                      ),
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
                      _Pill(
                        icon: Icons.scale_outlined,
                        label: 'Peso: ${formatWeightKg(offer.weight)}',
                      ),
                      _Pill(
                        icon: Icons.person_pin_circle_outlined,
                        label: offer.allowInPersonPickup
                            ? 'Retiro en persona: Sí'
                            : 'Retiro en persona: No',
                      ),
                    ],
                  ),
                ),

                // ── DESCRIPTION ──
                _SectionHeader(
                  label: 'Descripción',
                  icon: Icons.notes_rounded,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderGray100),
                    ),
                    child: Text(
                      offer.description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: textGray700,
                      ),
                    ),
                  ),
                ),

                // ── LOCATION ──
                if (location != null) ...[
                  _SectionHeader(
                    label: 'Ubicación de retiro',
                    icon: Icons.place_outlined,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: backgroundWhite,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderGray100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: borderGray100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.place_outlined,
                                    size: 18,
                                    color: primaryOrange,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        location.fullAddress,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: textGray900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Lat: ${location.latitude.toStringAsFixed(5)}, Lng: ${location.longitude.toStringAsFixed(5)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: textGray600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                            ),
                            child: SizedBox(
                              height: 180,
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(
                                    location.latitude,
                                    location.longitude,
                                  ),
                                  zoom: 15,
                                ),
                                markers: {
                                  Marker(
                                    markerId:
                                        const MarkerId('offer_location'),
                                    position: LatLng(
                                      location.latitude,
                                      location.longitude,
                                    ),
                                  ),
                                },
                                zoomControlsEnabled: false,
                                myLocationButtonEnabled: false,
                                myLocationEnabled: false,
                                rotateGesturesEnabled: false,
                                tiltGesturesEnabled: false,
                                zoomGesturesEnabled: false,
                                scrollGesturesEnabled: false,
                                liteModeEnabled: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── PICKUP SCHEDULE ──
                if (offer.pickupSchedule != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: backgroundWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderGray100),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: borderGray100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.schedule_outlined,
                              size: 18,
                              color: textGray600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Horario de retiro',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: textGray600,
                                  ),
                                ),
                                Text(
                                  offer.pickupSchedule!
                                      .getScheduleDescription(),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textGray900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── Q&A SECTION ──
                if (offer.price > 0) ...[
                  _SectionHeader(
                    label: 'Preguntas y respuestas',
                    icon: Icons.forum_outlined,
                  ),

                  Consumer(
                    builder: (context, ref, _) {
                      final commentsAsync = ref.watch(
                        offerCommentsProvider(offer.offerId),
                      );
                      final currentUser =
                          ref.watch(profileProvider).value;
                      final isOwner = currentUser?.id == offer.heroId;

                      return commentsAsync.when(
                        data: (comments) {
                          if (comments.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: backgroundWhite,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: borderGray100),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 36,
                                        color: textGray600),
                                    SizedBox(height: 10),
                                    Text(
                                      'Sin preguntas aún',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: textGray700,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '¡Sé el primero en preguntar!',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: textGray600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            child: Column(
                              children: comments.map((comment) {
                                final hasReply = comment.reply != null &&
                                    comment.reply!.isNotEmpty;

                                return Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: backgroundWhite,
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    border:
                                        Border.all(color: borderGray100),
                                  ),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration:
                                                  const BoxDecoration(
                                                color: borderGray100,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.help_outline_rounded,
                                                size: 18,
                                                color: primaryOrange,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        comment.userName,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 13,
                                                          color: textGray900,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      Text(
                                                        _formatDate(
                                                            comment.createdAt),
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: textGray600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    comment.text,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: textGray700,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (hasReply)
                                        Container(
                                          margin: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 16),
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: backgroundGray50,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: borderGray100,
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration:
                                                    const BoxDecoration(
                                                  color: primaryOrange,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.reply_rounded,
                                                  size: 16,
                                                  color: textGray900,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(
                                                      comment.replyBy ??
                                                          'Vendedor',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 12,
                                                        color: textGray900,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      comment.reply!,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        color: textGray700,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      if (isOwner && !hasReply)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 12),
                                          child: GestureDetector(
                                            onTap: () => _showReplyDialog(
                                              context,
                                              ref,
                                              comment.commentId,
                                              offer.offerId,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: primaryOrange,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.reply_rounded,
                                                    size: 16,
                                                    color: primaryOrange,
                                                  ),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Responder',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: primaryOrange,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: primaryOrange,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Error: $e',
                            style: const TextStyle(color: textGray900),
                          ),
                        ),
                      );
                    },
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: GestureDetector(
                      onTap: () =>
                          _showAddQuestionDialog(context, ref, offer.offerId),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: backgroundWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: primaryOrange),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.question_answer_outlined,
                              color: primaryOrange,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Hacer una pregunta',
                              style: TextStyle(
                                color: primaryOrange,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // ── ADD TO CART BUTTON ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  child: _AddToCartButton(
                    quantity: _cartQuantity,
                    onAdd: _addToCart,
                    onIncrement: _incrementCart,
                    onDecrement: _decrementCart,
                    onCheckout: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CheckoutScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return 'Hace ${difference.inDays} día${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'Hace ${difference.inHours} hora${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return 'Hace ${difference.inMinutes} minuto${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'Ahora';
    }
  }

  void _showAddQuestionDialog(
      BuildContext context, WidgetRef ref, String offerId) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Hacer una pregunta',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: textController,
          decoration: InputDecoration(
            hintText: '¿Cuál es tu pregunta?',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryOrange),
            ),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: textGray600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = textController.text.trim();
              if (text.isEmpty) return;
              final user = ref.read(profileProvider).value;
              if (user == null) return;
              await ref.read(addCommentProvider.notifier).addComment(
                    offerId: offerId,
                    userId: user.id,
                    userName: user.fullName,
                    userAvatarUrl: null,
                    text: text,
                  );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pregunta enviada')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Enviar',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showReplyDialog(BuildContext context, WidgetRef ref,
      String commentId, String offerId) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Responder pregunta',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: textController,
          decoration: InputDecoration(
            hintText: 'Escribe tu respuesta',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryOrange),
            ),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: textGray600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = textController.text.trim();
              if (text.isEmpty) return;
              final user = ref.read(profileProvider).value;
              if (user == null) return;
              await ref.read(addCommentProvider.notifier).replyToComment(
                    offerId: offerId,
                    commentId: commentId,
                    reply: text,
                    replyBy: user.fullName,
                  );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Respuesta enviada')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Enviar',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  ADD TO CART BUTTON
// ─────────────────────────────────────────────
class _AddToCartButton extends StatelessWidget {
  const _AddToCartButton({
    required this.quantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onCheckout,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 250),
        crossFadeState: quantity == 0
            ? CrossFadeState.showFirst
            : CrossFadeState.showSecond,
        firstCurve: Curves.easeInOut,
        secondCurve: Curves.easeInOut,
        sizeCurve: Curves.easeInOut,
        firstChild: _buildAddButton(),
        secondChild: quantity > 0 ? _buildCartControl() : const SizedBox(),
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: primaryOrange,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: primaryOrange.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'Agregar al carrito',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartControl() {
    return Row(
      children: [
        // ── Counter ──
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: backgroundWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderGray100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CounterBtn(icon: Icons.remove_rounded, onTap: onDecrement),
              Container(width: 1, height: 24, color: borderGray100),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: SizedBox(
                  key: ValueKey(quantity),
                  width: 40,
                  child: Text(
                    '$quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 24, color: borderGray100),
              _CounterBtn(icon: Icons.add_rounded, onTap: onIncrement),
            ],
          ),
        ),

        const SizedBox(width: 10),

        // ── Checkout button ──
        Expanded(
          child: GestureDetector(
            onTap: onCheckout,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: primaryOrange,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'Procesar pago',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Text(
                        '$quantity',
                        key: ValueKey(quantity),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: primaryOrange,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  COUNTER BUTTON HELPER
// ─────────────────────────────────────────────
class _CounterBtn extends StatelessWidget {
  const _CounterBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 52,
        child: Icon(icon, size: 18, color: primaryOrange),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SECTION HEADER
// ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: primaryOrange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: textGray900),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textGray900,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  STAT BADGE
// ─────────────────────────────────────────────
class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.label,
    required this.iconColor,
  });
  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundGray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderGray100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textGray900,
            ),
          ),
        ],
      ),
    );
  }
}
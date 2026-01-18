import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../viewmodels/search_viewmodel.dart';
import '../../../shared/notifications/presentation/providers/notifications_provider.dart';
import '../../../shared/notifications/presentation/views/notifications_screen.dart';
import '../providers/catalog_filters_provider.dart';
import '../widgets/product_card.dart';
import '../widgets/catalog_filter_widgets.dart';
import '../../../../domain/entities/offer_condition.dart';
import '../../../../domain/entities/user.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../views/buyer_catalog_screen.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

class HeroHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function() buildLogoSection;
  final Widget Function() buildNotificationIcon;
  final Widget Function(BuildContext) buildSearchBar;
  final bool isSearchExpanded;
  final Animation<double>? fadeAnimation;

  HeroHeaderDelegate({
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.buildLogoSection,
    required this.buildNotificationIcon,
    required this.buildSearchBar,
    required this.isSearchExpanded,
    this.fadeAnimation,
  });

  @override
  double get minExtent => collapsedHeight;

  @override
  double get maxExtent => expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double availableRange = maxExtent - minExtent;
    final double t = availableRange > 0
        ? (shrinkOffset / availableRange).clamp(0.0, 1.0)
        : 0.0;

    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double decorOpacity = isSearchExpanded ? 0.0 : (1.0 - (t * 0.85));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryOrange, primaryYellow.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: decorOpacity,
                child: Stack(
                  children: [
                    Positioned(
                      top: -40,
                      left: -30,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: backgroundWhite.withOpacity(0.16),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      right: -50,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: backgroundWhite.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 46,
                      left: 40,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Fila superior (logo + notificaciones) que se oculta al hacer scroll o expandir búsqueda
          Positioned(
            top: statusBarHeight + paddingNormal - 8 * t,
            left: paddingLarge,
            right: paddingLarge,
            child: Opacity(
              opacity: isSearchExpanded ? 0.0 : (1.0 - t),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [buildLogoSection(), buildNotificationIcon()],
              ),
            ),
          ),

          Positioned(
            left: paddingNormal,
            right: paddingNormal,
            bottom: 12.0,
            child: buildSearchBar(context),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HeroHeaderDelegate oldDelegate) {
    return isSearchExpanded != oldDelegate.isSearchExpanded ||
        fadeAnimation?.value != oldDelegate.fadeAnimation?.value;
  }
}

class HeroHeader extends ConsumerStatefulWidget {
  final VoidCallback? onSearchChanged;
  final VoidCallback? onSearchTap;
  final Function(bool)? onSearchExpandedChanged;

  const HeroHeader({
    super.key,
    this.onSearchChanged,
    this.onSearchTap,
    this.onSearchExpandedChanged,
  });

  @override
  ConsumerState<HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends ConsumerState<HeroHeader>
    with SingleTickerProviderStateMixin {
  bool _isSearchExpanded = false;
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.unfocus();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSearch(bool expanded) {
    setState(() {
      _isSearchExpanded = expanded;
    });
    widget.onSearchExpandedChanged?.call(expanded);
    if (expanded) {
      _animationController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchFocusNode.requestFocus();
      });
    } else {
      _animationController.reverse();

      final currentQuery = _searchController.text.trim();
      if (currentQuery.isNotEmpty) {
        ref.read(searchViewModelProvider.notifier).addRecentQuery(currentQuery);
      }

      _searchController.clear();
      _searchFocusNode.unfocus();
      ref.read(searchViewModelProvider.notifier).clearSearch();
      ref.read(catalogFiltersProvider.notifier).clearSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchViewModelProvider, (previous, next) {
      if (_searchController.text == next.query) return;
      _searchController.value = TextEditingValue(
        text: next.query,
        selection: TextSelection.collapsed(offset: next.query.length),
      );
    });

    final isMobile = ResponsiveUtils.isMobile(context);
    final expandedHeight = isMobile ? 220.0 : 220.0;
    final collapsedHeight = isMobile ? 140.0 : 140.0;

    return SliverPersistentHeader(
      pinned: true,
      delegate: HeroHeaderDelegate(
        expandedHeight: expandedHeight,
        collapsedHeight: collapsedHeight,
        buildLogoSection: _buildLogoSection,
        buildNotificationIcon: _buildNotificationIcon,
        buildSearchBar: _buildSearchBar,
        isSearchExpanded: _isSearchExpanded,
        fadeAnimation: _fadeAnimation,
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundWhite.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: backgroundWhite.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/logo_1.png',
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'TheHero',
            style: TextStyle(
              color: textGray900,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon() {
    final badgeCount = ref.watch(
      notificationsProvider.select(
        (async) => async.maybeWhen(
          data: (notifications) => notifications.where((n) => !n.read).length,
          orElse: () => 0,
        ),
      ),
    );

    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: textGray900.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_none_outlined,
              color: primaryOrange,
              size: 24,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryOrange, Color(0xFFFF6B35)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryYellow, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: backgroundWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: paddingNormal),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isSearchExpanded
              ? primaryOrange.withOpacity(0.3)
              : backgroundWhite.withOpacity(0.5),
          width: _isSearchExpanded ? 2 : 1,
        ),
        boxShadow: _isSearchExpanded
            ? [
                BoxShadow(
                  color: primaryOrange.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: textGray900.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: textGray900.withOpacity(0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: primaryOrange.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: SizedBox(
        height: 56,
        child: Center(
          child: TextField(
            focusNode: _searchFocusNode,
            controller: _searchController,
            readOnly: !_isSearchExpanded,
            showCursor: _isSearchExpanded,
            decoration: InputDecoration(
              hintText: 'Buscar productos...',
              hintStyle: TextStyle(
                color: textGray600.withOpacity(0.7),
                fontSize: 15,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: primaryOrange,
                size: 24,
              ),
              suffixIcon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _isSearchExpanded
                    ? Container(
                        key: const ValueKey('close'),
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: backgroundGray50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: textGray600,
                            size: 20,
                          ),
                          onPressed: () => _toggleSearch(false),
                        ),
                      )
                    : Container(
                        key: const ValueKey('tune'),
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.tune,
                          color: primaryOrange,
                          size: 20,
                        ),
                      ),
              ),
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 4,
              ),
            ),
            style: const TextStyle(
              color: textGray900,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: primaryOrange,
            onTap: () {
              if (!_isSearchExpanded) _toggleSearch(true);
            },
            onChanged: (value) {
              if (_isSearchExpanded) {
                ref.read(searchViewModelProvider.notifier).search(value);
                ref.read(catalogFiltersProvider.notifier).setSearchQuery(value);
              }
            },
            onSubmitted: (value) {
              ref.read(searchViewModelProvider.notifier).addRecentQuery(value);
            },
          ),
        ),
      ),
    );
  }

  TextEditingController get searchController => _searchController;
}

class HeroSearchContent extends ConsumerStatefulWidget {
  final TextEditingController? searchController;

  const HeroSearchContent({super.key, this.searchController});

  @override
  ConsumerState<HeroSearchContent> createState() => _HeroSearchContentState();
}

class _HeroSearchContentState extends ConsumerState<HeroSearchContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _panelController;
  late final Animation<double> _panelOpacity;
  late final Animation<Offset> _panelOffset;

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
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _panelOpacity = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOut,
    );
    _panelOffset = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic),
        );
  }

  @override
  void dispose() {
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchViewModelProvider);
    final offersAsync = ref.watch(filteredOffersProvider);
    final showRecent = searchState.query.trim().isEmpty;

    if (showRecent) {
      _panelController.forward();
    } else {
      _panelController.reverse();
    }

    final isMobile = ResponsiveUtils.isMobile(context);

    final topPadding = isMobile ? 8.0 : 12.0;

    return Container(
      color: backgroundGray50,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: topPadding,
        bottom: 16,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: showRecent
            ? FadeTransition(
                key: const ValueKey('recent'),
                opacity: _panelOpacity,
                child: SlideTransition(
                  position: _panelOffset,
                  child: searchState.recentQueries.isEmpty
                      ? const Center(
                          child: Text(
                            'Busca productos por nombre, categoría o descripción',
                            style: TextStyle(fontSize: 14, color: textGray600),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Búsquedas recientes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: textGray900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: ListView.separated(
                                itemCount: searchState.recentQueries.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final query =
                                      searchState.recentQueries[index];
                                  return Material(
                                    color: backgroundWhite,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        ref
                                            .read(
                                              searchViewModelProvider.notifier,
                                            )
                                            .selectRecentQuery(query);
                                        ref
                                            .read(
                                              catalogFiltersProvider.notifier,
                                            )
                                            .setSearchQuery(query);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.history,
                                              color: textGray600,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                query,
                                                style: const TextStyle(
                                                  color: textGray900,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                size: 18,
                                                color: textGray600,
                                              ),
                                              onPressed: () {
                                                ref
                                                    .read(
                                                      searchViewModelProvider
                                                          .notifier,
                                                    )
                                                    .removeRecentQuery(query);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              )
            : Column(
                key: const ValueKey('results-with-filters'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filters section
                  const CategoryFilterChips(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SortOptionsButton(),
                      SizedBox(width: 8),
                      PriceRangeFilter(),
                    ],
                  ),
                  const ActiveFiltersIndicator(),
                  const SizedBox(height: 12),

                  // Results section
                  Expanded(
                    child: offersAsync.when(
                      loading: () => const Center(
                        key: ValueKey('loading'),
                        child: CircularProgressIndicator(color: primaryOrange),
                      ),
                      error: (error, _) => const Center(
                        key: ValueKey('error'),
                        child: Text(
                          'Error al cargar productos',
                          style: TextStyle(fontSize: 14, color: textGray600),
                        ),
                      ),
                      data: (offers) {
                        if (offers.isEmpty) {
                          return const Center(
                            key: ValueKey('empty'),
                            child: Text(
                              'No se encontraron productos',
                              style: TextStyle(
                                fontSize: 14,
                                color: textGray600,
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          key: const ValueKey('results'),
                          itemCount: offers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final offer = offers[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        OfferDetailScreen(offer: offer),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: backgroundWhite,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: textGray900.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ProductCard(
                                  offerId: offer.offerId,
                                  name: offer.title,
                                  condition: offer.condition.displayName,
                                  colorCondition: _conditionColor(
                                    offer.condition,
                                  ),
                                  price: offer.price,
                                  weight: offer.weight,
                                  showShadow: false,
                                  imageUrl: offer.coverImageUrl,
                                  avgRating: offer.avgRating,
                                  ratingCount: offer.ratingCount,
                                  sellerName: _sellerNameFor(
                                    ref.watch(userByIdProvider(offer.heroId)),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ), // closes offersAsync.when
                  ), // closes Expanded child
                ], // closes Column children
              ), // closes Column
      ), // closes AnimatedSwitcher child
    ); // closes Container
  }
}

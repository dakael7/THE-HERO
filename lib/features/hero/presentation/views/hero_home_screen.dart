import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/hero_header.dart';
import '../widgets/hero_bottom_nav.dart';
import '../widgets/hero_fab.dart';
import '../widgets/hero_promo_banner.dart';
import '../viewmodels/hero_home_viewmodel.dart';
import 'buyer_catalog_screen.dart';
import '../../../shared/profile/presentation/views/profile_screen.dart'
    as profile;
import '../../../shared/profile/presentation/views/my_products_screen.dart';
import '../../../shared/chat/presentation/views/chat_list_screen.dart' as chat;
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    // Reset navigation to first tab on mount
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
      // Collapse header when search is activated
      _scrollController.animateTo(
        80.0, // Scroll enough to collapse the header
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      // Expand header when search is closed
      _scrollController.animateTo(
        0.0, // Scroll back to top
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _isSearchExpanded = false;

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
                  // Al presionar back, volver al tab de inicio
                  ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
                  return false; // No hacer pop de la navegación
                },
                child: profile.ProfileScreen(
                  isRiderProfile: false,
                  onBackPressed: () {
                    // Al presionar el botón de back del perfil, volver al tab de inicio
                    ref
                        .read(heroHomeViewModelProvider.notifier)
                        .selectNavItem(0);
                  },
                ),
              );
            }

            if (selectedIndex == 3) {
              return const chat.ChatListScreen();
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
                            // --- SECCIÓN BANNER PROMOCIONAL ---
                            const RepaintBoundary(child: HeroPromoBanner()),
                            const SizedBox(height: paddingNormal),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: paddingNormal,
                        ),
                        child: Column(
                          children: [
                            // Mis ofertas card
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Material(
                                color: backgroundWhite,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const MyProductsScreen(),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: borderGray100,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: textGray900.withOpacity(0.05),
                                          blurRadius: 12,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: primaryYellow.withOpacity(
                                              0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.inventory_2_outlined,
                                            color: primaryOrange,
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: const [
                                              Text(
                                                'Mis ofertas',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: textGray900,
                                                ),
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Publica y edita tus productos',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: textGray700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: textGray600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Catálogo integrado
                            const _CatalogSection(),
                          ],
                        ),
                      ),

                      const SizedBox(height: spacingScreenBottom),
                    ]),
                  ),
              ],
            );
          },
        ),

        // 3. Navegación Inferior y FAB - solo visible cuando no hay búsqueda activa
        bottomNavigationBar: _isSearchExpanded ? null : const HeroBottomNav(),
        floatingActionButton: _isSearchExpanded ? null : HeroFAB(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
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
        // Title
        const Text(
          'Catálogo de productos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textGray900,
          ),
        ),
        const SizedBox(height: 12),

        // Category chips
        const CategoryFilterChips(),
        const SizedBox(height: 12),

        // Sort and price filter
        Row(
          children: const [
            SortOptionsButton(),
            SizedBox(width: 8),
            PriceRangeFilter(),
          ],
        ),

        // Active filters indicator
        const ActiveFiltersIndicator(),

        // Products list
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
                // Results count
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

                // Products
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

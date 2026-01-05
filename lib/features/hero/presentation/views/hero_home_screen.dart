import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/hero_header.dart';
import '../widgets/hero_categories_section.dart';
import '../widgets/hero_featured_products_section.dart';
import '../widgets/hero_bottom_nav.dart';
import '../widgets/hero_fab.dart';
import '../widgets/hero_promo_banner.dart';
import '../viewmodels/hero_home_viewmodel.dart';
import '../../../shared/profile/presentation/views/profile_screen.dart'
    as profile;
import '../../../shared/profile/presentation/views/my_products_screen.dart';
import '../../../shared/chat/presentation/views/chat_list_screen.dart' as chat;
import '../../../map/presentation/views/map_location_screen.dart';

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

  bool _isSearchExpanded = false;

  // Optimización: Listas estáticas como const para evitar recreación
  static const List<Map<String, dynamic>> _categories = [
    {
      'label': 'Electrónicos',
      'icon': Icons.phone_android,
      'iconColor': categoryTextBlue,
      'bgColor': categoryBgBlue,
    },
    {
      'label': 'Hogar',
      'icon': Icons.chair_alt,
      'iconColor': categoryTextGreen,
      'bgColor': categoryBgGreen,
    },
    {
      'label': 'Computación',
      'icon': Icons.laptop_mac,
      'iconColor': categoryTextPurple,
      'bgColor': categoryBgPurple,
    },
    {
      'label': 'Ropa',
      'icon': Icons.checkroom,
      'iconColor': categoryTextPink,
      'bgColor': categoryBgPink,
    },
    {
      'label': 'Deportes',
      'icon': Icons.sports_soccer,
      'iconColor': categoryTextRed,
      'bgColor': categoryBgRed,
    },
    {
      'label': 'Libros y Cómics',
      'icon': Icons.menu_book,
      'iconColor': categoryTextYellow,
      'bgColor': categoryBgYellow,
    },
    {
      'label': 'Herramientas y Bricolaje',
      'icon': Icons.handyman,
      'iconColor': textGray900,
      'bgColor': backgroundWhite,
    },
    {
      'label': 'Accesorios para Mascotas',
      'icon': Icons.pets,
      'iconColor': categoryTextBlue,
      'bgColor': categoryBgBlue,
    },
    {
      'label': 'Muebles Grandes',
      'icon': Icons.weekend,
      'iconColor': categoryTextGreen,
      'bgColor': categoryBgGreen,
    },
    {
      'label': 'Instrumentos Musicales',
      'icon': Icons.music_note,
      'iconColor': categoryTextPink,
      'bgColor': categoryBgPink,
    },
    {
      'label': 'Juguetes',
      'icon': Icons.toys,
      'iconColor': primaryOrange,
      'bgColor': primaryOrange,
    },
  ];

  // Lista de productos destacados como const
  static const List<Map<String, dynamic>> _products = [
    {
      'name': 'iPhone 13 Pro',
      'condition': 'Excelente estado',
      'colorCondition': categoryTextGreen,
      'price': 45990.0,
      'weight': 0.2,
    },
    {
      'name': 'MacBook Air M1',
      'condition': 'Como nuevo',
      'colorCondition': categoryTextGreen,
      'price': 89990.0,
      'weight': 1.5,
    },
    {
      'name': 'Samsung Galaxy S22',
      'condition': 'Buen estado',
      'colorCondition': categoryTextYellow,
      'price': 35990.0,
      'weight': 0.18,
    },
  ];

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
              heroHomeViewModelProvider.select((state) => state.selectedNavIndex),
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
              slivers: [
                // 1. Header colapsable
                HeroHeader(
                  onSearchExpandedChanged: (expanded) {
                    setState(() {
                      _isSearchExpanded = expanded;
                    });
                  },
                ),

                // 2. Contenido condicional
                if (_isSearchExpanded)
                  const SliverFillRemaining(child: HeroSearchContent())
                else
                  // Cuerpo desplazable normal
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Material(
                            color: backgroundWhite,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const MyProductsScreen(),
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
                                      blurRadius: 16,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: primaryYellow.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.inventory_2_outlined,
                                        color: textGray900,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Mis productos',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: textGray900,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Administra tus publicaciones y stock',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: textGray600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: textGray600,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: spacingSection),

                      // --- SECCIÓN CATEGORÍAS ---
                      HeroCategoriesSection(categories: _categories),

                      const SizedBox(height: spacingSection),

                      // --- SECCIÓN PRODUCTOS DESTACADOS ---
                      HeroFeaturedProductsSection(products: _products),

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

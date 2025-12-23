import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/hero_header.dart';
import '../widgets/hero_categories_section.dart';
import '../widgets/hero_featured_products_section.dart';
import '../widgets/hero_bottom_nav.dart';
import '../widgets/hero_fab.dart';
import '../viewmodels/hero_home_viewmodel.dart';
import '../../../shared/profile/presentation/views/profile_screen.dart'
    as profile;
import '../../../shared/chat/presentation/views/chat_list_screen.dart' as chat;
import '../../../map/presentation/views/map_location_screen.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;
const double spacingSmall = paddingNormal / 2;
const double spacingSection = paddingNormal / 4;
const double spacingButtonV = paddingNormal * 0.75;
const double spacingButtonH = paddingNormal * 1.25;
const double spacingScreenBottom = paddingLarge * 4;

class HeroHomeScreen extends StatefulWidget {
  const HeroHomeScreen({super.key});

  @override
  State<HeroHomeScreen> createState() => _HeroHomeScreenState();
}

class _HeroHomeScreenState extends State<HeroHomeScreen> {
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
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: backgroundGray50,
        resizeToAvoidBottomInset: false,
        body: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(heroHomeViewModelProvider);
            final selectedIndex = state.selectedNavIndex;

            if (selectedIndex == 4) {
              return const profile.ProfileScreen();
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
                            // --- SECCIÓN PUBLICAR PRODUCTOS ---
                            RepaintBoundary(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final maxWidth = constraints.maxWidth;
                                  final scale =
                                      (maxWidth / 390.0).clamp(0.78, 1.20).toDouble();
                                  final cardHeight =
                                      (maxWidth * 0.52).clamp(170.0, 210.0).toDouble();
                                  final wheelSize =
                                      (maxWidth * 0.88).clamp(210.0, 320.0).toDouble();
                                  final contentRightPadding =
                                      (maxWidth * 0.42).clamp(92.0, 165.0).toDouble();

                                  final cardPadding =
                                      (paddingLarge * scale).clamp(14.0, 24.0).toDouble();
                                  final titleSize = (18.0 * scale).clamp(16.0, 22.0).toDouble();
                                  final subtitleSize =
                                      (14.0 * scale).clamp(12.0, 18.0).toDouble();
                                  final buttonFontSize =
                                      (14.0 * scale).clamp(12.0, 16.0).toDouble();
                                  final buttonIconSize =
                                      (20.0 * scale).clamp(18.0, 22.0).toDouble();
                                  final gapSmall =
                                      (spacingSmall * scale).clamp(6.0, 10.0).toDouble();
                                  final gapNormal =
                                      (paddingNormal * scale).clamp(10.0, 16.0).toDouble();
                                  final buttonHPadding =
                                      (spacingButtonH * scale).clamp(14.0, 20.0).toDouble();
                                  final buttonVPadding =
                                      (spacingButtonV * scale).clamp(10.0, 14.0).toDouble();

                                  final contentAvailableWidth = (maxWidth -
                                          (cardPadding * 2) -
                                          contentRightPadding)
                                      .clamp(120.0, 520.0)
                                      .toDouble();
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          primaryOrange,
                                          primaryYellow.withOpacity(0.95),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: [
                                        BoxShadow(
                                          color: primaryOrange.withOpacity(0.22),
                                          blurRadius: 18,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: SizedBox(
                                        height: cardHeight,
                                        child: Stack(
                                          clipBehavior: Clip.hardEdge,
                                          children: [
                                            Positioned(
                                              right: -wheelSize * 0.22,
                                              bottom: -wheelSize * 0.26,
                                              child: IgnorePointer(
                                                child: Opacity(
                                                  opacity: 0.95,
                                                  child: Transform.rotate(
                                                    angle: -0.22,
                                                    child: Image.asset(
                                                      'assets/wheel.png',
                                                      width: wheelSize,
                                                      height: wheelSize,
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(cardPadding),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Padding(
                                                      padding: EdgeInsets.only(
                                                        right: contentRightPadding,
                                                      ),
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment.centerLeft,
                                                        child: SizedBox(
                                                          width: contentAvailableWidth,
                                                          child: Column(
                                                            mainAxisSize: MainAxisSize.min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                '¿Tienes algo para vender?',
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: TextStyle(
                                                                  color: backgroundWhite,
                                                                  fontSize: titleSize,
                                                                  fontWeight:
                                                                      FontWeight.bold,
                                                                ),
                                                              ),
                                                              SizedBox(height: gapSmall),
                                                              Text(
                                                                'Publica tus productos y vende fácilmente',
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: TextStyle(
                                                                  color: backgroundWhite
                                                                      .withOpacity(0.92),
                                                                  fontSize: subtitleSize,
                                                                ),
                                                              ),
                                                              SizedBox(height: gapNormal),
                                                              ElevatedButton.icon(
                                                                onPressed: () {
                                                                  debugPrint(
                                                                    'Navegando a publicar producto',
                                                                  );
                                                                },
                                                                icon: Icon(
                                                                  Icons.add_circle_outline,
                                                                  color: primaryOrange,
                                                                  size: buttonIconSize,
                                                                ),
                                                                label: Text(
                                                                  'Publicar ahora',
                                                                  style: TextStyle(
                                                                    color: primaryOrange,
                                                                    fontSize:
                                                                        buttonFontSize,
                                                                    fontWeight:
                                                                        FontWeight.w600,
                                                                  ),
                                                                ),
                                                                style: ElevatedButton
                                                                    .styleFrom(
                                                                  backgroundColor:
                                                                      backgroundWhite,
                                                                  padding:
                                                                      EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        buttonHPadding,
                                                                    vertical:
                                                                        buttonVPadding,
                                                                  ),
                                                                  shape:
                                                                      RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: paddingNormal),
                          ],
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
        floatingActionButton: _isSearchExpanded ? null : const HeroFAB(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }
}

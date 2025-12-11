import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/hero_animated_card.dart';
import '../widgets/hero_header.dart';
import '../widgets/hero_categories_section.dart';
import '../widgets/hero_featured_products_section.dart';
import '../widgets/hero_bottom_nav.dart';
import '../widgets/hero_fab.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

class HeroHomeScreen extends StatefulWidget {
  const HeroHomeScreen({super.key});

  @override
  State<HeroHomeScreen> createState() => _HeroHomeScreenState();
}

class _HeroHomeScreenState extends State<HeroHomeScreen> {
  final List<Map<String, dynamic>> _categories = [
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
      'bgColor': categoryBgBlue.withOpacity(0.5),
    },
    {
      'label': 'Muebles Grandes',
      'icon': Icons.weekend,
      'iconColor': categoryTextGreen,
      'bgColor': categoryBgGreen.withOpacity(0.5),
    },
    {
      'label': 'Instrumentos Musicales',
      'icon': Icons.music_note,
      'iconColor': categoryTextPink,
      'bgColor': categoryBgPink.withOpacity(0.5),
    },
    {
      'label': 'Juguetes',
      'icon': Icons.toys,
      'iconColor': primaryOrange,
      'bgColor': primaryOrange.withOpacity(0.2),
    },
  ];

  // Lista de productos destacados
  final List<Map<String, dynamic>> _products = [
    {
      'name': 'iPhone 13 Pro',
      'condition': 'Excelente estado',
      'colorCondition': categoryTextGreen,
    },
    {
      'name': 'MacBook Air M1',
      'condition': 'Como nuevo',
      'colorCondition': categoryTextGreen,
    },
    {
      'name': 'Samsung Galaxy S22',
      'condition': 'Buen estado',
      'colorCondition': categoryTextYellow,
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

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: CustomScrollView(
        slivers: [
          // 1. Header colapsable
          HeroHeader(),

          // 2. Cuerpo desplazable
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: paddingNormal),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: paddingNormal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // --- SECCIÓN HÉROE / ENCUENTRA ---
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AnimatedHeroCard(
                            title: 'Sé un Héroe',
                            subtitle: 'Dóna tus productos',
                            icon: Icons.volunteer_activism_outlined,
                            onTap: () {
                              debugPrint(
                                'Tap en Sé un Héroe: ¡Navegando a donación!',
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: paddingNormal),
                        Expanded(
                          child: AnimatedHeroCard(
                            title: 'Encuentra',
                            subtitle: 'Busca donaciones',
                            icon: Icons.search,
                            onTap: () {
                              debugPrint(
                                'Tap en Encuentra: ¡Navegando a búsqueda!',
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // --- SECCIÓN CATEGORÍAS ---
              HeroCategoriesSection(categories: _categories),

              // --- SECCIÓN PRODUCTOS DESTACADOS ---
              HeroFeaturedProductsSection(products: _products),

              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),

      // 3. Navegación Inferior y FAB
      bottomNavigationBar: const HeroBottomNav(),
      floatingActionButton: const HeroFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

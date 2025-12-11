import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import 'product_card.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

class HeroFeaturedProductsSection extends StatelessWidget {
  final List<Map<String, dynamic>> products;

  const HeroFeaturedProductsSection({
    super.key,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: paddingLarge),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: paddingLarge),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Productos Destacados',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Los más buscados esta semana',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textGray600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Ver todos',
                  style: TextStyle(
                    fontSize: 12,
                    color: primaryOrange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: paddingLarge),
        ...products.map((product) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: paddingLarge, vertical: paddingNormal),
            child: ProductCard(
              name: product['name'],
              condition: product['condition'],
              colorCondition: product['colorCondition'],
            ),
          );
        }).toList(),
      ],
    );
  }
}

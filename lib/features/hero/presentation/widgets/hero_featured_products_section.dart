import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import 'product_card.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

class HeroFeaturedProductsSection extends StatelessWidget {
  final List<Map<String, dynamic>> products;

  const HeroFeaturedProductsSection({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: paddingLarge),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Productos Destacados',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: textGray900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Los más buscados esta semana',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textGray600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: paddingLarge),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: paddingNormal),
          child: Container(
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
              children: [
                ...products.asMap().entries.map((entry) {
                  final index = entry.key;
                  final product = entry.value;
                  final isLast = index == products.length - 1;
                  final price = (product['price'] as double?) ?? 45990.0;
                  final weight = (product['weight'] as double?) ?? 0.5;
                  return Column(
                    children: [
                      RepaintBoundary(
                        key: ValueKey('product_$index'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: paddingNormal,
                            vertical: 0,
                          ),
                          child: ProductCard(
                            name: product['name'],
                            condition: product['condition'],
                            colorCondition: product['colorCondition'],
                            price: price,
                            weight: weight,
                            showShadow: false,
                          ),
                        ),
                      ),
                      if (!isLast)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: borderGray100,
                          indent: paddingNormal,
                          endIndent: paddingNormal,
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

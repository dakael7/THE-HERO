import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../cart/cart_provider.dart';

const double paddingNormal = 16.0;

class ProductCard extends ConsumerWidget {
  final String name;
  final String condition;
  final Color colorCondition;
  final double price;
  final double weight;

  const ProductCard({
    super.key,
    required this.name,
    required this.condition,
    required this.colorCondition,
    required this.price,
    this.weight = 0.5,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Optimización: RepaintBoundary para evitar repintados innecesarios
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = ResponsiveUtils.isMobile(context);
          final maxWidth = constraints.maxWidth;
          final rawImageSize = isMobile ? maxWidth * 0.28 : maxWidth * 0.22;
          final imageSize = rawImageSize.clamp(100.0, 200.0);
          final padding = ResponsiveUtils.responsivePadding(
            context,
            mobilePadding: paddingNormal,
            tabletPadding: 20.0,
            desktopPadding: 24.0,
          );
          final nameFontSize = ResponsiveUtils.responsiveFontSize(
            context,
            mobileSize: 16,
            tabletSize: 17,
            desktopSize: 18,
          );
          final priceFontSize = ResponsiveUtils.responsiveFontSize(
            context,
            mobileSize: 18,
            tabletSize: 20,
            desktopSize: 22,
          );
          final conditionFontSize = ResponsiveUtils.responsiveFontSize(
            context,
            mobileSize: 10,
            tabletSize: 11,
            desktopSize: 12,
          );
          final conditionPadding = ResponsiveUtils.responsivePadding(
            context,
            mobilePadding: 8.0,
            tabletPadding: 9.0,
            desktopPadding: 10.0,
          );

          return Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: textGray900.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: primaryOrange.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    color: borderGray100,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: textGray900.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.image, color: textGray600, size: 48),
                  ),
                ),
                SizedBox(width: padding),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: nameFontSize,
                          fontWeight: FontWeight.w700,
                          color: textGray900,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: padding * 0.4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 14,
                            color: textGray600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Publicado por: Juan Pérez',
                              style: const TextStyle(
                                fontSize: 12,
                                color: textGray600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: padding * 0.5),
                      Text(
                        '\$${price.toStringAsFixed(0)} CLP',
                        style: TextStyle(
                          fontSize: priceFontSize,
                          fontWeight: FontWeight.w800,
                          color: primaryOrange,
                        ),
                      ),
                      SizedBox(height: padding * 0.5),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  size: 16,
                                  color: Color(0xFFFFB800),
                                ),
                                const SizedBox(width: 3),
                                const Text(
                                  '4.8',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textGray900,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '(234 vendidos)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textGray600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: conditionPadding,
                              vertical: conditionPadding * 0.5,
                            ),
                            decoration: BoxDecoration(
                              color: colorCondition.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              condition,
                              style: TextStyle(
                                fontSize: conditionFontSize,
                                fontWeight: FontWeight.w600,
                                color: colorCondition,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: padding * 0.6),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: () {
                            ref
                                .read(cartProvider.notifier)
                                .addItem(
                                  name: name,
                                  condition: condition,
                                  price: price,
                                  weight: weight,
                                );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: padding * 0.9,
                              vertical: padding * 0.6,
                            ),
                            decoration: BoxDecoration(
                              color: primaryOrange,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryOrange.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Agregar al carrito',
                              style: TextStyle(
                                color: backgroundWhite,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

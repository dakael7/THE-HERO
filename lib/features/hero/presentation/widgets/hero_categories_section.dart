import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

/// Widget de la sección de categorías
class HeroCategoriesSection extends StatelessWidget {
  final List<Map<String, dynamic>> categories;

  const HeroCategoriesSection({super.key, required this.categories});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: paddingLarge),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: paddingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Explora Categorías',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Encuentra lo que buscas en nuestras categorías',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textGray600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: paddingLarge),
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = ResponsiveUtils.isMobile(context);
            final categoryHeight = isMobile ? 140.0 : 160.0;
            final categoryWidth = isMobile ? 100.0 : 120.0;

            // Optimización: itemExtent mejora el rendimiento del scroll
            return SizedBox(
              height: categoryHeight,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: paddingLarge),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemExtent: categoryWidth + 16, // width + padding
                itemBuilder: (context, index) {
                  final category = categories[index];
                  // Optimización: RepaintBoundary para cada item
                  return RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _buildCategoryItem(
                        label: category['label'],
                        icon: category['icon'],
                        iconColor: category['iconColor'],
                        bgColor: category['bgColor'],
                        width: categoryWidth,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCategoryItem({
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required double width,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        splashColor: primaryOrange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(100),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    color: primaryOrange.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: primaryOrange, size: 36),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: textGray900,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

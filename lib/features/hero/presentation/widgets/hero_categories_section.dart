import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

/// Widget de la sección de categorías
class HeroCategoriesSection extends StatelessWidget {
  final List<Map<String, dynamic>> categories;

  const HeroCategoriesSection({
    super.key,
    required this.categories,
  });

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
            
            return SizedBox(
              height: categoryHeight,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: paddingLarge),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _buildCategoryItem(
                      label: category['label'],
                      icon: category['icon'],
                      iconColor: category['iconColor'],
                      bgColor: category['bgColor'],
                      width: categoryWidth,
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
        splashColor: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: iconColor.withOpacity(0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: iconColor, size: 30),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textGray900,
                      height: 1.2,
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

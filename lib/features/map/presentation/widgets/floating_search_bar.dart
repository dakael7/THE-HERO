import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class FloatingSearchBar extends StatelessWidget {
  final int productCount;
  final VoidCallback? onFilterTap;
  final VoidCallback? onSearchTap;

  const FloatingSearchBar({
    super.key,
    required this.productCount,
    this.onFilterTap,
    this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSearchTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.search,
                    color: primaryOrange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Buscar productos',
                        style: TextStyle(
                          color: textGray900,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$productCount productos cercanos',
                        style: const TextStyle(
                          color: textGray600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onFilterTap != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primaryYellow.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.tune,
                        color: textGray900,
                        size: 22,
                      ),
                      onPressed: onFilterTap,
                      padding: EdgeInsets.zero,
                      splashRadius: 22,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

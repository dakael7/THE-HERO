import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../cart/cart_provider.dart';
import '../../cart/hero_cart_screen.dart';

/// Widget del botón flotante (FAB) con carrito
class HeroFAB extends ConsumerWidget {
  const HeroFAB({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final itemCount = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final isMobile = ResponsiveUtils.isMobile(context);
    final fabSize = isMobile ? 70.0 : 80.0;
    final fabHeight = isMobile ? 80.0 : 90.0;
    final yOffset = isMobile ? 40.0 : 45.0;
    final iconSize = isMobile ? 32.0 : 38.0;

    return Transform.translate(
      offset: Offset(0, yOffset),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const HeroCartScreen(),
            ),
          );
        },
        child: Container(
          width: fabSize,
          height: fabHeight,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryOrange.withOpacity(0.2),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryOrange,
              boxShadow: [
                BoxShadow(
                  color: primaryOrange.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  color: backgroundWhite,
                  size: iconSize,
                ),
                if (itemCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: backgroundWhite,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$itemCount',
                        style: const TextStyle(
                          color: primaryOrange,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
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

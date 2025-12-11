import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../viewmodels/hero_home_viewmodel.dart';

/// Widget del botón flotante (FAB) con carrito
class HeroFAB extends ConsumerWidget {
  const HeroFAB({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = ref.read(heroHomeViewModelProvider.notifier);
    final isMobile = ResponsiveUtils.isMobile(context);
    final fabSize = isMobile ? 60.0 : 70.0;
    final fabHeight = isMobile ? 70.0 : 80.0;
    final yOffset = isMobile ? 35.0 : 40.0;
    final iconSize = isMobile ? 30.0 : 34.0;

    return Transform.translate(
      offset: Offset(0, yOffset),
      child: Container(
        width: fabSize,
        height: fabHeight,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primaryOrange.withOpacity(0.2),
        ),
        child: FloatingActionButton(
          onPressed: () => viewModel.selectNavItem(2),
          backgroundColor: primaryOrange,
          elevation: 4,
          shape: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                color: backgroundWhite,
                size: iconSize,
              ),
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
                  child: const Text(
                    '2',
                    style: TextStyle(
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
    );
  }
}

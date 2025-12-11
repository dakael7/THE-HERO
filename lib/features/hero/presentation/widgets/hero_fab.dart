import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../viewmodels/hero_home_viewmodel.dart';

/// Widget del botón flotante (FAB) con carrito
class HeroFAB extends ConsumerWidget {
  const HeroFAB({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = ref.read(heroHomeViewModelProvider.notifier);

    return Transform.translate(
      offset: const Offset(0, 35.0),
      child: Container(
        width: 60,
        height: 70,
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
              const Icon(
                Icons.shopping_cart_outlined,
                color: backgroundWhite,
                size: 30,
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

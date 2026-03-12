import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../cart/cart_item.dart';
import '../../cart/cart_provider.dart';
import '../../cart/hero_cart_screen.dart';

class HeroFAB extends ConsumerStatefulWidget {
  const HeroFAB({super.key});

  @override
  ConsumerState<HeroFAB> createState() => _HeroFABState();
}

class _HeroFABState extends ConsumerState<HeroFAB>
    with TickerProviderStateMixin {
  late final AnimationController _bumpController;
  late final AnimationController _badgeController;

  late final ProviderSubscription<List<CartItem>> _cartSubscription;

  late final Animation<double> _bumpScale;
  late final Animation<double> _badgeScale;

  @override
  void initState() {
    super.initState();

    _bumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _bumpScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.10)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.10, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 45,
      ),
    ]).animate(_bumpController);

    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.25)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.25, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 40,
      ),
    ]).animate(_badgeController);

    _cartSubscription = ref.listenManual<List<CartItem>>(
      cartProvider,
      (previous, next) {
        final prevCount = (previous ?? const <CartItem>[])
            .fold<int>(0, (sum, item) => sum + item.quantity);
        final nextCount =
            next.fold<int>(0, (sum, item) => sum + item.quantity);

        if (nextCount > prevCount) {
          _bumpController.forward(from: 0);
          _badgeController.forward(from: 0);
        }
      },
    );
  }

  @override
  void dispose() {
    _cartSubscription.close();
    _bumpController.dispose();
    _badgeController.dispose();
    super.dispose();
  }

  void _navigateToCart() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const HeroCartScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = ref.watch(
      cartProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );
    final isMobile = ResponsiveUtils.isMobile(context);
    final fabSize = isMobile ? 74.0 : 86.0;
    final iconSize = isMobile ? 34.0 : 40.0;

    // ✅ FIX: Sin Transform.translate — desplazaba visualmente el FAB
    // pero el hit-test quedaba en la posición original, rompiendo los toques.
    // El Scaffold con centerFloat posiciona el FAB correctamente.
    return ScaleTransition(
      scale: _bumpScale,
      child: SizedBox(
        width: fabSize,
        height: fabSize,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _navigateToCart,
            borderRadius: BorderRadius.circular(fabSize / 2),
            splashColor: Colors.white.withValues(alpha: 0.2),
            highlightColor: Colors.white.withValues(alpha: 0.1),
            child: IgnorePointer(
              child: Container(
                width: fabSize,
                height: fabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryOrange.withValues(alpha: 0.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryOrange,
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: iconSize * 2,
                            height: iconSize * 2,
                            child: Image.asset(
                              'assets/wheel.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          if (itemCount > 0)
                            Positioned(
                              right: -2,
                              top: -4,
                              child: ScaleTransition(
                                scale: _badgeScale,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: backgroundWhite,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  child: Text(
                                    itemCount.toString(),
                                    style: const TextStyle(
                                      color: primaryOrange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../../../../hero/cart/cart_provider.dart';
import '../../../../hero/cart/hero_cart_sheet.dart';

class MyProductsScreen extends ConsumerWidget {
  const MyProductsScreen({super.key});

  Future<void> _openCartSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HeroCartSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final itemCount = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
          },
        ),
        title: const Text(
          'Mis productos',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Carrito',
              onPressed: () => _openCartSheet(context),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_cart_outlined),
                  if (itemCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: primaryOrange,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          itemCount.toString(),
                          style: const TextStyle(
                            color: backgroundWhite,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- HERO CONTAINER SECTION ---
            Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final scale = (maxWidth / 390.0).clamp(0.78, 1.20).toDouble();
                  final cardHeight = (maxWidth * 0.52)
                      .clamp(170.0, 210.0)
                      .toDouble();
                  final wheelSize = (maxWidth * 0.88)
                      .clamp(210.0, 320.0)
                      .toDouble();
                  final contentRightPadding = (maxWidth * 0.42)
                      .clamp(92.0, 165.0)
                      .toDouble();

                  final cardPadding = (24.0 * scale)
                      .clamp(14.0, 24.0)
                      .toDouble();
                  final titleSize = (18.0 * scale).clamp(16.0, 22.0).toDouble();
                  final subtitleSize = (14.0 * scale)
                      .clamp(12.0, 18.0)
                      .toDouble();
                  final buttonFontSize = (14.0 * scale)
                      .clamp(12.0, 16.0)
                      .toDouble();
                  final buttonIconSize = (20.0 * scale)
                      .clamp(18.0, 22.0)
                      .toDouble();
                  final gapSmall = (8.0 * scale).clamp(6.0, 10.0).toDouble();
                  final gapNormal = (16.0 * scale).clamp(10.0, 16.0).toDouble();
                  final buttonHPadding = (20.0 * scale)
                      .clamp(14.0, 20.0)
                      .toDouble();
                  final buttonVPadding = (12.0 * scale)
                      .clamp(10.0, 14.0)
                      .toDouble();

                  final contentAvailableWidth =
                      (maxWidth - (cardPadding * 2) - contentRightPadding)
                          .clamp(120.0, 520.0)
                          .toDouble();

                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          primaryOrange,
                          primaryYellow.withOpacity(0.95),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withOpacity(0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        height: cardHeight,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned(
                              right: -wheelSize * 0.22,
                              bottom: -wheelSize * 0.26,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: 0.95,
                                  child: Transform.rotate(
                                    angle: -0.22,
                                    child: Image.asset(
                                      'assets/wheel.png',
                                      width: wheelSize,
                                      height: wheelSize,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(cardPadding),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: contentRightPadding,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: SizedBox(
                                          width: contentAvailableWidth,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '¿Tienes algo para vender?',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: backgroundWhite,
                                                  fontSize: titleSize,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: gapSmall),
                                              Text(
                                                'Publica tus productos y vende fácilmente',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: backgroundWhite
                                                      .withOpacity(0.92),
                                                  fontSize: subtitleSize,
                                                ),
                                              ),
                                              SizedBox(height: gapNormal),
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Publicación de productos próximamente',
                                                      ),
                                                      duration: Duration(
                                                        milliseconds: 1600,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: Icon(
                                                  Icons.add_circle_outline,
                                                  color: primaryOrange,
                                                  size: buttonIconSize,
                                                ),
                                                label: Text(
                                                  'Publicar ahora',
                                                  style: TextStyle(
                                                    color: primaryOrange,
                                                    fontSize: buttonFontSize,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      backgroundWhite,
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: buttonHPadding,
                                                    vertical: buttonVPadding,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // --- PRODUCTOS PUBLICADOS ---
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: primaryOrange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      size: 34,
                      color: primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Aún no tienes productos publicados',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cuando publiques un producto, aparecerá aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textGray600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

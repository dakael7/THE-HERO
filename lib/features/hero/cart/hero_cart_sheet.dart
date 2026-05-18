import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../shared/profile/presentation/providers/profile_provider.dart';
import 'cart_item.dart';
import 'cart_provider.dart';
import 'checkout_screen.dart';

class HeroCartSheet extends ConsumerWidget {
  const HeroCartSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final totalItems = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.18,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: backgroundWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: borderGray100,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_cart_outlined,
                        color: textGray900,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Mi carrito',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: textGray900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$totalItems artículo${totalItems == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textGray600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: textGray700),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: cartItems.isEmpty
                      ? ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(24),
                          children: const [
                            SizedBox(height: 16),
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 64,
                              color: textGray600,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Tu carrito está vacío',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Agrega productos desde la pantalla principal para verlos aquí.',
                              style: TextStyle(
                                fontSize: 14,
                                color: textGray600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: cartItems.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = cartItems[index];
                            return _CartItemTile(item: item);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: textGray900.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: borderGray100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.image, color: textGray600, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: textGray900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.condition,
                      style: const TextStyle(fontSize: 14, color: textGray600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                color: textGray600,
                onPressed: () {
                  ref.read(cartProvider.notifier).removeItem(item);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 24),
                color: textGray600,
                onPressed: () {
                  ref.read(cartProvider.notifier).removeOne(item);
                },
              ),
              Text(
                '${item.quantity}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: textGray900,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 24),
                color: primaryOrange,
                onPressed: () {
                  ref
                      .read(cartProvider.notifier)
                      .addItem(
                        offerId: item.offerId,
                        category: item.category,
                        name: item.name,
                        condition: item.condition,
                        price: item.price,
                        imageUrl: item.imageUrl,
                        availableQty: item.availableQty,
                        weight: item.weight,
                        pickupGeo: item.pickupGeo,
                        pickupCountryCode: item.pickupCountryCode,
                        sellerHeroId: item.sellerHeroId,
                        allowInPersonPickup: item.allowInPersonPickup,
                      );
                },
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: backgroundWhite,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final user = ref.read(profileProvider).maybeWhen(
                        data: (u) => u,
                        orElse: () => null,
                      );
                  if (user != null && user.isSuspended) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Tu cuenta está suspendida. No puedes proceder al pago en este momento.',
                        ),
                        duration: Duration(seconds: 4),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CheckoutScreen(item: item),
                    ),
                  );
                },
                child: const Text(
                  'Pagar servicio',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

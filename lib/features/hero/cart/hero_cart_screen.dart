import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/weight_utils.dart';
import 'cart_provider.dart';
import 'cart_item.dart';
import 'checkout_screen.dart';

class HeroCartScreen extends ConsumerWidget {
  const HeroCartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final totalItems = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.shopping_bag_outlined, color: textGray900),
            const SizedBox(width: 8),
            const Text(
              'Mi carrito',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: backgroundWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$totalItems artículo${totalItems == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                ),
              ),
            ),
          ],
        ),
      ),
      body: cartItems.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cartItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      return _CartItemTile(item: item);
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 4,
                      bottom: 12,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 18,
                          offset: Offset(0, -6),
                        ),
                      ],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryOrange,
                              foregroundColor: backgroundWhite,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 4,
                              shadowColor: primaryOrange.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CheckoutScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Proceder al pago',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircleAvatar(
              radius: 42,
              backgroundColor: Color(0xFFFFF2E5),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 40,
                color: primaryOrange,
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Tu carrito está vacío',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Explora productos y agrega los que te interesen para verlos aquí.',
              style: TextStyle(fontSize: 14, color: textGray600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = item.imageUrl.trim();
    final isAsset = image.startsWith('assets/');
    final hasImage = image.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: textGray900.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 66,
              height: 66,
              color: borderGray100,
              child: !hasImage
                  ? const Icon(Icons.image, color: textGray600)
                  : isAsset
                  ? Image.asset(image, fit: BoxFit.cover)
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image, color: textGray600),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: textGray900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.condition,
                  style: const TextStyle(fontSize: 13, color: textGray600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: borderGray100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '\$${_formatPriceCLP(item.price)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: textGray900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatWeightKg(item.weight),
                      style: const TextStyle(fontSize: 12, color: textGray600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QtyButton(
                    icon: Icons.remove,
                    color: textGray600,
                    onTap: () =>
                        ref.read(cartProvider.notifier).removeOne(item),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: textGray900,
                      ),
                    ),
                  ),
                  _QtyButton(
                    icon: Icons.add,
                    color: primaryOrange,
                    onTap: () => ref
                        .read(cartProvider.notifier)
                        .addItem(
                          offerId: item.offerId,
                          name: item.name,
                          condition: item.condition,
                          price: item.price,
                          weight: item.weight,
                          imageUrl: item.imageUrl,
                          availableQty: item.availableQty,
                          pickupGeo: item.pickupGeo,
                          pickupCountryCode: item.pickupCountryCode,
                          sellerHeroId: item.sellerHeroId,
                          allowInPersonPickup: item.allowInPersonPickup,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: textGray600,
                onPressed: () =>
                    ref.read(cartProvider.notifier).removeItem(item),
                tooltip: 'Eliminar',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QtyButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

String _formatPriceCLP(double value) {
  final negative = value < 0;
  final abs = value.abs();

  final rounded = abs.round().toString();
  final groupedInt = _groupThousands(rounded);
  final sign = negative ? '-' : '';
  return '$sign$groupedInt';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }
  return buffer.toString();
}

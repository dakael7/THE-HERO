import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import 'cart_item.dart';
import 'cart_provider.dart';
import 'cart_summary_provider.dart';

class HeroCartSheet extends ConsumerWidget {
  const HeroCartSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final summary = ref.watch(cartSummaryProvider);
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
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = cartItems[index];
                            return _CartItemTile(item: item);
                          },
                        ),
                ),
                if (cartItems.isNotEmpty)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 10,
                        bottom: 12,
                      ),
                      decoration: const BoxDecoration(
                        color: backgroundWhite,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 12,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resumen de pago',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: textGray900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildSummaryRow(
                            'Subtotal (Donación):',
                            '\$${summary.subtotal.toStringAsFixed(0)}',
                            fontSize: 13,
                          ),
                          const SizedBox(height: 10),
                          _buildSummaryRow(
                            'Envío (Bicicleta):',
                            '\$${summary.shippingCost.toStringAsFixed(0)}',
                            fontSize: 13,
                          ),
                          const SizedBox(height: 10),
                          _buildSummaryRow(
                            'Comisión de servicio:',
                            '\$${summary.serviceFee.toStringAsFixed(0)}',
                            fontSize: 13,
                          ),
                          const SizedBox(height: 10),
                          _buildSummaryRow(
                            'Impuestos (IVA 19%):',
                            '\$${summary.tax.toStringAsFixed(0)}',
                            fontSize: 13,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Container(
                              height: 1,
                              color: borderGray100,
                            ),
                          ),
                          _buildSummaryRow(
                            'Total:',
                            '\$${summary.total.toStringAsFixed(0)}',
                            isBold: true,
                            fontSize: 17,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '* Peso total: ${summary.totalWeight.toStringAsFixed(2)} kg',
                            style: TextStyle(
                              fontSize: 11,
                              color: textGray600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryOrange,
                                foregroundColor: backgroundWhite,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                elevation: 4,
                                shadowColor: primaryOrange.withOpacity(0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Flujo de pago aún no implementado'),
                                    duration: Duration(milliseconds: 1800),
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
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 14,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: textGray900,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: textGray900,
          ),
        ),
      ],
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
            color: textGray900.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: borderGray100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.image,
            color: textGray600,
            size: 28,
          ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: textGray900,
          ),
        ),
        subtitle: Text(
          item.condition,
          style: const TextStyle(
            fontSize: 14,
            color: textGray600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
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
                ref.read(cartProvider.notifier).addItem(
                      name: item.name,
                      condition: item.condition,
                      price: item.price,
                      weight: item.weight,
                    );
              },
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
      ),
    );
  }
}

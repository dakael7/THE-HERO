import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import 'cart_provider.dart';
import 'cart_item.dart';

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
        title: const Text(
          'Mi carrito',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$totalItems artículo${totalItems == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textGray900,
                ),
              ),
            ),
          ),
        ],
      ),
      body: cartItems.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cartItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      return _CartItemTile(item: item);
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 12),
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
                      const SizedBox(height: 16),
                      _buildSummaryRow('Subtotal (Donación):', '\$0', fontSize: 13),
                      const SizedBox(height: 10),
                      _buildSummaryRow('Envío (Bicicleta):', '\$1.500', fontSize: 13),
                      const SizedBox(height: 10),
                      _buildSummaryRow('Comisión de servicio:', '\$2.000', fontSize: 13),
                      const SizedBox(height: 10),
                      _buildSummaryRow('Impuestos (IVA 19%):', '\$665', fontSize: 13),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          height: 1,
                          color: borderGray100,
                        ),
                      ),
                      _buildSummaryRow(
                        'Total:',
                        '\$4.165',
                        isBold: true,
                        fontSize: 17,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '* Peso total: 0.20 kg',
                        style: TextStyle(
                          fontSize: 11,
                          color: textGray600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryOrange,
                            foregroundColor: backgroundWhite,
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, double fontSize = 14}) {
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.shopping_cart_outlined,
              size: 72,
              color: textGray600,
            ),
            SizedBox(height: 16),
            Text(
              'Tu carrito está vacío',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
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
                ref
                    .read(cartProvider.notifier)
                    .addItem(name: item.name, condition: item.condition);
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

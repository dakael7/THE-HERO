import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

enum PaymentMethod { mercadopago, cash }

/// Widget to select payment method
class PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod selectedMethod;
  final ValueChanged<PaymentMethod> onMethodChanged;

  const PaymentMethodSelector({
    super.key,
    required this.selectedMethod,
    required this.onMethodChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Método de pago',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: textGray900,
          ),
        ),
        const SizedBox(height: 12),

        // MercadoPago option
        _PaymentMethodCard(
          icon: Icons.credit_card,
          title: 'Pago en línea',
          subtitle: 'Tarjeta de crédito o débito',
          isSelected: selectedMethod == PaymentMethod.mercadopago,
          onTap: () => onMethodChanged(PaymentMethod.mercadopago),
          badge: 'Recomendado',
        ),
        const SizedBox(height: 12),

        // Cash option
        _PaymentMethodCard(
          icon: Icons.payments_outlined,
          title: 'Pago en efectivo',
          subtitle: 'Paga al rider al recibir',
          isSelected: selectedMethod == PaymentMethod.cash,
          onTap: () => onMethodChanged(PaymentMethod.cash),
        ),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;

  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primaryYellow.withOpacity(0.1) : backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryOrange : borderGray100,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryOrange.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryOrange.withOpacity(0.1)
                    : backgroundGray50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? primaryOrange : textGray600,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? textGray900 : textGray700,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryOrange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: backgroundWhite,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textGray600,
                    ),
                  ),
                ],
              ),
            ),

            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? primaryOrange : borderGray100,
                  width: 2,
                ),
                color: isSelected ? primaryOrange : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: backgroundWhite)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

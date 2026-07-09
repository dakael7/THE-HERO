import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/repository_providers.dart';
import '../../../domain/entities/offer.dart';
import '../../../domain/entities/offer_status.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_status.dart';
import '../../shared/profile/presentation/providers/profile_provider.dart';
import '../../shared/profile/presentation/views/donation_questions_screen.dart';

const int cartBaseMonthlyOrderLimit = 3;
const int cartOrdersPerMonthlyDonation = 3;

int cartMonthlyOrderLimitForDonations(int donationCount) {
  final safeDonationCount = donationCount < 0 ? 0 : donationCount;
  return cartBaseMonthlyOrderLimit +
      (safeDonationCount * cartOrdersPerMonthlyDonation);
}

class CartMonthlyAllowance {
  const CartMonthlyAllowance({
    required this.ordersUsed,
    required this.donationsUploaded,
    required this.orderLimit,
  });

  final int ordersUsed;
  final int donationsUploaded;
  final int orderLimit;

  int get remainingOrders {
    final remaining = orderLimit - ordersUsed;
    return remaining < 0 ? 0 : remaining;
  }

  bool get canAddToCart => remainingOrders > 0;
}

final cartMonthlyAllowanceProvider = FutureProvider.autoDispose
    .family<CartMonthlyAllowance, String>((ref, userId) async {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month);
      final nextMonthStart = DateTime(now.year, now.month + 1);

      final ordersRepository = ref.read(ordersRepositoryProvider);
      final offersRepository = ref.read(offersRepositoryProvider);

      final orders = await ordersRepository.getOrdersByHero(userId).first;
      final offers = await offersRepository.getOffersByHero(userId).first;

      final ordersUsed = orders
          .where(
            (order) =>
                _isInMonth(
                  order.timestamps.createdAt,
                  monthStart,
                  nextMonthStart,
                ) &&
                _countsAsMonthlyOrder(order),
          )
          .length;
      final donationsUploaded = offers
          .where(
            (offer) =>
                _isInMonth(offer.createdAt, monthStart, nextMonthStart) &&
                _countsAsMonthlyDonation(offer),
          )
          .length;

      return CartMonthlyAllowance(
        ordersUsed: ordersUsed,
        donationsUploaded: donationsUploaded,
        orderLimit: cartMonthlyOrderLimitForDonations(donationsUploaded),
      );
    });

Future<bool> ensureCanAddItemToCart({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final userId = ref.read(currentUserIdProvider)?.trim();
  if (userId == null || userId.isEmpty) return true;

  try {
    ref.invalidate(cartMonthlyAllowanceProvider(userId));
    final allowance = await ref.read(
      cartMonthlyAllowanceProvider(userId).future,
    );
    if (allowance.canAddToCart) return true;
    if (!context.mounted) return false;

    final goToDonation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Limite mensual alcanzado'),
          content: Text(
            'Puedes hacer $cartBaseMonthlyOrderLimit pedidos al mes. '
            'Ya usaste ${allowance.ordersUsed} de ${allowance.orderLimit}. '
            'Sube un articulo para donar y se habilitaran '
            '$cartOrdersPerMonthlyDonation pedidos mas este mes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Donar articulo'),
            ),
          ],
        );
      },
    );

    if (goToDonation == true && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DonationQuestionsScreen()),
      );
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos validar tu limite mensual de pedidos.'),
        ),
      );
    }
    return false;
  }
}

bool _isInMonth(DateTime date, DateTime monthStart, DateTime nextMonthStart) {
  return !date.isBefore(monthStart) && date.isBefore(nextMonthStart);
}

bool _countsAsMonthlyOrder(Order order) {
  switch (order.status) {
    case OrderStatus.pendingPayment:
    case OrderStatus.paid:
    case OrderStatus.queued:
    case OrderStatus.assigned:
    case OrderStatus.pickedUp:
    case OrderStatus.inTransit:
    case OrderStatus.delivered:
      return true;
    case OrderStatus.created:
    case OrderStatus.canceled:
    case OrderStatus.failed:
      return false;
  }
}

bool _countsAsMonthlyDonation(Offer offer) {
  return offer.status != OfferStatus.draft &&
      offer.status != OfferStatus.archived;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/repository_providers.dart';
import '../../../domain/entities/offer.dart';
import '../../../domain/entities/offer_status.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_status.dart';
import '../../shared/profile/presentation/providers/profile_provider.dart';
import '../../shared/profile/presentation/views/donation_questions_screen.dart';

const int cartWeeklyOrderLimit = 3;
const int cartOrdersPerWeeklyDonation = 3;

class CartWeeklyAllowance {
  const CartWeeklyAllowance({
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

final cartWeeklyAllowanceProvider = FutureProvider.autoDispose
    .family<CartWeeklyAllowance, String>((ref, userId) async {
      final now = DateTime.now();
      final weekStart = _startOfIsoWeek(now);
      final nextWeekStart = weekStart.add(const Duration(days: 7));

      final ordersRepository = ref.read(ordersRepositoryProvider);
      final offersRepository = ref.read(offersRepositoryProvider);
      final orders = await ordersRepository.getOrdersByHero(userId).first;
      final offers = await offersRepository.getOffersByHero(userId).first;

      final ordersUsed = orders
          .where(
            (order) =>
                _isInWeek(
                  order.timestamps.createdAt,
                  weekStart,
                  nextWeekStart,
                ) &&
                _countsAsWeeklyOrder(order),
          )
          .length;
      final donationsUploaded = offers
          .where(
            (offer) =>
                _isInWeek(
                  offer.publishedAt ?? offer.createdAt,
                  weekStart,
                  nextWeekStart,
                ) &&
                _countsAsWeeklyDonation(offer),
          )
          .length;

      return CartWeeklyAllowance(
        ordersUsed: ordersUsed,
        donationsUploaded: donationsUploaded,
        orderLimit:
            cartWeeklyOrderLimit +
            (donationsUploaded * cartOrdersPerWeeklyDonation),
      );
    });

Future<bool> ensureCanAddItemToCart({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final userId = ref.read(currentUserIdProvider)?.trim();
  if (userId == null || userId.isEmpty) return true;

  try {
    ref.invalidate(cartWeeklyAllowanceProvider(userId));
    final allowance = await ref.read(
      cartWeeklyAllowanceProvider(userId).future,
    );
    if (allowance.canAddToCart) return true;
    if (!context.mounted) return false;

    final goToDonation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Límite semanal alcanzado'),
          content: Text(
            'Puedes hacer $cartWeeklyOrderLimit pedidos por semana. '
            'Cada donacion publicada habilita '
            '$cartOrdersPerWeeklyDonation pedidos mas esta semana. '
            'Ya usaste ${allowance.ordersUsed} de ${allowance.orderLimit}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Publicar donacion'),
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
          content: Text('No pudimos validar tu límite semanal de pedidos.'),
        ),
      );
    }
    return false;
  }
}

DateTime _startOfIsoWeek(DateTime date) {
  final utc = date.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

bool _isInWeek(DateTime date, DateTime weekStart, DateTime nextWeekStart) {
  return !date.isBefore(weekStart) && date.isBefore(nextWeekStart);
}

bool _countsAsWeeklyDonation(Offer offer) {
  return offer.status == OfferStatus.active ||
      offer.status == OfferStatus.soldOut;
}

bool _countsAsWeeklyOrder(Order order) {
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

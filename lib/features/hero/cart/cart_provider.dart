import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/utils/weight_utils.dart';
import 'cart_item.dart';

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    return const [];
  }

  void addItem({
    required String offerId,
    required String name,
    required String condition,
    required double price,
    required String imageUrl,
    double weight = 0.5,
    firestore.GeoPoint? pickupGeo,
  }) {
    assert(() {
      debugPrint(
        '🛒 [Cart] addItem offerId=$offerId pickupGeo=${pickupGeo?.latitude},${pickupGeo?.longitude}',
      );
      return true;
    }());

    final weightKg = parseWeightKg(weight, fallbackKg: 0.5);
    final index = state.indexWhere((item) => item.offerId == offerId);

    if (index == -1) {
      state = [
        ...state,
        CartItem(
          offerId: offerId,
          name: name,
          condition: condition,
          quantity: 1,
          price: 0.0,
          weight: weightKg,
          imageUrl: imageUrl,
          pickupGeo: pickupGeo,
        ),
      ];
    } else {
      final current = state[index];
      final shouldUpgradePickupGeo =
          current.pickupGeo == null && pickupGeo != null;

      final updated = CartItem(
        offerId: current.offerId,
        name: current.name,
        condition: current.condition,
        quantity: current.quantity + 1,
        price: current.price,
        weight: current.weight,
        imageUrl: current.imageUrl,
        pickupGeo: shouldUpgradePickupGeo ? pickupGeo : current.pickupGeo,
        pickupSchedule: current.pickupSchedule,
        useConcierge: current.useConcierge,
        conciergeInfo: current.conciergeInfo,
      );
      final newState = [...state];
      newState[index] = updated;
      state = newState;
    }
  }

  void removeOne(CartItem item) {
    final index = state.indexWhere((e) => e.offerId == item.offerId);
    if (index == -1) return;

    final current = state[index];
    if (current.quantity <= 1) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i != index) state[i],
      ];
    } else {
      final updated = current.copyWith(quantity: current.quantity - 1);
      final newState = [...state];
      newState[index] = updated;
      state = newState;
    }
  }

  void removeItem(CartItem item) {
    state = state.where((e) => e.offerId != item.offerId).toList();
  }

  void clear() {
    state = const [];
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(() {
  return CartNotifier();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';

import 'cart_item.dart';

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    return const [];
  }

  void addItem({
    required String name,
    required String condition,
    required double price,
    double weight = 0.5,
  }) {
    final index = state.indexWhere(
      (item) => item.name == name && item.condition == condition,
    );

    if (index == -1) {
      state = [
        ...state,
        CartItem(
          name: name,
          condition: condition,
          quantity: 1,
          price: price,
          weight: weight,
        ),
      ];
    } else {
      final current = state[index];
      final updated = current.copyWith(quantity: current.quantity + 1);
      final newState = [...state];
      newState[index] = updated;
      state = newState;
    }
  }

  void removeOne(CartItem item) {
    final index = state.indexWhere(
      (e) => e.name == item.name && e.condition == item.condition,
    );
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
    state = state
        .where((e) => e.name != item.name || e.condition != item.condition)
        .toList();
  }

  void clear() {
    state = const [];
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartItem>>(() {
  return CartNotifier();
});

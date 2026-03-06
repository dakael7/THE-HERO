import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/utils/weight_utils.dart';
import '../../shared/profile/presentation/providers/profile_provider.dart';
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
    int? availableQty,
    double weight = 0.5,
    firestore.GeoPoint? pickupGeo,
    String? pickupAddressSnapshot,
    String? pickupCountryCode,
    String? sellerHeroId,
    bool allowInPersonPickup = false,
  }) {
    final currentUserId = ref.read(profileProvider).maybeWhen(
          data: (user) => user?.id,
          orElse: () => null,
        );
    final sellerId = sellerHeroId?.trim();
    if (currentUserId != null &&
        sellerId != null &&
        sellerId.isNotEmpty &&
        sellerId == currentUserId) {
      assert(() {
        debugPrint(
          '🛒 [Cart] Blocked self-add offerId=$offerId sellerHeroId=$sellerId',
        );
        return true;
      }());
      return;
    }

    assert(() {
      debugPrint(
        '🛒 [Cart] addItem offerId=$offerId pickupGeo=${pickupGeo?.latitude},${pickupGeo?.longitude}',
      );
      return true;
    }());

    final weightKg = parseWeightKg(weight, fallbackKg: 0.5);
    final index = state.indexWhere((item) => item.offerId == offerId);

    final effectiveAvailableQty = availableQty ??
        (index == -1 ? null : state[index].availableQty);
    if (effectiveAvailableQty != null && effectiveAvailableQty <= 0) {
      assert(() {
        debugPrint('🛒 [Cart] Blocked addItem sold out offerId=$offerId');
        return true;
      }());
      return;
    }

    if (index == -1) {
      state = [
        ...state,
        CartItem(
          offerId: offerId,
          sellerHeroId: sellerHeroId,
          name: name,
          condition: condition,
          quantity: 1,
          availableQty: effectiveAvailableQty,
          price: 0.0,
          weight: weightKg,
          imageUrl: imageUrl,
          pickupGeo: pickupGeo,
          pickupAddressSnapshot: pickupAddressSnapshot,
          pickupCountryCode: pickupCountryCode,
          allowInPersonPickup: allowInPersonPickup,
        ),
      ];
    } else {
      final current = state[index];

      if (effectiveAvailableQty != null &&
          current.quantity >= effectiveAvailableQty) {
        assert(() {
          debugPrint(
            '🛒 [Cart] Blocked addItem over stock offerId=$offerId qty=${current.quantity} available=$effectiveAvailableQty',
          );
          return true;
        }());
        return;
      }

      final shouldUpgradePickupGeo =
          current.pickupGeo == null && pickupGeo != null;
      final shouldUpgradePickupAddress =
          (current.pickupAddressSnapshot == null ||
              current.pickupAddressSnapshot!.trim().isEmpty) &&
          pickupAddressSnapshot != null &&
          pickupAddressSnapshot.trim().isNotEmpty;
      final shouldUpgradeCountry =
          (current.pickupCountryCode == null ||
              current.pickupCountryCode!.trim().isEmpty) &&
          pickupCountryCode != null &&
          pickupCountryCode.trim().isNotEmpty;

      final updated = CartItem(
        offerId: current.offerId,
        sellerHeroId: current.sellerHeroId ?? sellerHeroId,
        name: current.name,
        condition: current.condition,
        quantity: current.quantity + 1,
        availableQty: effectiveAvailableQty,
        price: current.price,
        weight: current.weight,
        imageUrl: current.imageUrl,
        pickupGeo: shouldUpgradePickupGeo ? pickupGeo : current.pickupGeo,
        pickupAddressSnapshot: shouldUpgradePickupAddress
            ? pickupAddressSnapshot
            : current.pickupAddressSnapshot,
        pickupCountryCode:
            shouldUpgradeCountry ? pickupCountryCode : current.pickupCountryCode,
        pickupSchedule: current.pickupSchedule,
        useConcierge: current.useConcierge,
        conciergeInfo: current.conciergeInfo,
        allowInPersonPickup: current.allowInPersonPickup || allowInPersonPickup,
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

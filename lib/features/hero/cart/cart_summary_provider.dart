import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../../core/config/donation_pricing_config.dart';
import '../../../domain/config/pricing_config_provider.dart';
import '../../../domain/entities/order_requirements.dart';
import 'cart_provider.dart';
import 'cart_item.dart';

class CartSummary {
  final double subtotal;
  final double shippingCost;
  final double serviceFee;
  final double tax;
  final double total;
  final double totalWeight;
  final String? shippingBreakdown;

  const CartSummary({
    required this.subtotal,
    required this.shippingCost,
    required this.serviceFee,
    required this.tax,
    required this.total,
    required this.totalWeight,
    this.shippingBreakdown,
  });
}

final deliveryGeoProvider = StateProvider<firestore.GeoPoint?>((ref) => null);

final allItemsAllowInPersonPickupProvider = Provider<bool>((ref) {
  final cartItems = ref.watch(cartProvider);
  if (cartItems.isEmpty) return false;
  return cartItems.every((e) => e.allowInPersonPickup);
});

final inPersonPickupSelectedProvider = StateProvider<bool>((ref) => false);

final routeDistanceKmProvider = StateProvider<double?>((ref) => null);

double? computeEffectiveDistanceKm({
  required List<CartItem> cartItems,
  required firestore.GeoPoint? deliveryGeo,
  required double? routeDistanceKm,
  required bool inPersonPickupSelected,
  required bool allItemsAllowInPersonPickup,
}) {
  if (inPersonPickupSelected && allItemsAllowInPersonPickup) {
    return null;
  }

  final hasRouteDistance =
      routeDistanceKm != null &&
      routeDistanceKm.isFinite &&
      !routeDistanceKm.isNaN &&
      routeDistanceKm > 0;
  if (hasRouteDistance) return routeDistanceKm;

  final pickupGeos = cartItems
      .map((e) => e.pickupGeo)
      .where(_isValidGeo)
      .cast<firestore.GeoPoint>()
      .toList();

  final hasDeliveryGeo = _isValidGeo(deliveryGeo);
  final hasPickupGeos = pickupGeos.isNotEmpty;

  if (!hasDeliveryGeo || !hasPickupGeos) return null;

  final delivery = deliveryGeo!;

  final uniquePickups = <String, firestore.GeoPoint>{};
  for (final geo in pickupGeos) {
    final key =
        '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
    uniquePickups[key] = geo;
  }

  var totalKm = 0.0;
  for (final geo in uniquePickups.values) {
    totalKm += _haversineKm(geo, delivery);
  }

  if (totalKm.isNaN || totalKm.isInfinite || totalKm <= 0) return null;
  return totalKm;
}

final effectiveDistanceKmProvider = Provider<double?>((ref) {
  final cartItems = ref.watch(cartProvider);
  final deliveryGeo = ref.watch(deliveryGeoProvider);
  final routeDistanceKm = ref.watch(routeDistanceKmProvider);
  final inPersonPickupSelected = ref.watch(inPersonPickupSelectedProvider);
  final allItemsAllowInPersonPickup = ref.watch(
    allItemsAllowInPersonPickupProvider,
  );

  return computeEffectiveDistanceKm(
    cartItems: cartItems,
    deliveryGeo: deliveryGeo,
    routeDistanceKm: routeDistanceKm,
    inPersonPickupSelected: inPersonPickupSelected,
    allItemsAllowInPersonPickup: allItemsAllowInPersonPickup,
  );
});

bool _isValidGeo(firestore.GeoPoint? geo) {
  if (geo == null) return false;
  final lat = geo.latitude;
  final lng = geo.longitude;
  if (lat.isNaN || lng.isNaN) return false;
  if (lat.isInfinite || lng.isInfinite) return false;
  if (lat.abs() > 90 || lng.abs() > 180) return false;
  if (lat == 0.0 && lng == 0.0) return false;
  return true;
}

double _toRadians(double degrees) => degrees * 3.141592653589793 / 180.0;

double _haversineKm(firestore.GeoPoint a, firestore.GeoPoint b) {
  const earthRadiusKm = 6371.0;

  final dLat = _toRadians(b.latitude - a.latitude);
  final dLng = _toRadians(b.longitude - a.longitude);

  final lat1 = _toRadians(a.latitude);
  final lat2 = _toRadians(b.latitude);

  final sinDLat = math.sin(dLat / 2);
  final sinDLng = math.sin(dLng / 2);

  final h =
      sinDLat * sinDLat + sinDLng * sinDLng * math.cos(lat1) * math.cos(lat2);
  final c = 2 * math.asin(math.sqrt(h));
  return earthRadiusKm * c;
}

double _calculateTransportFee({
  required double distanceKm,
  required double totalWeightKg,
  required PricingConfig pricingConfig,
}) {
  final vehicle = OrderRequirements.calculateRequiredVehicleFor(
    weightKg: totalWeightKg,
    distanceKm: distanceKm,
  );
  final minimum = pricingConfig.getMinimumCharge(vehicle);
  final basePerKm = pricingConfig.getPricePerKm(vehicle);
  final discount = pricingConfig.getDistanceDiscount(vehicle);

  var kmFee = 0.0;
  if (discount.hasDiscount && distanceKm > discount.thresholdKm!) {
    final threshold = discount.thresholdKm!;
    final reduced = discount.reducedPricePerKm!;
    final firstLeg = distanceKm.clamp(0.0, threshold);
    final remaining = (distanceKm - threshold).clamp(0.0, double.infinity);
    kmFee = firstLeg * basePerKm + remaining * reduced;
  } else {
    kmFee = distanceKm * basePerKm;
  }

  return math.max(minimum, kmFee);
}

CartSummary computeCartSummary({
  required List<CartItem> cartItems,
  required firestore.GeoPoint? deliveryGeo,
  required double? routeDistanceKm,
  required bool inPersonPickupSelected,
  required bool allItemsAllowInPersonPickup,
  required PricingConfig pricingConfig,
}) {
  double subtotal = 0.0;
  double totalWeight = 0.0;

  for (final item in cartItems) {
    subtotal = 0.0;
    totalWeight += item.weight * item.quantity;
  }

  final serviceFeeFixed = pricingConfig.riderCommissionConfig.serviceFeeCLP;
  final taxPercentage = pricingConfig.taxPercentage;

  final hasItems = cartItems.isNotEmpty;

  double shippingCost = 0.0;
  String? shippingBreakdown;

  if (hasItems) {
    if (inPersonPickupSelected && allItemsAllowInPersonPickup) {
      shippingCost = 0.0;
      shippingBreakdown = null;
    } else {
      final pickupGeos = cartItems
          .map((e) => e.pickupGeo)
          .where(_isValidGeo)
          .cast<firestore.GeoPoint>()
          .toList();

      final hasDeliveryGeo = _isValidGeo(deliveryGeo);
      final hasPickupGeos = pickupGeos.isNotEmpty;

      final hasRouteDistance =
          routeDistanceKm != null &&
          routeDistanceKm.isFinite &&
          !routeDistanceKm.isNaN &&
          routeDistanceKm > 0;

      if (hasRouteDistance) {
        final totalKm = routeDistanceKm;
        try {
          shippingCost = _calculateTransportFee(
            distanceKm: totalKm,
            totalWeightKg: totalWeight,
            pricingConfig: pricingConfig,
          );

          final requiredVehicle = OrderRequirements.calculateRequiredVehicleFor(
            weightKg: totalWeight,
            distanceKm: totalKm,
          );
          shippingBreakdown =
              '${totalKm.toStringAsFixed(1)} km · ${requiredVehicle.displayName}';
        } catch (_) {
          shippingCost = DonationPricingConfig.buyerShippingCost;
          shippingBreakdown = null;
        }

        assert(() {
          debugPrint(
            '🚚 [CartSummary] Using OSRM routeDistanceKm=${totalKm.toStringAsFixed(2)} shipping=$shippingCost',
          );
          return true;
        }());
      } else if (hasDeliveryGeo && hasPickupGeos) {
        final delivery = deliveryGeo!;

        final uniquePickups = <String, firestore.GeoPoint>{};
        for (final geo in pickupGeos) {
          final key =
              '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
          uniquePickups[key] = geo;
        }

        var totalKm = 0.0;
        for (final geo in uniquePickups.values) {
          totalKm += _haversineKm(geo, delivery);
        }

        if (totalKm.isNaN || totalKm.isInfinite || totalKm <= 0) {
          shippingCost = DonationPricingConfig.buyerShippingCost;
          shippingBreakdown = null;

          assert(() {
            debugPrint(
              '🚚 [CartSummary] Invalid totalKm=$totalKm (pickups=${uniquePickups.length}). Using fallback shipping cost.',
            );
            return true;
          }());
        } else {
          try {
            shippingCost = _calculateTransportFee(
              distanceKm: totalKm,
              totalWeightKg: totalWeight,
              pricingConfig: pricingConfig,
            );

            final requiredVehicle =
                OrderRequirements.calculateRequiredVehicleFor(
                  weightKg: totalWeight,
                  distanceKm: totalKm,
                );
            shippingBreakdown =
                '${totalKm.toStringAsFixed(1)} km · ${requiredVehicle.displayName}';
          } catch (_) {
            shippingCost = DonationPricingConfig.buyerShippingCost;
            shippingBreakdown = null;
          }

          assert(() {
            debugPrint(
              '🚚 [CartSummary] totalKm=${totalKm.toStringAsFixed(2)} pickups=${uniquePickups.length} delivery=${delivery.latitude},${delivery.longitude} shipping=$shippingCost',
            );
            return true;
          }());
        }
      } else {
        shippingCost = DonationPricingConfig.buyerShippingCost;
        shippingBreakdown = null;

        assert(() {
          debugPrint(
            '🚚 [CartSummary] Missing/invalid geos. deliveryValid=$hasDeliveryGeo pickupCount=${pickupGeos.length}. Using fallback shipping cost.',
          );
          return true;
        }());
      }
    }
  }

  final serviceFee = hasItems ? serviceFeeFixed : 0.0;
  final taxBase = shippingCost + serviceFee;
  final tax = taxBase * taxPercentage;
  final total = subtotal + taxBase + tax;

  return CartSummary(
    subtotal: subtotal,
    shippingCost: shippingCost,
    serviceFee: serviceFee,
    tax: tax,
    total: total,
    totalWeight: totalWeight,
    shippingBreakdown: shippingBreakdown,
  );
}

final cartSummaryProvider = Provider<CartSummary>((ref) {
  final cartItems = ref.watch(cartProvider);
  final deliveryGeo = ref.watch(deliveryGeoProvider);
  final routeDistanceKm = ref.watch(routeDistanceKmProvider);
  final inPersonPickupSelected = ref.watch(inPersonPickupSelectedProvider);
  final allItemsAllowInPersonPickup = ref.watch(
    allItemsAllowInPersonPickupProvider,
  );
  final pricingConfig = ref.watch(pricingConfigProvider);

  return computeCartSummary(
    cartItems: cartItems,
    deliveryGeo: deliveryGeo,
    routeDistanceKm: routeDistanceKm,
    inPersonPickupSelected: inPersonPickupSelected,
    allItemsAllowInPersonPickup: allItemsAllowInPersonPickup,
    pricingConfig: pricingConfig,
  );
});

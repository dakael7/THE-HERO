import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/donation_pricing_config.dart';
import '../../data/providers/network_providers.dart';
import '../entities/vehicle.dart';
import 'transport_pricing_config.dart';
import '../services/rider_commission_calculator.dart';

/// Distance-based discount config for a specific vehicle type.
class DistanceDiscountConfig {
  /// km threshold after which the reduced price kicks in. null = no discount.
  final double? thresholdKm;

  /// Price per km charged beyond [thresholdKm]. null = no discount.
  final double? reducedPricePerKm;

  const DistanceDiscountConfig({
    required this.thresholdKm,
    required this.reducedPricePerKm,
  });

  bool get hasDiscount => thresholdKm != null && reducedPricePerKm != null;
}

/// Rider commission settings read from remote config (or defaults).
class RiderCommissionConfig {
  final double serviceFeeCLP;
  final double taxPercentage; // 0..1

  const RiderCommissionConfig({
    required this.serviceFeeCLP,
    required this.taxPercentage,
  });

  factory RiderCommissionConfig.defaults() => const RiderCommissionConfig(
    serviceFeeCLP: RiderCommissionCalculator.serviceFeeCLP,
    taxPercentage: RiderCommissionCalculator.taxPercentage,
  );
}

class PricingConfig {
  final Map<VehicleType, double> pricePerKm;
  final Map<VehicleType, double> minimumCharge;
  final double taxPercentage;

  /// Max km per vehicle — remote-controlled, with local fallback.
  final Map<VehicleType, double> maxDistanceKm;

  /// Distance-discount config per vehicle — remote-controlled, with local fallback.
  final Map<VehicleType, DistanceDiscountConfig> distanceDiscount;

  /// Rider commission config — remote-controlled, with local fallback.
  final RiderCommissionConfig riderCommissionConfig;

  const PricingConfig({
    required this.pricePerKm,
    required this.minimumCharge,
    required this.taxPercentage,
    required this.maxDistanceKm,
    required this.distanceDiscount,
    required this.riderCommissionConfig,
  });

  factory PricingConfig.defaults() {
    final distanceDiscountDefaults = <VehicleType, DistanceDiscountConfig>{
      for (final v in VehicleType.values)
        v: DistanceDiscountConfig(
          thresholdKm: TransportPricingConfig.hasDistanceDiscount(v)
              ? TransportPricingConfig.distanceThresholdForDiscount
              : null,
          reducedPricePerKm: TransportPricingConfig.getReducedPricePerKm(v),
        ),
    };
    return PricingConfig(
      pricePerKm: TransportPricingConfig.pricePerKm,
      minimumCharge: TransportPricingConfig.minimumCharge,
      taxPercentage: DonationPricingConfig.taxPercentage,
      maxDistanceKm: TransportPricingConfig.maxDistanceKm,
      distanceDiscount: distanceDiscountDefaults,
      riderCommissionConfig: RiderCommissionConfig.defaults(),
    );
  }

  double getPricePerKm(VehicleType vehicleType) {
    return pricePerKm[vehicleType] ??
        TransportPricingConfig.getPricePerKm(vehicleType);
  }

  double getMinimumCharge(VehicleType vehicleType) {
    return minimumCharge[vehicleType] ??
        TransportPricingConfig.getMinimumCharge(vehicleType);
  }

  /// Max distance for a vehicle. Returns infinity if uncapped.
  double getMaxDistance(VehicleType vehicleType) {
    return maxDistanceKm[vehicleType] ?? double.infinity;
  }

  /// Distance-discount config for a vehicle.
  DistanceDiscountConfig getDistanceDiscount(VehicleType vehicleType) {
    return distanceDiscount[vehicleType] ??
        DistanceDiscountConfig(thresholdKm: null, reducedPricePerKm: null);
  }

  static PricingConfig fromFirestore(Map<String, dynamic> data) {
    final defaults = PricingConfig.defaults();

    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.nan;
    }

    Map<VehicleType, double> parseVehicleMap(
      dynamic raw,
      Map<VehicleType, double> fallback,
    ) {
      if (raw is! Map) return fallback;
      final result = <VehicleType, double>{...fallback};
      for (final entry in raw.entries) {
        final key = entry.key?.toString();
        if (key == null || key.trim().isEmpty) continue;
        VehicleType? type;
        try {
          type = VehicleType.fromString(key);
        } catch (_) {
          type = null;
        }
        if (type == null) continue;
        final value = parseDouble(entry.value);
        if (value.isNaN || !value.isFinite || value < 0) continue;
        result[type] = value;
      }
      return result;
    }

    /// Parse maxDistanceKm: null / missing / very large number → infinity.
    Map<VehicleType, double> parseMaxDistanceMap(
      dynamic raw,
      Map<VehicleType, double> fallback,
    ) {
      if (raw is! Map) return fallback;
      final result = <VehicleType, double>{...fallback};
      for (final entry in raw.entries) {
        final key = entry.key?.toString();
        if (key == null || key.trim().isEmpty) continue;
        VehicleType? type;
        try {
          type = VehicleType.fromString(key);
        } catch (_) {
          type = null;
        }
        if (type == null) continue;
        final v = entry.value;
        if (v == null) {
          result[type] = double.infinity;
          continue;
        }
        final value = parseDouble(v);
        if (value.isNaN || value < 0) continue;
        result[type] = value >= 99999 ? double.infinity : value;
      }
      return result;
    }

    /// Parse distanceDiscount map.
    /// Firestore format per vehicle:
    ///   { "thresholdKm": 30, "reducedPricePerKm": 800 }
    /// or null to disable discount.
    Map<VehicleType, DistanceDiscountConfig> parseDistanceDiscountMap(
      dynamic raw,
      Map<VehicleType, DistanceDiscountConfig> fallback,
    ) {
      if (raw is! Map) return fallback;
      final result = <VehicleType, DistanceDiscountConfig>{...fallback};
      for (final entry in raw.entries) {
        final key = entry.key?.toString();
        if (key == null || key.trim().isEmpty) continue;
        VehicleType? type;
        try {
          type = VehicleType.fromString(key);
        } catch (_) {
          type = null;
        }
        if (type == null) continue;

        final v = entry.value;
        if (v == null) {
          // null explicitly = no discount for this vehicle
          result[type] = const DistanceDiscountConfig(
            thresholdKm: null,
            reducedPricePerKm: null,
          );
          continue;
        }
        if (v is! Map) continue;

        final threshold = parseDouble(v['thresholdKm']);
        final reduced = parseDouble(v['reducedPricePerKm']);

        result[type] = DistanceDiscountConfig(
          thresholdKm: (threshold.isFinite && !threshold.isNaN && threshold > 0)
              ? threshold
              : fallback[type]?.thresholdKm,
          reducedPricePerKm:
              (reduced.isFinite && !reduced.isNaN && reduced >= 0)
              ? reduced
              : fallback[type]?.reducedPricePerKm,
        );
      }
      return result;
    }

    final rawPricePerKm = data['pricePerKm'];
    final rawMinimumCharge = data['minimumCharge'];
    final rawMaxDistanceKm = data['maxDistanceKm'];
    final rawDistanceDiscount = data['distanceDiscount'];

    // ── IVA (taxPercentage) ──
    double resolvedTax = defaults.taxPercentage;
    final rawTaxBasisPoints = data['taxBasisPoints'];
    final rawTaxPercent = data['taxPercent'];
    final rawTaxPercentage = data['taxPercentage'];

    double normalizePercent(dynamic raw) {
      final v = parseDouble(raw);
      if (!v.isFinite || v.isNaN || v < 0) return double.nan;
      if (v > 1.0) return v / 100.0;
      return v;
    }

    if (rawTaxBasisPoints is num) {
      final v = rawTaxBasisPoints.toDouble();
      if (v.isFinite && !v.isNaN && v >= 0) resolvedTax = v / 10000.0;
    } else {
      final fromPercent = normalizePercent(rawTaxPercent);
      if (fromPercent.isFinite && !fromPercent.isNaN) {
        resolvedTax = fromPercent;
      } else {
        final fromPercentage = normalizePercent(rawTaxPercentage);
        if (fromPercentage.isFinite && !fromPercentage.isNaN) {
          resolvedTax = fromPercentage;
        }
      }
    }

    // ── Rider commission ──
    RiderCommissionConfig resolvedRiderCommission =
        defaults.riderCommissionConfig;
    final rawRiderCommission = data['riderCommission'];
    if (rawRiderCommission is Map) {
      final rawFeeCLP = rawRiderCommission['serviceFeeCLP'];
      final rawTaxP =
          rawRiderCommission['taxPercent'] ??
          rawRiderCommission['taxPercentage'];

      final feeCLP = parseDouble(rawFeeCLP);
      final taxP = normalizePercent(rawTaxP);

      resolvedRiderCommission = RiderCommissionConfig(
        serviceFeeCLP: (feeCLP.isFinite && !feeCLP.isNaN && feeCLP >= 0)
            ? feeCLP
            : defaults.riderCommissionConfig.serviceFeeCLP,
        taxPercentage: (taxP.isFinite && !taxP.isNaN && taxP >= 0)
            ? taxP
            : defaults.riderCommissionConfig.taxPercentage,
      );
    }

    return PricingConfig(
      pricePerKm: parseVehicleMap(rawPricePerKm, defaults.pricePerKm),
      minimumCharge: parseVehicleMap(rawMinimumCharge, defaults.minimumCharge),
      taxPercentage: resolvedTax,
      maxDistanceKm: parseMaxDistanceMap(
        rawMaxDistanceKm,
        defaults.maxDistanceKm,
      ),
      distanceDiscount: parseDistanceDiscountMap(
        rawDistanceDiscount,
        defaults.distanceDiscount,
      ),
      riderCommissionConfig: resolvedRiderCommission,
    );
  }
}

final pricingConfigStreamProvider = StreamProvider<PricingConfig>((ref) {
  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore.collection('settings').doc('pricing').snapshots().map((
    snap,
  ) {
    final data = snap.data();
    if (!snap.exists || data == null) return PricingConfig.defaults();
    return PricingConfig.fromFirestore(data);
  });
});

final pricingConfigProvider = Provider<PricingConfig>((ref) {
  final async = ref.watch(pricingConfigStreamProvider);
  return async.maybeWhen(data: (v) => v, orElse: PricingConfig.defaults);
});

/// Convenience provider: only the rider commission config.
final riderCommissionConfigProvider = Provider<RiderCommissionConfig>((ref) {
  return ref.watch(pricingConfigProvider).riderCommissionConfig;
});

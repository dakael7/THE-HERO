import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/donation_pricing_config.dart';
import '../../data/providers/network_providers.dart';
import '../entities/vehicle.dart';
import 'transport_pricing_config.dart';

class PricingConfig {
  final Map<VehicleType, double> pricePerKm;
  final Map<VehicleType, double> minimumCharge;
  final double taxPercentage;

  const PricingConfig({
    required this.pricePerKm,
    required this.minimumCharge,
    required this.taxPercentage,
  });

  factory PricingConfig.defaults() {
    return PricingConfig(
      pricePerKm: TransportPricingConfig.pricePerKm,
      minimumCharge: TransportPricingConfig.minimumCharge,
      taxPercentage: DonationPricingConfig.taxPercentage,
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

    final rawPricePerKm = data['pricePerKm'];
    final rawMinimumCharge = data['minimumCharge'];

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
      if (v.isFinite && !v.isNaN && v >= 0) {
        resolvedTax = v / 10000.0;
      }
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

    return PricingConfig(
      pricePerKm: parseVehicleMap(rawPricePerKm, defaults.pricePerKm),
      minimumCharge:
          parseVehicleMap(rawMinimumCharge, defaults.minimumCharge),
      taxPercentage: resolvedTax,
    );
  }
}

final pricingConfigStreamProvider = StreamProvider<PricingConfig>((ref) {
  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore
      .collection('settings')
      .doc('pricing')
      .snapshots()
      .map((snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return PricingConfig.defaults();
    return PricingConfig.fromFirestore(data);
  });
});

final pricingConfigProvider = Provider<PricingConfig>((ref) {
  final async = ref.watch(pricingConfigStreamProvider);
  return async.maybeWhen(
    data: (v) => v,
    orElse: PricingConfig.defaults,
  );
});

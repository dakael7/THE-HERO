import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/domain/config/pricing_config_provider.dart';
import 'package:the_hero/domain/entities/order_requirements.dart';
import 'package:the_hero/domain/entities/vehicle.dart';

void main() {
  test('reads buyer service fee from pricing settings', () {
    final config = PricingConfig.fromFirestore({'buyerServiceFeeCLP': 1600});

    expect(config.buyerServiceFee, 1600);
  });

  test('supports legacy service fee field names', () {
    final config = PricingConfig.fromFirestore({'serviceFeeCLP': 1600});

    expect(config.buyerServiceFee, 1600);
  });

  test('maps legacy riderCommission service fee to buyer service fee', () {
    final config = PricingConfig.fromFirestore({
      'riderCommission': {'serviceFeeCLP': 1600},
    });

    expect(config.buyerServiceFee, 1600);
    expect(config.riderCommissionConfig.serviceFeeCLP, 0);
  });

  test('uses Firebase max distance when selecting required vehicle', () {
    final config = PricingConfig.fromFirestore({
      'maxDistanceKm': {'motorcycle': 50},
    });

    final vehicle = OrderRequirements.calculateRequiredVehicleFor(
      weightKg: 8,
      distanceKm: 20,
      maxDistanceFor: config.getMaxDistance,
    );

    expect(vehicle, VehicleType.motorcycle);
  });
}

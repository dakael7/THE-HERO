import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/domain/config/transport_pricing_config.dart';
import 'package:the_hero/domain/services/delivery_fee_calculator.dart';
import 'package:the_hero/domain/entities/vehicle.dart';

void main() {
  group('Transport Pricing Tests', () {
    test('Bicycle - Minimum charge applies for short distance', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.bicycle,
        distanceKm: 1.0,
      );

      expect(result.fee, equals(2000.0)); // Minimum charge
      expect(result.minimumChargeApplied, isTrue);
    });

    test('Bicycle - Normal rate for medium distance', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.bicycle,
        distanceKm: 5.0,
      );

      expect(result.fee, equals(2500.0)); // 500 * 5
      expect(result.minimumChargeApplied, isFalse);
    });

    test('Bicycle - Exceeds maximum distance', () {
      expect(
        () => DeliveryFeeCalculator.calculateFee(
          vehicleType: VehicleType.bicycle,
          distanceKm: 4.0,
        ),
        throwsException,
      );
    });

    test('Motorcycle - Minimum charge applies', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.motorcycle,
        distanceKm: 2.0,
      );

      expect(result.fee, equals(3000.0)); // Minimum charge
      expect(result.minimumChargeApplied, isTrue);
    });

    test('Motorcycle - Normal rate', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.motorcycle,
        distanceKm: 10.0,
      );

      expect(result.fee, equals(6500.0)); // 650 * 10
      expect(result.minimumChargeApplied, isFalse);
    });

    test('Car - Minimum charge applies', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.car,
        distanceKm: 3.0,
      );

      expect(result.fee, equals(4500.0)); // Minimum charge
      expect(result.minimumChargeApplied, isTrue);
    });

    test('Car - Normal rate under 30km', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.car,
        distanceKm: 20.0,
      );

      expect(result.fee, equals(20000.0)); // 1000 * 20
      expect(result.minimumChargeApplied, isFalse);
      expect(result.distanceDiscountApplied, isFalse);
    });

    test('Car - Reduced rate after 30km', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.car,
        distanceKm: 35.0,
      );

      // First 30 km: 30 * 1000 = 30000
      // Next 5 km: 5 * 800 = 4000
      // Total: 34000
      expect(result.fee, equals(34000.0));
      expect(result.distanceDiscountApplied, isTrue);
    });

    test('Truck - Minimum charge applies', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.truck,
        distanceKm: 5.0,
      );

      expect(result.fee, equals(10000.0)); // Minimum charge
      expect(result.minimumChargeApplied, isTrue);
    });

    test('Truck - Normal rate under 30km', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.truck,
        distanceKm: 20.0,
      );

      expect(result.fee, equals(30000.0)); // 1500 * 20
      expect(result.minimumChargeApplied, isFalse);
    });

    test('Truck - Reduced rate after 30km', () {
      final result = DeliveryFeeCalculator.calculateFee(
        vehicleType: VehicleType.truck,
        distanceKm: 40.0,
      );

      // First 30 km: 30 * 1500 = 45000
      // Next 10 km: 10 * 1200 = 12000
      // Total: 57000
      expect(result.fee, equals(57000.0));
      expect(result.distanceDiscountApplied, isTrue);
    });

    test('Configuration values are correct', () {
      expect(
        TransportPricingConfig.getPricePerKm(VehicleType.bicycle),
        equals(500.0),
      );
      expect(
        TransportPricingConfig.getPricePerKm(VehicleType.motorcycle),
        equals(650.0),
      );
      expect(
        TransportPricingConfig.getPricePerKm(VehicleType.car),
        equals(1000.0),
      );
      expect(
        TransportPricingConfig.getPricePerKm(VehicleType.truck),
        equals(1500.0),
      );

      expect(
        TransportPricingConfig.getMinimumCharge(VehicleType.bicycle),
        equals(2000.0),
      );
      expect(
        TransportPricingConfig.getMinimumCharge(VehicleType.motorcycle),
        equals(3000.0),
      );
      expect(
        TransportPricingConfig.getMinimumCharge(VehicleType.car),
        equals(4500.0),
      );
      expect(
        TransportPricingConfig.getMinimumCharge(VehicleType.truck),
        equals(10000.0),
      );

      expect(
        TransportPricingConfig.getMaxDistance(VehicleType.bicycle),
        equals(3.5),
      );
      expect(
        TransportPricingConfig.getMaxDistance(VehicleType.motorcycle),
        equals(10.0),
      );
    });
  });
}

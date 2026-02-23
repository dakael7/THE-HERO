import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_pickup.dart';
import '../../../domain/entities/order_pickup_stop.dart';
import '../../../domain/entities/order_delivery.dart';
import '../../../domain/entities/order_requirements.dart';
import '../../../domain/entities/order_rider.dart';
import '../../../domain/entities/order_timestamps.dart';
import '../../../domain/entities/order_status.dart';
import '../../../domain/entities/vehicle.dart';
import '../../../domain/entities/pickup_schedule.dart';
import '../../../domain/entities/concierge_info.dart';
import 'cart_item.dart';
import 'cart_summary_provider.dart';

/// Utility class to build Order objects from cart data
class OrderBuilder {
  /// Builds a complete Order object from cart items and summary
  ///
  /// This creates a local preview of the order before submission.
  /// The orderId will be empty and should be set by Firestore when creating the order.
  static Order buildOrderFromCart({
    String orderId = '',
    required List<CartItem> cartItems,
    required CartSummary cartSummary,
    required String heroId,
    required OrderDelivery delivery,
    OrderStatus status = OrderStatus.pendingPayment,
    String pickupAddress = '',
    firestore.GeoPoint? pickupGeo,
    String pickupGeohash = '',
    String pickupContactName = '',
    String pickupContactPhone = '',
    String pickupInstructions = '',
    PickupSchedule? pickupSchedule,
    bool useConcierge = false,
    ConciergeInfo? conciergeInfo,
  }) {
    if (cartItems.isEmpty) {
      throw Exception('Cannot create order from empty cart');
    }

    final now = DateTime.now();

    // Convert cart items to order items
    final orderItems = cartItems.map((item) => item.toOrderItem()).toList();

    // Calculate total weight
    final totalWeight = cartSummary.totalWeight;

    // Determine required vehicle based on weight
    final requiredVehicle = OrderRequirements.calculateRequiredVehicle(
      totalWeight,
    );

    // Create order pickup (seller's location)
    final pickup = OrderPickup(
      geo:
          pickupGeo ??
          const firestore.GeoPoint(
            0,
            0,
          ), // Default, should be set from seller profile
      geohash: pickupGeohash,
      addressSnapshot: pickupAddress,
      contactName: pickupContactName,
      contactPhone: pickupContactPhone,
      instructions: pickupInstructions,
    );

    final pickupStops = <OrderPickupStop>[];
    final byKey = <String, Set<String>>{};
    for (final item in cartItems) {
      final geo = item.pickupGeo;
      if (geo == null) continue;
      if (geo.latitude == 0.0 && geo.longitude == 0.0) continue;
      final key = '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
      (byKey[key] ??= <String>{}).add(item.offerId);
    }

    for (final entry in byKey.entries) {
      final parts = entry.key.split(',');
      final lat = double.tryParse(parts.first) ?? 0.0;
      final lng = double.tryParse(parts.length > 1 ? parts[1] : '') ?? 0.0;
      pickupStops.add(
        OrderPickupStop(
          geo: firestore.GeoPoint(lat, lng),
          addressSnapshot: '',
          offerIds: entry.value.toList(),
        ),
      );
    }

    // Create order requirements
    final requirements = OrderRequirements(
      weightKg: totalWeight,
      requiredVehicle: requiredVehicle,
      estimatedDistanceKm: 0.0, // Will be calculated when addresses are known
    );

    // Create unassigned rider
    final rider = OrderRider();

    // Create timestamps
    final timestamps = OrderTimestamps(createdAt: now);

    // Build the order
    return Order(
      orderId: orderId,
      heroId: heroId,
      items: orderItems,
      subtotal: cartSummary.subtotal,
      deliveryFee: cartSummary.shippingCost,
      serviceFee: cartSummary.serviceFee,
      tax: cartSummary.tax,
      amountTotal: cartSummary.total,
      currency: 'CLP',
      pickup: pickup,
      pickupStops: pickupStops.isEmpty ? null : pickupStops,
      delivery: delivery,
      requirements: requirements,
      rider: rider,
      status: status,
      timestamps: timestamps,
      updatedAt: now,
      version: 1,
      pickupSchedule: pickupSchedule,
      useConcierge: useConcierge,
      conciergeInfo: conciergeInfo,
    );
  }

  /// Helper to create OrderDelivery from form data
  static OrderDelivery createDelivery({
    required String address,
    required String recipientName,
    required String recipientPhone,
    firestore.GeoPoint? geo,
    String instructions = '',
    bool deliverToReception = false,
  }) {
    return OrderDelivery(
      geo:
          geo ??
          const firestore.GeoPoint(
            0,
            0,
          ), // Default, should be geocoded from address
      addressSnapshot: address,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      instructions: instructions,
      deliverToReception: deliverToReception,
    );
  }

  /// Get vehicle type display name
  static String getVehicleDisplayName(VehicleType vehicle) {
    switch (vehicle) {
      case VehicleType.bicycle:
        return 'Bicicleta';
      case VehicleType.motorcycle:
        return 'Motocicleta';
      case VehicleType.car:
        return 'Auto';
      case VehicleType.truck:
        return 'Camión';
    }
  }
}

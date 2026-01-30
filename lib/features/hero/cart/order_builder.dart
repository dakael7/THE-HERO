import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_pickup.dart';
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
    required List<CartItem> cartItems,
    required CartSummary cartSummary,
    required String heroId,
    required OrderDelivery delivery,
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
      orderId: '', // Will be set by Firestore
      heroId: heroId,
      items: orderItems,
      subtotal: cartSummary.subtotal,
      deliveryFee: cartSummary.shippingCost,
      serviceFee: cartSummary.serviceFee,
      tax: cartSummary.tax,
      amountTotal: cartSummary.total,
      currency: 'CLP',
      pickup: pickup,
      delivery: delivery,
      requirements: requirements,
      rider: rider,
      status: OrderStatus.created,
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

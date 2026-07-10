import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/domain/entities/order.dart';
import 'package:the_hero/domain/entities/order_delivery.dart';
import 'package:the_hero/domain/entities/order_pickup.dart';
import 'package:the_hero/domain/entities/order_requirements.dart';
import 'package:the_hero/domain/entities/order_rider.dart';
import 'package:the_hero/domain/entities/order_status.dart';
import 'package:the_hero/domain/entities/order_timestamps.dart';
import 'package:the_hero/domain/entities/vehicle.dart';

void main() {
  test('associated chats are hidden until the order is paid', () {
    expect(OrderStatus.created.canShowAssociatedChats, isFalse);
    expect(OrderStatus.pendingPayment.canShowAssociatedChats, isFalse);
    expect(OrderStatus.failed.canShowAssociatedChats, isFalse);

    expect(OrderStatus.paid.canShowAssociatedChats, isTrue);
    expect(OrderStatus.queued.canShowAssociatedChats, isTrue);
    expect(OrderStatus.assigned.canShowAssociatedChats, isTrue);
    expect(OrderStatus.canceled.canShowAssociatedChats, isFalse);
  });

  test('orders can only be canceled before payment', () {
    expect(OrderStatus.created.canBeCanceled, isTrue);
    expect(OrderStatus.pendingPayment.canBeCanceled, isTrue);

    expect(OrderStatus.paid.canBeCanceled, isFalse);
    expect(OrderStatus.queued.canBeCanceled, isFalse);
    expect(OrderStatus.assigned.canBeCanceled, isFalse);
    expect(OrderStatus.delivered.canBeCanceled, isFalse);
  });

  test('blocked paid orders keep payment but hide associated chats', () {
    final order = _order(
      status: OrderStatus.paid,
      fulfillmentStatus: 'blocked',
      fulfillmentBlockReason: 'approved_payment_without_stock_reservation',
      supportReviewStatus: 'pending',
    );

    expect(order.status.canShowAssociatedChats, isTrue);
    expect(order.isFulfillmentBlocked, isTrue);
    expect(order.canShowAssociatedChats, isFalse);
    expect(order.needsSupportReview, isTrue);
  });
}

Order _order({
  required OrderStatus status,
  String? fulfillmentStatus,
  String? fulfillmentBlockReason,
  String? supportReviewStatus,
}) {
  final now = DateTime(2026);
  const geo = GeoPoint(0, 0);
  return Order(
    orderId: 'order-1',
    heroId: 'hero-1',
    items: const [],
    subtotal: 0,
    deliveryFee: 0,
    serviceFee: 0,
    tax: 0,
    amountTotal: 0,
    currency: 'CLP',
    pickup: OrderPickup(
      geo: geo,
      geohash: 'abc',
      addressSnapshot: 'Pickup',
      contactName: 'Seller',
      contactPhone: '+56911111111',
    ),
    delivery: OrderDelivery(
      geo: geo,
      addressSnapshot: 'Delivery',
      recipientName: 'Hero',
      recipientPhone: '+56922222222',
    ),
    requirements: OrderRequirements(
      weightKg: 1,
      requiredVehicle: VehicleType.bicycle,
      estimatedDistanceKm: 1,
    ),
    rider: OrderRider(),
    status: status,
    timestamps: OrderTimestamps(createdAt: now),
    updatedAt: now,
    fulfillmentStatus: fulfillmentStatus,
    fulfillmentBlockReason: fulfillmentBlockReason,
    supportReviewStatus: supportReviewStatus,
  );
}

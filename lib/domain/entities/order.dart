import 'order_item.dart';
import 'order_pickup.dart';
import 'order_delivery.dart';
import 'order_requirements.dart';
import 'order_rider.dart';
import 'order_timestamps.dart';
import 'order_status.dart';

class Order {
  final String orderId;
  final String heroId;
  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double serviceFee;
  final double tax;
  final double amountTotal;
  final String currency;
  final OrderPickup pickup;
  final OrderDelivery delivery;
  final OrderRequirements requirements;
  final OrderRider rider;
  final OrderStatus status;
  final OrderTimestamps timestamps;
  final String? cancelReason;
  final String? canceledBy;
  final DateTime updatedAt;
  final int version;

  Order({
    required this.orderId,
    required this.heroId,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.serviceFee,
    required this.tax,
    required this.amountTotal,
    required this.currency,
    required this.pickup,
    required this.delivery,
    required this.requirements,
    required this.rider,
    required this.status,
    required this.timestamps,
    this.cancelReason,
    this.canceledBy,
    required this.updatedAt,
    this.version = 1,
  });

  bool get isAssigned => rider.isAssigned;
  bool get isActive => status.isActive;
  bool get isCompleted => status.isCompleted;
  bool get canBeCanceled => status.canBeCanceled;

  int get totalItems => items.fold(0, (sum, item) => sum + item.qty);

  Order copyWith({
    String? orderId,
    String? heroId,
    List<OrderItem>? items,
    double? subtotal,
    double? deliveryFee,
    double? serviceFee,
    double? tax,
    double? amountTotal,
    String? currency,
    OrderPickup? pickup,
    OrderDelivery? delivery,
    OrderRequirements? requirements,
    OrderRider? rider,
    OrderStatus? status,
    OrderTimestamps? timestamps,
    String? cancelReason,
    String? canceledBy,
    DateTime? updatedAt,
    int? version,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      heroId: heroId ?? this.heroId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      serviceFee: serviceFee ?? this.serviceFee,
      tax: tax ?? this.tax,
      amountTotal: amountTotal ?? this.amountTotal,
      currency: currency ?? this.currency,
      pickup: pickup ?? this.pickup,
      delivery: delivery ?? this.delivery,
      requirements: requirements ?? this.requirements,
      rider: rider ?? this.rider,
      status: status ?? this.status,
      timestamps: timestamps ?? this.timestamps,
      cancelReason: cancelReason ?? this.cancelReason,
      canceledBy: canceledBy ?? this.canceledBy,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }
}

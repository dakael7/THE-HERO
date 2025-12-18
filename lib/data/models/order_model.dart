import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../domain/entities/order.dart';
import '../../domain/entities/order_status.dart';
import 'order_item_model.dart';
import 'order_pickup_model.dart';
import 'order_delivery_model.dart';
import 'order_requirements_model.dart';
import 'order_rider_model.dart';
import 'order_timestamps_model.dart';

class OrderModel {
  final String orderId;
  final String heroId;
  final List<OrderItemModel> items;
  final double subtotal;
  final double deliveryFee;
  final double serviceFee;
  final double tax;
  final double amountTotal;
  final String currency;
  final OrderPickupModel pickup;
  final OrderDeliveryModel delivery;
  final OrderRequirementsModel requirements;
  final OrderRiderModel rider;
  final String status;
  final OrderTimestampsModel timestamps;
  final String? cancelReason;
  final String? canceledBy;
  final firestore.Timestamp updatedAt;
  final int version;

  OrderModel({
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

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      orderId: json['orderId'] as String? ?? '',
      heroId: json['heroId'] as String? ?? '',
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => OrderItemModel.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['serviceFee'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
      amountTotal: (json['amountTotal'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'CLP',
      pickup: OrderPickupModel.fromJson(json['pickup'] as Map<String, dynamic>? ?? {}),
      delivery: OrderDeliveryModel.fromJson(json['delivery'] as Map<String, dynamic>? ?? {}),
      requirements: OrderRequirementsModel.fromJson(json['requirements'] as Map<String, dynamic>? ?? {}),
      rider: OrderRiderModel.fromJson(json['rider'] as Map<String, dynamic>? ?? {}),
      status: json['status'] as String? ?? 'created',
      timestamps: OrderTimestampsModel.fromJson(json['timestamps'] as Map<String, dynamic>? ?? {}),
      cancelReason: json['cancelReason'] as String?,
      canceledBy: json['canceledBy'] as String?,
      updatedAt: json['updatedAt'] as firestore.Timestamp? ?? firestore.Timestamp.now(),
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'heroId': heroId,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'serviceFee': serviceFee,
      'tax': tax,
      'amountTotal': amountTotal,
      'currency': currency,
      'pickup': pickup.toJson(),
      'delivery': delivery.toJson(),
      'requirements': requirements.toJson(),
      'rider': rider.toJson(),
      'status': status,
      'timestamps': timestamps.toJson(),
      'cancelReason': cancelReason,
      'canceledBy': canceledBy,
      'updatedAt': updatedAt,
      'version': version,
    };
  }

  Order toEntity() {
    return Order(
      orderId: orderId,
      heroId: heroId,
      items: items.map((item) => item.toEntity()).toList(),
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      serviceFee: serviceFee,
      tax: tax,
      amountTotal: amountTotal,
      currency: currency,
      pickup: pickup.toEntity(),
      delivery: delivery.toEntity(),
      requirements: requirements.toEntity(),
      rider: rider.toEntity(),
      status: _stringToOrderStatus(status),
      timestamps: timestamps.toEntity(),
      cancelReason: cancelReason,
      canceledBy: canceledBy,
      updatedAt: updatedAt.toDate(),
      version: version,
    );
  }

  factory OrderModel.fromEntity(Order entity) {
    return OrderModel(
      orderId: entity.orderId,
      heroId: entity.heroId,
      items: entity.items.map((item) => OrderItemModel.fromEntity(item)).toList(),
      subtotal: entity.subtotal,
      deliveryFee: entity.deliveryFee,
      serviceFee: entity.serviceFee,
      tax: entity.tax,
      amountTotal: entity.amountTotal,
      currency: entity.currency,
      pickup: OrderPickupModel.fromEntity(entity.pickup),
      delivery: OrderDeliveryModel.fromEntity(entity.delivery),
      requirements: OrderRequirementsModel.fromEntity(entity.requirements),
      rider: OrderRiderModel.fromEntity(entity.rider),
      status: _orderStatusToString(entity.status),
      timestamps: OrderTimestampsModel.fromEntity(entity.timestamps),
      cancelReason: entity.cancelReason,
      canceledBy: entity.canceledBy,
      updatedAt: firestore.Timestamp.fromDate(entity.updatedAt),
      version: entity.version,
    );
  }

  static OrderStatus _stringToOrderStatus(String value) {
    switch (value.toLowerCase()) {
      case 'created':
        return OrderStatus.created;
      case 'pending_payment':
      case 'pendingpayment':
        return OrderStatus.pendingPayment;
      case 'paid':
        return OrderStatus.paid;
      case 'queued':
        return OrderStatus.queued;
      case 'assigned':
        return OrderStatus.assigned;
      case 'picked_up':
      case 'pickedup':
        return OrderStatus.pickedUp;
      case 'in_transit':
      case 'intransit':
        return OrderStatus.inTransit;
      case 'delivered':
        return OrderStatus.delivered;
      case 'canceled':
        return OrderStatus.canceled;
      case 'failed':
        return OrderStatus.failed;
      default:
        return OrderStatus.created;
    }
  }

  static String _orderStatusToString(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
        return 'created';
      case OrderStatus.pendingPayment:
        return 'pending_payment';
      case OrderStatus.paid:
        return 'paid';
      case OrderStatus.queued:
        return 'queued';
      case OrderStatus.assigned:
        return 'assigned';
      case OrderStatus.pickedUp:
        return 'picked_up';
      case OrderStatus.inTransit:
        return 'in_transit';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.canceled:
        return 'canceled';
      case OrderStatus.failed:
        return 'failed';
    }
  }
}

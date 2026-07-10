import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import '../../domain/entities/order.dart';
import '../../domain/entities/order_status.dart';
import 'order_item_model.dart';
import 'order_pickup_model.dart';
import 'order_pickup_stop_model.dart';
import 'order_delivery_model.dart';
import 'order_requirements_model.dart';
import 'order_rider_model.dart';
import 'order_timestamps_model.dart';
import 'pickup_schedule_model.dart';
import 'concierge_info_model.dart';

class OrderModel {
  final String orderId;
  final String heroId;
  final List<String> sellerHeroIds;
  final List<OrderItemModel> items;
  final double subtotal;
  final double deliveryFee;
  final double serviceFee;
  final double tax;
  final double tip;
  final double amountTotal;
  final String currency;
  final String documentType;
  final String? invoiceBusinessName;
  final String? invoiceRut;
  final String? invoiceGiro;
  final String? invoiceAddress;
  final String? invoiceEmail;
  final String? invoicePhone;
  final String? billingInvoiceId;
  final String? billingInvoiceStatus;
  final OrderPickupModel pickup;
  final List<OrderPickupStopModel>? pickupStops;
  final int? pickupProgressCurrentStopIndex;
  final OrderDeliveryModel delivery;
  final OrderRequirementsModel requirements;
  final OrderRiderModel rider;
  final String status;
  final OrderTimestampsModel timestamps;
  final String? cancelReason;
  final String? canceledBy;
  final firestore.Timestamp? paymentExpiresAt;
  final firestore.Timestamp updatedAt;
  final int version;
  final PickupScheduleModel? pickupSchedule;
  final bool useConcierge;
  final ConciergeInfoModel? conciergeInfo;
  final bool inPersonPickup;
  final bool confirmedByHero;
  final double? heroRating;
  final String? heroRatingComment;
  final double? buyerRating;
  final String? buyerRatingComment;
  final String? buyerRatingBySellerId;
  final Map<String, dynamic>? coupon;
  final String? fulfillmentStatus;
  final String? fulfillmentBlockReason;
  final String? supportReviewStatus;

  OrderModel({
    required this.orderId,
    required this.heroId,
    this.sellerHeroIds = const [],
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.serviceFee,
    required this.tax,
    this.tip = 0.0,
    required this.amountTotal,
    required this.currency,
    this.documentType = 'boleta',
    this.invoiceBusinessName,
    this.invoiceRut,
    this.invoiceGiro,
    this.invoiceAddress,
    this.invoiceEmail,
    this.invoicePhone,
    this.billingInvoiceId,
    this.billingInvoiceStatus,
    required this.pickup,
    this.pickupStops,
    this.pickupProgressCurrentStopIndex,
    required this.delivery,
    required this.requirements,
    required this.rider,
    required this.status,
    required this.timestamps,
    this.cancelReason,
    this.canceledBy,
    this.paymentExpiresAt,
    required this.updatedAt,
    this.version = 1,
    this.pickupSchedule,
    this.useConcierge = false,
    this.conciergeInfo,
    this.inPersonPickup = false,
    this.confirmedByHero = false,
    this.heroRating,
    this.heroRatingComment,
    this.buyerRating,
    this.buyerRatingComment,
    this.buyerRatingBySellerId,
    this.coupon,
    this.fulfillmentStatus,
    this.fulfillmentBlockReason,
    this.supportReviewStatus,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // Helper to parse timestamp from either Timestamp or ISO string
    firestore.Timestamp parseTimestamp(dynamic value) {
      if (value is firestore.Timestamp) return value;
      if (value is String) {
        try {
          return firestore.Timestamp.fromDate(DateTime.parse(value));
        } catch (e) {
          return firestore.Timestamp.now();
        }
      }
      return firestore.Timestamp.now();
    }

    final pickupProgress = (json['pickupProgress'] is Map)
        ? (json['pickupProgress'] as Map)
        : null;
    final billing = (json['billing'] is Map) ? (json['billing'] as Map) : null;

    final pickupProgressStopIndexRaw = pickupProgress?['currentStopIndex'];
    final pickupProgressStopIndex = (pickupProgressStopIndexRaw is int)
        ? pickupProgressStopIndexRaw
        : (pickupProgressStopIndexRaw is num)
        ? pickupProgressStopIndexRaw.toInt()
        : null;

    return OrderModel(
      orderId: json['orderId'] as String? ?? '',
      heroId: json['heroId'] as String? ?? '',
      sellerHeroIds:
          (json['sellerHeroIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      items:
          (json['items'] as List<dynamic>?)
              ?.map(
                (item) => OrderItemModel.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['serviceFee'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
      tip: (json['tip'] as num?)?.toDouble() ?? 0.0,
      amountTotal: (json['amountTotal'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'CLP',
      documentType:
          (billing?['documentType'] as String?)?.trim().isNotEmpty == true
          ? (billing?['documentType'] as String).trim()
          : ((json['documentType'] as String?)?.trim().isNotEmpty == true
                ? (json['documentType'] as String).trim()
                : 'boleta'),
      invoiceBusinessName: (json['invoiceBusinessName'] as String?)?.trim(),
      invoiceRut: (json['invoiceRut'] as String?)?.trim(),
      invoiceGiro: (json['invoiceGiro'] as String?)?.trim(),
      invoiceAddress: (json['invoiceAddress'] as String?)?.trim(),
      invoiceEmail: (json['invoiceEmail'] as String?)?.trim(),
      invoicePhone: (json['invoicePhone'] as String?)?.trim(),
      billingInvoiceId:
          (billing?['invoiceId'] as String?)?.trim() ??
          (json['billingInvoiceId'] as String?)?.trim(),
      billingInvoiceStatus:
          (billing?['invoiceStatus'] as String?)?.trim() ??
          (json['billingInvoiceStatus'] as String?)?.trim(),
      pickup: OrderPickupModel.fromJson(
        json['pickup'] as Map<String, dynamic>? ?? {},
      ),
      pickupStops: (json['pickupStops'] as List?)
          ?.whereType<Map>()
          .map((e) => OrderPickupStopModel.fromJson(e.cast<String, dynamic>()))
          .toList(),
      pickupProgressCurrentStopIndex: pickupProgressStopIndex,
      delivery: OrderDeliveryModel.fromJson(
        json['delivery'] as Map<String, dynamic>? ?? {},
      ),
      requirements: OrderRequirementsModel.fromJson(
        json['requirements'] as Map<String, dynamic>? ?? {},
      ),
      rider: OrderRiderModel.fromJson(
        json['rider'] as Map<String, dynamic>? ?? {},
      ),
      status: json['status'] as String? ?? 'created',
      timestamps: OrderTimestampsModel.fromJson(
        json['timestamps'] as Map<String, dynamic>? ?? {},
      ),
      cancelReason: json['cancelReason'] as String?,
      canceledBy: json['canceledBy'] as String?,
      paymentExpiresAt: json['paymentExpiresAt'] != null
          ? parseTimestamp(json['paymentExpiresAt'])
          : null,
      updatedAt: parseTimestamp(json['updatedAt']),
      version: json['version'] as int? ?? 1,
      pickupSchedule: json['pickupSchedule'] != null
          ? PickupScheduleModel.fromJson(
              json['pickupSchedule'] as Map<String, dynamic>,
            )
          : null,
      useConcierge: json['useConcierge'] as bool? ?? false,
      conciergeInfo: json['conciergeInfo'] != null
          ? ConciergeInfoModel.fromJson(
              json['conciergeInfo'] as Map<String, dynamic>,
            )
          : null,
      inPersonPickup: json['inPersonPickup'] as bool? ?? false,
      confirmedByHero: json['confirmedByHero'] as bool? ?? false,
      heroRating: (json['heroRating'] as num?)?.toDouble(),
      heroRatingComment: json['heroRatingComment'] as String?,
      buyerRating: (json['buyerRating'] as num?)?.toDouble(),
      buyerRatingComment: json['buyerRatingComment'] as String?,
      buyerRatingBySellerId: json['buyerRatingBySellerId'] as String?,
      coupon: (json['coupon'] is Map)
          ? (json['coupon'] as Map).cast<String, dynamic>()
          : null,
      fulfillmentStatus: json['fulfillmentStatus'] as String?,
      fulfillmentBlockReason: json['fulfillmentBlockReason'] as String?,
      supportReviewStatus: json['supportReviewStatus'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'heroId': heroId,
      'sellerHeroIds': sellerHeroIds,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'serviceFee': serviceFee,
      'tax': tax,
      'tip': tip,
      'amountTotal': amountTotal,
      'currency': currency,
      'documentType': documentType,
      'invoiceBusinessName': invoiceBusinessName,
      'invoiceRut': invoiceRut,
      'invoiceGiro': invoiceGiro,
      'invoiceAddress': invoiceAddress,
      'invoiceEmail': invoiceEmail,
      'invoicePhone': invoicePhone,
      'billingInvoiceId': billingInvoiceId,
      'billingInvoiceStatus': billingInvoiceStatus,
      'pickup': pickup.toJson(),
      'pickupStops': pickupStops?.map((e) => e.toJson()).toList(),
      'delivery': delivery.toJson(),
      'requirements': requirements.toJson(),
      'rider': rider.toJson(),
      'status': status,
      'timestamps': timestamps.toJson(),
      'cancelReason': cancelReason,
      'canceledBy': canceledBy,
      'paymentExpiresAt': paymentExpiresAt?.toDate().toIso8601String(),
      'updatedAt': updatedAt
          .toDate()
          .toIso8601String(), // Convert to ISO string
      'version': version,
      'pickupSchedule': pickupSchedule?.toJson(),
      'useConcierge': useConcierge,
      'conciergeInfo': conciergeInfo?.toJson(),
      'inPersonPickup': inPersonPickup,
      'confirmedByHero': confirmedByHero,
      'heroRating': heroRating,
      'heroRatingComment': heroRatingComment,
      'buyerRating': buyerRating,
      'buyerRatingComment': buyerRatingComment,
      'buyerRatingBySellerId': buyerRatingBySellerId,
      'coupon': coupon,
      'fulfillmentStatus': fulfillmentStatus,
      'fulfillmentBlockReason': fulfillmentBlockReason,
      'supportReviewStatus': supportReviewStatus,
    };
  }

  Order toEntity() {
    return Order(
      orderId: orderId,
      heroId: heroId,
      sellerHeroIds: sellerHeroIds,
      items: items.map((item) => item.toEntity()).toList(),
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      serviceFee: serviceFee,
      tax: tax,
      tip: tip,
      amountTotal: amountTotal,
      currency: currency,
      documentType: documentType,
      invoiceBusinessName: invoiceBusinessName,
      invoiceRut: invoiceRut,
      invoiceGiro: invoiceGiro,
      invoiceAddress: invoiceAddress,
      invoiceEmail: invoiceEmail,
      invoicePhone: invoicePhone,
      billingInvoiceId: billingInvoiceId,
      billingInvoiceStatus: billingInvoiceStatus,
      pickup: pickup.toEntity(),
      pickupStops: pickupStops?.map((e) => e.toEntity()).toList(),
      pickupProgressCurrentStopIndex: pickupProgressCurrentStopIndex,
      delivery: delivery.toEntity(),
      requirements: requirements.toEntity(),
      rider: rider.toEntity(),
      status: _stringToOrderStatus(status),
      timestamps: timestamps.toEntity(),
      cancelReason: cancelReason,
      canceledBy: canceledBy,
      paymentExpiresAt: paymentExpiresAt?.toDate(),
      updatedAt: updatedAt.toDate(),
      version: version,
      pickupSchedule: pickupSchedule?.toEntity(),
      useConcierge: useConcierge,
      conciergeInfo: conciergeInfo?.toEntity(),
      inPersonPickup: inPersonPickup,
      confirmedByHero: confirmedByHero,
      heroRating: heroRating,
      heroRatingComment: heroRatingComment,
      buyerRating: buyerRating,
      buyerRatingComment: buyerRatingComment,
      buyerRatingBySellerId: buyerRatingBySellerId,
      coupon: coupon,
      fulfillmentStatus: fulfillmentStatus,
      fulfillmentBlockReason: fulfillmentBlockReason,
      supportReviewStatus: supportReviewStatus,
    );
  }

  factory OrderModel.fromEntity(Order entity) {
    return OrderModel(
      orderId: entity.orderId,
      heroId: entity.heroId,
      sellerHeroIds: entity.sellerHeroIds,
      items: entity.items
          .map((item) => OrderItemModel.fromEntity(item))
          .toList(),
      subtotal: entity.subtotal,
      deliveryFee: entity.deliveryFee,
      serviceFee: entity.serviceFee,
      tax: entity.tax,
      tip: entity.tip,
      amountTotal: entity.amountTotal,
      currency: entity.currency,
      documentType: entity.documentType,
      invoiceBusinessName: entity.invoiceBusinessName,
      invoiceRut: entity.invoiceRut,
      invoiceGiro: entity.invoiceGiro,
      invoiceAddress: entity.invoiceAddress,
      invoiceEmail: entity.invoiceEmail,
      invoicePhone: entity.invoicePhone,
      billingInvoiceId: entity.billingInvoiceId,
      billingInvoiceStatus: entity.billingInvoiceStatus,
      pickup: OrderPickupModel.fromEntity(entity.pickup),
      pickupStops: entity.pickupStops
          ?.map(OrderPickupStopModel.fromEntity)
          .toList(),
      delivery: OrderDeliveryModel.fromEntity(entity.delivery),
      requirements: OrderRequirementsModel.fromEntity(entity.requirements),
      rider: OrderRiderModel.fromEntity(entity.rider),
      status: _orderStatusToString(entity.status),
      timestamps: OrderTimestampsModel.fromEntity(entity.timestamps),
      cancelReason: entity.cancelReason,
      canceledBy: entity.canceledBy,
      paymentExpiresAt: entity.paymentExpiresAt != null
          ? firestore.Timestamp.fromDate(entity.paymentExpiresAt!)
          : null,
      updatedAt: firestore.Timestamp.fromDate(entity.updatedAt),
      version: entity.version,
      pickupSchedule: entity.pickupSchedule != null
          ? PickupScheduleModel.fromEntity(entity.pickupSchedule!)
          : null,
      useConcierge: entity.useConcierge,
      conciergeInfo: entity.conciergeInfo != null
          ? ConciergeInfoModel.fromEntity(entity.conciergeInfo!)
          : null,
      inPersonPickup: entity.inPersonPickup,
      confirmedByHero: entity.confirmedByHero,
      heroRating: entity.heroRating,
      heroRatingComment: entity.heroRatingComment,
      buyerRating: entity.buyerRating,
      buyerRatingComment: entity.buyerRatingComment,
      buyerRatingBySellerId: entity.buyerRatingBySellerId,
      coupon: entity.coupon,
      fulfillmentStatus: entity.fulfillmentStatus,
      fulfillmentBlockReason: entity.fulfillmentBlockReason,
      supportReviewStatus: entity.supportReviewStatus,
    );
  }

  static OrderStatus _stringToOrderStatus(String value) {
    switch (value.toLowerCase()) {
      case 'created':
        return OrderStatus.created;
      case 'pending_payment':
      case 'pendingpayment':
        return OrderStatus.pendingPayment;
      case 'payment_failed':
      case 'paymentfailed':
        return OrderStatus.failed;
      case 'refunded':
      case 'charged_back':
      case 'chargedback':
        return OrderStatus.canceled;
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

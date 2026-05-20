import 'order_item.dart';
import 'order_pickup.dart';
import 'order_pickup_stop.dart';
import 'order_delivery.dart';
import 'order_requirements.dart';
import 'order_rider.dart';
import 'order_timestamps.dart';
import 'order_status.dart';
import 'pickup_schedule.dart';
import 'concierge_info.dart';

class Order {
  final String orderId;
  final String heroId;
  final List<String> sellerHeroIds;
  final List<OrderItem> items;
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
  final OrderPickup pickup;
  final List<OrderPickupStop>? pickupStops;
  final int? pickupProgressCurrentStopIndex;
  final OrderDelivery delivery;
  final OrderRequirements requirements;
  final OrderRider rider;
  final OrderStatus status;
  final OrderTimestamps timestamps;
  final String? cancelReason;
  final String? canceledBy;
  final DateTime updatedAt;
  final int version;
  final PickupSchedule? pickupSchedule;
  final bool useConcierge;
  final ConciergeInfo? conciergeInfo;
  final bool inPersonPickup;
  final bool confirmedByHero;
  final double? heroRating;
  final String? heroRatingComment;

  Order({
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
    required this.updatedAt,
    this.version = 1,
    this.pickupSchedule,
    this.useConcierge = false,
    this.conciergeInfo,
    this.inPersonPickup = false,
    this.confirmedByHero = false,
    this.heroRating,
    this.heroRatingComment,
  });

  bool get isAssigned => rider.isAssigned;
  bool get isActive => status.isActive;
  bool get isCompleted => status.isCompleted;
  bool get canBeCanceled => status.canBeCanceled;
  String get effectiveDocumentType {
    final normalized = documentType.trim().toLowerCase();
    if (normalized == 'factura' || normalized == 'boleta') {
      return normalized;
    }

    final hasBillingInvoiceData =
        (billingInvoiceId?.trim().isNotEmpty ?? false) ||
        (billingInvoiceStatus?.trim().isNotEmpty ?? false);
    return hasBillingInvoiceData ? 'factura' : 'boleta';
  }

  bool get isFactura => effectiveDocumentType == 'factura';

  int get totalItems => items.fold(0, (sum, item) => sum + item.qty);

  Order copyWith({
    String? orderId,
    String? heroId,
    List<String>? sellerHeroIds,
    List<OrderItem>? items,
    double? subtotal,
    double? deliveryFee,
    double? serviceFee,
    double? tax,
    double? tip,
    double? amountTotal,
    String? currency,
    String? documentType,
    String? invoiceBusinessName,
    String? invoiceRut,
    String? invoiceGiro,
    String? invoiceAddress,
    String? invoiceEmail,
    String? invoicePhone,
    String? billingInvoiceId,
    String? billingInvoiceStatus,
    OrderPickup? pickup,
    List<OrderPickupStop>? pickupStops,
    OrderDelivery? delivery,
    OrderRequirements? requirements,
    OrderRider? rider,
    OrderStatus? status,
    OrderTimestamps? timestamps,
    String? cancelReason,
    String? canceledBy,
    DateTime? updatedAt,
    int? version,
    PickupSchedule? pickupSchedule,
    bool? useConcierge,
    ConciergeInfo? conciergeInfo,
    bool? inPersonPickup,
    bool? confirmedByHero,
    double? heroRating,
    String? heroRatingComment,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      heroId: heroId ?? this.heroId,
      sellerHeroIds: sellerHeroIds ?? this.sellerHeroIds,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      serviceFee: serviceFee ?? this.serviceFee,
      tax: tax ?? this.tax,
      tip: tip ?? this.tip,
      amountTotal: amountTotal ?? this.amountTotal,
      currency: currency ?? this.currency,
      documentType: documentType ?? this.documentType,
      invoiceBusinessName: invoiceBusinessName ?? this.invoiceBusinessName,
      invoiceRut: invoiceRut ?? this.invoiceRut,
      invoiceGiro: invoiceGiro ?? this.invoiceGiro,
      invoiceAddress: invoiceAddress ?? this.invoiceAddress,
      invoiceEmail: invoiceEmail ?? this.invoiceEmail,
      invoicePhone: invoicePhone ?? this.invoicePhone,
      billingInvoiceId: billingInvoiceId ?? this.billingInvoiceId,
      billingInvoiceStatus: billingInvoiceStatus ?? this.billingInvoiceStatus,
      pickup: pickup ?? this.pickup,
      pickupStops: pickupStops ?? this.pickupStops,
      delivery: delivery ?? this.delivery,
      requirements: requirements ?? this.requirements,
      rider: rider ?? this.rider,
      status: status ?? this.status,
      timestamps: timestamps ?? this.timestamps,
      cancelReason: cancelReason ?? this.cancelReason,
      canceledBy: canceledBy ?? this.canceledBy,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      pickupSchedule: pickupSchedule ?? this.pickupSchedule,
      useConcierge: useConcierge ?? this.useConcierge,
      conciergeInfo: conciergeInfo ?? this.conciergeInfo,
      inPersonPickup: inPersonPickup ?? this.inPersonPickup,
      confirmedByHero: confirmedByHero ?? this.confirmedByHero,
      heroRating: heroRating ?? this.heroRating,
      heroRatingComment: heroRatingComment ?? this.heroRatingComment,
    );
  }
}

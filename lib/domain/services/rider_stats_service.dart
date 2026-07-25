import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../entities/order.dart';
import '../entities/order_status.dart';
import '../entities/rider_stats.dart';
import 'rider_commission_calculator.dart';

class RiderStatsService {
  const RiderStatsService();

  int _toCents(double value) {
    if (!value.isFinite) return 0;
    return (value * 100).round();
  }

  RiderStats computeFromSources({
    required List<Order> orders,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> walletTxDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tripEventDocs,
    required double pendingBalance,
    DateTime? since,
  }) {
    final cutoff = since;

    final completedTrips = orders.where((o) {
      if (o.status != OrderStatus.delivered) return false;
      if (cutoff == null) return true;
      final deliveredAt = o.timestamps.deliveredAt;
      if (deliveredAt == null) return false;
      return !deliveredAt.isBefore(cutoff);
    }).length;

    final canceledByOrderStatus = orders.where((o) {
      if (o.status != OrderStatus.canceled) return false;
      if (cutoff == null) return true;
      final canceledAt = o.timestamps.canceledAt;
      if (canceledAt == null) return false;
      return !canceledAt.isBefore(cutoff);
    }).length;

    final canceledByEvents = tripEventDocs.where((doc) {
      final data = doc.data();
      final type = data['type']?.toString() ?? '';
      if (type != 'canceled_trip') return false;
      if (cutoff == null) return true;
      final createdAt = data['createdAt'];
      if (createdAt is! Timestamp) return false;
      return !createdAt.toDate().isBefore(cutoff);
    }).length;

    final canceledTrips = canceledByOrderStatus + canceledByEvents;

    double totalEarnings = 0.0;
    double totalTips = 0.0;

    int earningsCents = 0;
    int tipsCents = 0;
    bool sawCents = false;
    final deliveryEarningsOrderIds = <String>{};

    for (final doc in walletTxDocs) {
      final data = doc.data();
      final type = data['type']?.toString() ?? '';
      if (type != 'delivery_earnings') continue;

      final orderId = data['orderId']?.toString() ?? '';
      if (orderId.isNotEmpty) {
        deliveryEarningsOrderIds.add(orderId);
      }

      final createdAt = data['createdAt'];
      if (cutoff != null && createdAt is Timestamp) {
        if (createdAt.toDate().isBefore(cutoff)) continue;
      }

      final meta = data['meta'];
      if (meta is! Map) continue;

      final amountCents = (data['amountCents'] as num?)?.toInt();
      if (amountCents != null) {
        sawCents = true;
      }

      final deliveryFee = (meta['deliveryFee'] as num?)?.toDouble() ?? 0.0;
      final commission = RiderCommissionCalculator.calculateCommission(
        deliveryFee: deliveryFee,
      );

      final tipC = (meta['tipCents'] as num?)?.toInt();
      if (tipC != null) {
        sawCents = true;
        tipsCents += tipC;
      } else {
        final tip = (meta['tip'] as num?)?.toDouble() ?? 0.0;
        if (sawCents) {
          tipsCents += _toCents(tip);
        } else {
          totalTips += tip;
        }
      }

      final netC = (meta['netEarningsCents'] as num?)?.toInt();
      if (netC != null) {
        sawCents = true;
        earningsCents += netC;
      } else {
        if (sawCents) {
          earningsCents += _toCents(commission.netEarnings);
        } else {
          totalEarnings += commission.netEarnings;
        }
      }
    }

    for (final order in orders) {
      if (order.status != OrderStatus.delivered) continue;
      if (!order.rider.isCashOrder) continue;
      if (deliveryEarningsOrderIds.contains(order.orderId)) continue;
      if (cutoff != null) {
        final deliveredAt = order.timestamps.deliveredAt;
        if (deliveredAt == null || deliveredAt.isBefore(cutoff)) continue;
      }

      final commission = RiderCommissionCalculator.calculateCommission(
        deliveryFee: order.deliveryFee,
      );
      if (sawCents) {
        earningsCents += _toCents(commission.netEarnings);
        tipsCents += _toCents(order.tip);
      } else {
        totalEarnings += commission.netEarnings;
        totalTips += order.tip;
      }
    }

    if (sawCents) {
      totalEarnings = earningsCents / 100.0;
      totalTips = tipsCents / 100.0;
    }

    return RiderStats(
      totalEarnings: totalEarnings,
      totalTips: totalTips,
      completedTrips: completedTrips,
      canceledTrips: canceledTrips,
      pendingBalance: pendingBalance,
    );
  }
}

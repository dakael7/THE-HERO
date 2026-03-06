import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../entities/rider_earnings_breakdown.dart';

class RiderEarningsBreakdownService {
  const RiderEarningsBreakdownService();

  RiderEarningsBreakdown compute({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> walletTxDocs,
    DateTime? since,
  }) {
    final cutoff = since;

    double earningsOnline = 0.0;
    double earningsCash = 0.0;
    double cashToRender = 0.0;

    int earningsOnlineCents = 0;
    int earningsCashCents = 0;
    int cashToRenderCents = 0;
    bool sawCents = false;

    for (final doc in walletTxDocs) {
      final data = doc.data();
      final type = data['type']?.toString() ?? '';

      final createdAt = data['createdAt'];
      if (cutoff != null && createdAt is Timestamp) {
        if (createdAt.toDate().isBefore(cutoff)) continue;
      }

      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final amountCents = (data['amountCents'] as num?)?.toInt();
      if (amountCents != null) sawCents = true;

      if (type == 'delivery_earnings') {
        final meta = data['meta'];
        final isCashOrder = (meta is Map)
            ? ((meta['isCashOrder'] as bool?) ?? false)
            : false;

        if (amountCents != null) {
          if (isCashOrder) {
            earningsCashCents += amountCents;
          } else {
            earningsOnlineCents += amountCents;
          }
        } else {
          if (isCashOrder) {
            earningsCash += amount;
          } else {
            earningsOnline += amount;
          }
        }
      } else if (type == 'cash_settlement') {
        // amount is negative when rider renders cash
        if (amountCents != null) {
          cashToRenderCents += (-amountCents);
        } else {
          cashToRender += (-amount);
        }
      }
    }

    if (sawCents) {
      earningsOnline = earningsOnlineCents / 100.0;
      earningsCash = earningsCashCents / 100.0;
      cashToRender = cashToRenderCents / 100.0;
    }

    return RiderEarningsBreakdown(
      earningsOnline: earningsOnline,
      earningsCash: earningsCash,
      cashToRender: cashToRender,
    );
  }
}

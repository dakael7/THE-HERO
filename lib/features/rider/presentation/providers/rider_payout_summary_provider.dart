import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';

class RiderMonthlyPayoutSummary {
  final double earningsMonth;
  final double cashSettledMonth;
  final double payableMonth;
  final double tipsMonth;

  const RiderMonthlyPayoutSummary({
    required this.earningsMonth,
    required this.cashSettledMonth,
    required this.payableMonth,
    required this.tipsMonth,
  });
}

final riderMonthlyPayoutSummaryProvider = StreamProvider.autoDispose
    .family<RiderMonthlyPayoutSummary?, String>((ref, riderId) {
  final auth = ref.watch(firebaseAuthProvider);
  final currentUid = auth.currentUser?.uid;
  if (currentUid == null || currentUid != riderId) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  final userRef = firestore.collection('users').doc(riderId);

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final monthStartTs = Timestamp.fromDate(monthStart);

  final txQuery = userRef
      .collection('riderWalletTransactions')
      .where('createdAt', isGreaterThanOrEqualTo: monthStartTs)
      .orderBy('createdAt', descending: true);

  return txQuery.snapshots().map((snapshot) {
    double earnings = 0.0;
    double cashSettled = 0.0;
    double tips = 0.0;

    int earningsCents = 0;
    int cashSettledCents = 0;
    int tipsCents = 0;
    bool sawCents = false;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = data['type']?.toString() ?? '';
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final amountCents = (data['amountCents'] as num?)?.toInt();
      if (amountCents != null) {
        sawCents = true;
      }

      if (type == 'delivery_earnings') {
        if (amountCents != null) {
          earningsCents += amountCents;
        } else {
          earnings += amount;
        }

        final meta = data['meta'];
        if (meta is Map) {
          final tip = (meta['tip'] as num?)?.toDouble() ?? 0.0;
          final tipC = (meta['tipCents'] as num?)?.toInt();
          if (tipC != null) {
            sawCents = true;
            tipsCents += tipC;
          } else {
            tips += tip;
          }
        }
      } else if (type == 'cash_settlement') {
        if (amountCents != null) {
          cashSettledCents += amountCents;
        } else {
          cashSettled += amount;
        }
      }
    }

    if (sawCents) {
      earnings = earningsCents / 100.0;
      cashSettled = cashSettledCents / 100.0;
      tips = tipsCents / 100.0;
    }

    final payable = earnings + cashSettled;

    return RiderMonthlyPayoutSummary(
      earningsMonth: earnings,
      cashSettledMonth: cashSettled,
      payableMonth: payable,
      tipsMonth: tips,
    );
  });
});

final riderPendingEarningsProvider = StreamProvider.autoDispose
    .family<double?, String>((ref, riderId) {
  final auth = ref.watch(firebaseAuthProvider);
  final currentUid = auth.currentUser?.uid;
  if (currentUid == null || currentUid != riderId) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  final userRef = firestore.collection('users').doc(riderId);
  return userRef.snapshots().map((snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;

    final wallet = (data['riderWallet'] is Map)
        ? (data['riderWallet'] as Map)
        : const <String, dynamic>{};

    final cents = (wallet['earningsBalanceCents'] as num?)?.toInt();
    if (cents != null) {
      return cents / 100.0;
    }

    return (wallet['earningsBalance'] as num?)?.toDouble() ?? 0.0;
  });
});

final riderPendingTipsProvider = StreamProvider.autoDispose
    .family<double?, String>((ref, riderId) {
  final auth = ref.watch(firebaseAuthProvider);
  final currentUid = auth.currentUser?.uid;
  if (currentUid == null || currentUid != riderId) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  final userRef = firestore.collection('users').doc(riderId);

  final txQuery = userRef
      .collection('riderWalletTransactions')
      .orderBy('createdAt', descending: true);

  return txQuery.snapshots().map((snapshot) {
    double tips = 0.0;
    int tipsCents = 0;
    bool sawCents = false;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = data['type']?.toString() ?? '';

      if (type == 'payout') {
        final meta = data['meta'];
        final isPartial = (meta is Map)
            ? ((meta['isPartial'] as bool?) ?? false)
            : false;
        if (!isPartial) {
          break;
        }
        continue;
      }

      if (type != 'delivery_earnings') continue;

      final meta = data['meta'];
      if (meta is! Map) continue;

      final isCashOrder = (meta['isCashOrder'] as bool?) ?? false;
      if (isCashOrder) {
        continue;
      }

      final tipC = (meta['tipCents'] as num?)?.toInt();
      if (tipC != null) {
        sawCents = true;
        tipsCents += tipC;
      } else {
        tips += (meta['tip'] as num?)?.toDouble() ?? 0.0;
      }
    }

    if (sawCents) {
      tips = tipsCents / 100.0;
    }
    return tips;
  });
});

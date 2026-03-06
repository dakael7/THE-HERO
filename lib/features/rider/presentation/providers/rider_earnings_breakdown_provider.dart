import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/rider_earnings_breakdown.dart';
import '../../../../domain/services/rider_earnings_breakdown_service.dart';

final riderEarningsBreakdownProvider = StreamProvider.autoDispose
    .family<RiderEarningsBreakdown?, String>((ref, riderId) {
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

  final service = const RiderEarningsBreakdownService();

  return userRef.snapshots().asyncExpand((userSnap) {
    if (!userSnap.exists) return Stream.value(null);

    final data = userSnap.data() ?? <String, dynamic>{};
    final wallet = (data['riderWallet'] is Map)
        ? (data['riderWallet'] as Map)
        : const <String, dynamic>{};

    final lastPayoutAtRaw = wallet['lastPayoutAt'];
    DateTime? lastPayoutAt;
    if (lastPayoutAtRaw is Timestamp) {
      lastPayoutAt = lastPayoutAtRaw.toDate();
    }

    return txQuery.snapshots().map((txSnap) {
      return service.compute(
        walletTxDocs: txSnap.docs,
        since: lastPayoutAt,
      );
    });
  });
});

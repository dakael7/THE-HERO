import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/order.dart';
import '../../../../domain/entities/rider_stats.dart';
import '../../../../domain/providers/orders_usecase_providers.dart';
import '../../../../domain/services/rider_stats_service.dart';

final riderCumulativeStatsProvider = StreamProvider.autoDispose
    .family<RiderStats?, String>((ref, riderId) {
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
  final tripEventsQuery = userRef
      .collection('riderTripEvents')
      .orderBy('createdAt', descending: true);

  final ordersUseCase = ref.read(getOrdersByRiderUseCaseProvider);
  final service = const RiderStatsService();

  final controller = StreamController<RiderStats?>.broadcast();

  DocumentSnapshot<Map<String, dynamic>>? latestUser;
  QuerySnapshot<Map<String, dynamic>>? latestTx;
  QuerySnapshot<Map<String, dynamic>>? latestTripEvents;
  List<Order>? latestOrders;

  void emitIfReady() {
    final userSnap = latestUser;
    final txSnap = latestTx;
    final tripEventsSnap = latestTripEvents;
    final orders = latestOrders;
    if (userSnap == null || txSnap == null || tripEventsSnap == null || orders == null) {
      return;
    }
    if (!userSnap.exists) {
      controller.add(null);
      return;
    }

    final data = userSnap.data() ?? <String, dynamic>{};
    final wallet = (data['riderWallet'] is Map)
        ? (data['riderWallet'] as Map)
        : const <String, dynamic>{};

    final lastPayoutAtRaw = wallet['lastPayoutAt'];
    DateTime? lastPayoutAt;
    if (lastPayoutAtRaw is Timestamp) {
      lastPayoutAt = lastPayoutAtRaw.toDate();
    }

    final cents = (wallet['earningsBalanceCents'] as num?)?.toInt();
    final pendingBalance = cents != null
        ? (cents / 100.0)
        : (wallet['earningsBalance'] as num?)?.toDouble() ?? 0.0;

    final stats = service.computeFromSources(
      orders: orders,
      walletTxDocs: txSnap.docs,
      tripEventDocs: tripEventsSnap.docs,
      pendingBalance: pendingBalance,
      since: lastPayoutAt,
    );
    controller.add(stats);
  }

  final userSub = userRef.snapshots().listen((snap) {
    latestUser = snap;
    emitIfReady();
  }, onError: controller.addError);

  final txSub = txQuery.snapshots().listen((snap) {
    latestTx = snap;
    emitIfReady();
  }, onError: controller.addError);

  final tripEventsSub = tripEventsQuery.snapshots().listen((snap) {
    latestTripEvents = snap;
    emitIfReady();
  }, onError: controller.addError);

  final ordersSub = ordersUseCase.execute(riderId).listen((list) {
    latestOrders = list;
    emitIfReady();
  }, onError: controller.addError);

  ref.onDispose(() {
    userSub.cancel();
    txSub.cancel();
    tripEventsSub.cancel();
    ordersSub.cancel();
    controller.close();
  });

  return controller.stream;
});

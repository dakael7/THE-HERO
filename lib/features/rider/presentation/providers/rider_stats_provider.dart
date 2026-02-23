import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';

final riderStatsProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((
  ref,
  riderId,
) {
  final auth = ref.watch(firebaseAuthProvider);
  final currentUid = auth.currentUser?.uid;
  if (currentUid == null || currentUid != riderId) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore
      .collection('rider_stats')
      .doc(riderId)
      .snapshots()
      .map((doc) => doc.data());
});

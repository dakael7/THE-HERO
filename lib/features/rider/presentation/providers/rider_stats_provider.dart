import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';

final riderStatsProvider = StreamProvider.family<Map<String, dynamic>?, String>((
  ref,
  riderId,
) {
  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore
      .collection('rider_stats')
      .doc(riderId)
      .snapshots()
      .map((doc) => doc.data());
});

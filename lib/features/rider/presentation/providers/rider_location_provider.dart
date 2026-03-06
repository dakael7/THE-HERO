import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/location_entity.dart';
import '../../../orders/presentation/providers/orders_provider.dart';

/// Provider that streams the rider's real-time location from Firestore
/// for a specific order. This reads from orders/{orderId}/rider_location/{riderId}
final riderLocationForOrderProvider = StreamProvider.autoDispose
    .family<LocationEntity?, String>((ref, orderId) {
      final firestore = FirebaseFirestore.instance;

      // Prefer the assigned rider's doc if we can resolve it from the order.
      final orderAsync = ref.watch(orderByIdProvider(orderId));
      final assignedRiderId = orderAsync.maybeWhen(
        data: (o) => o?.rider.assignedRiderId,
        orElse: () => null,
      );

      if (assignedRiderId == null || assignedRiderId.trim().isEmpty) {
        return Stream.value(null);
      }

      return firestore
          .collection('orders')
          .doc(orderId)
          .collection('rider_location')
          .doc(assignedRiderId)
          .snapshots()
          .map((doc) {
            final data = doc.data();
            if (data == null) return null;

            final geo = data['geo'] as GeoPoint?;
            if (geo == null) return null;

            final updatedAt = data['updatedAt'];
            final ts = updatedAt is Timestamp ? updatedAt.toDate() : null;

            return LocationEntity(
              latitude: geo.latitude,
              longitude: geo.longitude,
              accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0.0,
              timestamp: ts ?? DateTime.now(),
            );
          });
    });

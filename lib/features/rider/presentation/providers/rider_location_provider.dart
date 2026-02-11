import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/location_entity.dart';

/// Provider that streams the rider's real-time location from Firestore
/// for a specific order. This reads from orders/{orderId}/rider_location/{riderId}
final riderLocationForOrderProvider = StreamProvider.autoDispose
    .family<LocationEntity?, String>((ref, orderId) {
      final firestore = FirebaseFirestore.instance;

      return firestore
          .collection('orders')
          .doc(orderId)
          .collection('rider_location')
          .snapshots()
          .map((snapshot) {
            if (snapshot.docs.isEmpty) {
              return null;
            }

            // Get the first (and should be only) rider location document
            final doc = snapshot.docs.first;
            final data = doc.data();

            final geo = data['geo'] as GeoPoint?;
            if (geo == null) return null;

            return LocationEntity(
              latitude: geo.latitude,
              longitude: geo.longitude,
              accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0.0,
              timestamp: DateTime.now(),
            );
          });
    });

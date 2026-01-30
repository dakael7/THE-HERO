import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../domain/entities/location_entity.dart';
import '../../../../domain/repositories/location_repository.dart';

class RiderTrackingService {
  final FirebaseFirestore firestore;
  final LocationRepository locationRepository;

  RiderTrackingService({required this.firestore, required this.locationRepository});

  /// Starts streaming rider location to orders/{orderId}/rider_location/{riderId}
  Future<StreamSubscription<LocationEntity>> startTracking({
    required String orderId,
    required String riderId,
  }) async {
    final collection = firestore
        .collection('orders')
        .doc(orderId)
        .collection('rider_location');

    final sub = locationRepository.getLocationStream().listen((loc) async {
      final data = {
        'riderId': riderId,
        'geo': GeoPoint(loc.latitude, loc.longitude),
        'accuracy': loc.accuracy,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await collection.doc(riderId).set(data, SetOptions(merge: true));
    });

    return sub;
  }
}

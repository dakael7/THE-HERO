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

    final servicesEnabled = await locationRepository.isLocationServiceEnabled();
    if (!servicesEnabled) {
      throw Exception('Servicios de ubicación desactivados');
    }

    var granted = await locationRepository.checkPermissions();
    if (!granted) {
      granted = await locationRepository.requestPermissions();
    }
    if (!granted) {
      throw Exception('Permisos de ubicación no otorgados');
    }

    // Initial write to ensure map has at least one rider marker quickly.
    try {
      final initial = await locationRepository.getCurrentLocation();
      await collection.doc(riderId).set(
        {
          'riderId': riderId,
          'geo': GeoPoint(initial.latitude, initial.longitude),
          'accuracy': initial.accuracy,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      // Do not block tracking stream for initial write failures.
      // ignore
    }

    DateTime lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);
    const minWriteInterval = Duration(seconds: 3);

    final sub = locationRepository.getLocationStream().listen(
      (loc) async {
        final now = DateTime.now();
        if (now.difference(lastWriteAt) < minWriteInterval) return;
        lastWriteAt = now;

        final data = {
          'riderId': riderId,
          'geo': GeoPoint(loc.latitude, loc.longitude),
          'accuracy': loc.accuracy,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        try {
          await collection.doc(riderId).set(data, SetOptions(merge: true));
        } catch (e) {
          // Surface issues during development.
          // ignore: avoid_print
          print('⚠️ RiderTrackingService write failed: $e');
        }
      },
      onError: (e) {
        // ignore: avoid_print
        print('⚠️ RiderTrackingService stream error: $e');
      },
    );

    return sub;
  }
}

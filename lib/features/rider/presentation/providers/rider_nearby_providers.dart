import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../data/repositories/location_repository_impl.dart';
import '../../../../domain/entities/location_entity.dart';
import '../../../../domain/entities/vehicle.dart';
import '../../../../domain/repositories/location_repository.dart';
import '../../../../features/orders/presentation/providers/orders_provider.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../domain/entities/nearby_order.dart';

// Repository provider (independent from map feature to avoid coupling)
final riderLocationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepositoryImpl();
});

// Stream of rider location updates
final riderLocationStreamProvider = StreamProvider.autoDispose<LocationEntity>((
  ref,
) {
  final repo = ref.read(riderLocationRepositoryProvider);
  return repo.getLocationStream();
});

// Radius (meters) by vehicle type
const _radiusByVehicle = {
  VehicleType.bicycle: 3000.0,
  VehicleType.motorcycle: 8000.0,
  VehicleType.car: 12000.0,
  VehicleType.truck: 20000.0,
};

final nearbyOrdersProvider =
    AsyncNotifierProvider.autoDispose<NearbyOrdersNotifier, List<NearbyOrder>>(
      NearbyOrdersNotifier.new,
    );

class NearbyOrdersNotifier extends AsyncNotifier<List<NearbyOrder>> {
  @override
  FutureOr<List<NearbyOrder>> build() async {
    print('🔍 [NearbyOrders] Starting build...');

    final profile = await ref.watch(profileProvider.future);
    print('👤 [NearbyOrders] Profile loaded: ${profile?.id}');

    final vehicle = profile?.riderProfile?.vehicle;
    print('🚗 [NearbyOrders] Vehicle: ${vehicle?.type.name}');

    if (vehicle == null) {
      print('⚠️ [NearbyOrders] No vehicle found, returning empty list');
      return [];
    }

    // Wait for both location and orders to be available
    print('⏳ [NearbyOrders] Waiting for location and orders...');
    final loc = await ref.watch(riderLocationStreamProvider.future);
    print(
      '📍 [NearbyOrders] Location received: ${loc.latitude}, ${loc.longitude}',
    );

    final orders = await ref.watch(
      availableOrdersProvider(vehicle.type).future,
    );
    print('📦 [NearbyOrders] Available orders count: ${orders.length}');

    if (orders.isEmpty) {
      print('⚠️ [NearbyOrders] No available orders found');
      return [];
    }

    final radius = _radiusByVehicle[vehicle.type] ?? 5000.0;
    print('📏 [NearbyOrders] Search radius: ${radius}m');

    final distanceCalc = Distance();

    final list =
        orders
            .map((o) {
              final hasGeo =
                  o.pickup.geo.latitude != 0 && o.pickup.geo.longitude != 0;

              if (!hasGeo) {
                print(
                  '⚠️ [NearbyOrders] Order ${o.orderId} has no valid geo coordinates',
                );
                return NearbyOrder(order: o, distanceMeters: null);
              }
              final distance = distanceCalc.as(
                LengthUnit.Meter,
                LatLng(loc.latitude, loc.longitude),
                LatLng(o.pickup.geo.latitude, o.pickup.geo.longitude),
              );

              print(
                '📦 [NearbyOrders] Order ${o.orderId}: distance=${distance.toStringAsFixed(0)}m, pickup=(${o.pickup.geo.latitude}, ${o.pickup.geo.longitude})',
              );
              return NearbyOrder(order: o, distanceMeters: distance);
            })
            .where((n) {
              // If we have distance, enforce radius; if not, include it so it is visible.
              if (n.distanceMeters == null) {
                print(
                  '✅ [NearbyOrders] Including order ${n.order.orderId} (no distance)',
                );
                return true;
              }
              final withinRadius = n.distanceMeters! <= radius;
              print(
                '${withinRadius ? "✅" : "❌"} [NearbyOrders] Order ${n.order.orderId}: ${n.distanceMeters!.toStringAsFixed(0)}m ${withinRadius ? "within" : "outside"} ${radius}m radius',
              );
              return withinRadius;
            })
            .toList()
          ..sort((a, b) {
            final da = a.distanceMeters;
            final db = b.distanceMeters;
            if (da == null && db == null) return 0;
            if (da == null) return 1; // put unknowns last
            if (db == null) return -1;
            return da.compareTo(db);
          });

    print('✅ [NearbyOrders] Final nearby orders count: ${list.length}');
    return list;
  }
}

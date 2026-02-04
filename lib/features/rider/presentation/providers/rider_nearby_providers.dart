import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../data/repositories/location_repository_impl.dart';
import '../../../../domain/entities/location_entity.dart';
import '../../../../domain/entities/order.dart';
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
  LocationEntity? _lastLoc;
  List<Order>? _lastOrders;
  double? _radius;

  @override
  FutureOr<List<NearbyOrder>> build() async {
    print('🔍 [NearbyOrders] Starting reactive build...');

    final profile = await ref.watch(profileProvider.future);
    print('👤 [NearbyOrders] Profile loaded: ${profile?.id}');

    final vehicle = profile?.riderProfile?.vehicle;
    print('🚗 [NearbyOrders] Vehicle: ${vehicle?.type.name}');

    if (vehicle == null) {
      print('⚠️ [NearbyOrders] No vehicle found, returning empty list');
      return [];
    }

    final radius = _radiusByVehicle[vehicle.type] ?? 5000.0;
    _radius = radius;
    print('📏 [NearbyOrders] Search radius: ${radius}m');

    ref.listen(riderLocationStreamProvider, (prev, next) {
      if (next.hasError) {
        state = AsyncValue.error(next.error!, next.stackTrace!);
        return;
      }
      if (!next.hasValue) return;
      _lastLoc = next.value;
      _recompute();
    });

    ref.listen(availableOrdersProvider(vehicle.type), (prev, next) {
      if (next.hasError) {
        state = AsyncValue.error(next.error!, next.stackTrace!);
        return;
      }
      if (!next.hasValue) return;
      _lastOrders = next.value;
      _recompute();
    });

    // We start with empty list; listeners will push the real value when ready.
    return const [];
  }

  void _recompute() {
    final loc = _lastLoc;
    final orders = _lastOrders;
    final radius = _radius;
    if (orders == null || radius == null) return;

    // If we don't have a rider location yet (permissions/GPS not ready), we still
    // expose the orders so the rider can see and claim them. Distance will be
    // shown as "no disponible" in the UI.
    if (loc == null) {
      state = AsyncValue.data(
        orders
            .map((o) => NearbyOrder(order: o, distanceMeters: null))
            .toList(),
      );
      return;
    }

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

              return NearbyOrder(order: o, distanceMeters: distance);
            })
            .where((n) {
              if (n.distanceMeters == null) return true;
              return n.distanceMeters! <= radius;
            })
            .toList()
          ..sort((a, b) {
            final da = a.distanceMeters;
            final db = b.distanceMeters;
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          });

    state = AsyncValue.data(list);
  }
}

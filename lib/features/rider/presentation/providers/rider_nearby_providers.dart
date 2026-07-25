import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/env.dart';
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

// Max order distance (km) by vehicle type (pickup(s) -> delivery)
const _maxOrderDistanceKmByVehicle = {VehicleType.bicycle: 3.5};

final nearbyOrdersProvider =
    AsyncNotifierProvider.autoDispose<NearbyOrdersNotifier, List<NearbyOrder>>(
      NearbyOrdersNotifier.new,
    );

class NearbyOrdersNotifier extends AsyncNotifier<List<NearbyOrder>> {
  LocationEntity? _lastLoc;
  List<Order>? _lastOrders;
  double? _radius;
  double? _maxOrderKm;

  @override
  FutureOr<List<NearbyOrder>> build() async {
    developer.log('🔍 [NearbyOrders] Starting reactive build...');

    final profile = await ref.watch(profileStreamProvider.future);
    developer.log('👤 [NearbyOrders] Profile loaded: ${profile?.id}');

    final devCheckoutBypass = Env.devCheckoutBypass;
    final riderProfile = profile?.riderProfile;
    final vehicle = riderProfile?.activeVehicle;
    final vehicleType = devCheckoutBypass ? VehicleType.truck : vehicle?.type;
    if (vehicle != null) {
      developer.log('🚗 [NearbyOrders] Vehicle: ${vehicle.type.name}');
    } else {
      developer.log('🚗 [NearbyOrders] Vehicle: null');
    }

    if (vehicleType == null || (!devCheckoutBypass && riderProfile == null)) {
      developer.log('⚠️ [NearbyOrders] No vehicle found, returning empty list');
      return [];
    }

    final radius = devCheckoutBypass
        ? double.infinity
        : (_radiusByVehicle[vehicleType] ?? 5000.0);
    _radius = radius;
    developer.log('📏 [NearbyOrders] Search radius: ${radius}m');

    if (devCheckoutBypass) {
      _maxOrderKm = null;
    } else {
      final maxByVehicleKm = _maxOrderDistanceKmByVehicle[vehicleType];
      final maxByProfileKm = riderProfile!.activeLimits.maxDistanceKm;
      final hasProfileCap =
          maxByProfileKm.isFinite && !maxByProfileKm.isInfinite;

      if (maxByVehicleKm == null && !hasProfileCap) {
        _maxOrderKm = null;
      } else if (maxByVehicleKm == null) {
        _maxOrderKm = maxByProfileKm;
      } else if (!hasProfileCap) {
        _maxOrderKm = maxByVehicleKm;
      } else {
        _maxOrderKm = (maxByVehicleKm < maxByProfileKm)
            ? maxByVehicleKm
            : maxByProfileKm;
      }
    }

    ref.listen(riderLocationStreamProvider, (prev, next) {
      if (next.hasError) {
        state = AsyncValue.error(next.error!, next.stackTrace!);
        return;
      }
      if (!next.hasValue) return;
      _lastLoc = next.value;
      _recompute();
    });

    ref.listen(availableOrdersProvider(vehicleType), (prev, next) {
      if (next.hasError) {
        state = AsyncValue.error(next.error!, next.stackTrace!);
        return;
      }
      if (!next.hasValue) return;
      _lastOrders = next.value;
      _recompute();
    });

    return const [];
  }

  void _recompute() {
    final loc = _lastLoc;
    final orders = _lastOrders;
    final radius = _radius;
    final maxOrderKm = _maxOrderKm;
    if (orders == null || radius == null) return;

    if (loc == null) {
      final distanceCalc = Distance();
      state = AsyncValue.data(
        orders
            .where((o) {
              if (maxOrderKm == null) return true;
              final km = _computeOrderDistanceKm(distanceCalc, o);
              if (km == null) return false;
              return km <= maxOrderKm;
            })
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
                developer.log(
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
            .where((n) {
              if (maxOrderKm == null) return true;
              final km = _computeOrderDistanceKm(distanceCalc, n.order);
              if (km == null) return false;
              return km <= maxOrderKm;
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

  double? _computeOrderDistanceKm(Distance distanceCalc, Order o) {
    final delivery = o.delivery.geo;
    if (delivery.latitude == 0 || delivery.longitude == 0) return null;

    final pickupStops = o.pickupStops;
    final List<GeoPoint> pickupPoints =
        (pickupStops != null && pickupStops.isNotEmpty)
        ? pickupStops.map((s) => s.geo).toList(growable: false)
        : <GeoPoint>[o.pickup.geo];

    if (pickupPoints.isEmpty) return null;

    double meters = 0.0;
    for (int i = 0; i < pickupPoints.length - 1; i++) {
      final a = pickupPoints[i];
      final b = pickupPoints[i + 1];
      if (a.latitude == 0 || a.longitude == 0) return null;
      if (b.latitude == 0 || b.longitude == 0) return null;
      meters += distanceCalc.as(
        LengthUnit.Meter,
        LatLng(a.latitude, a.longitude),
        LatLng(b.latitude, b.longitude),
      );
    }

    final last = pickupPoints.last;
    if (last.latitude == 0 || last.longitude == 0) return null;
    meters += distanceCalc.as(
      LengthUnit.Meter,
      LatLng(last.latitude, last.longitude),
      LatLng(delivery.latitude, delivery.longitude),
    );

    final km = meters / 1000;
    if (!km.isFinite || km < 0) return null;
    return km;
  }
}

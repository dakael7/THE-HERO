import 'vehicle.dart';
import 'documents.dart';
import 'limits.dart';
import 'verification.dart';

class RiderProfile {
  final String? rut;
  final bool isActive;
  final bool isVerified;
  final String? activeVehicleType;
  final Map<String, dynamic> vehicles;
  final Vehicle vehicle;
  final Documents documents;
  final Limits limits;
  final Verification? verification;
  final int deliveredOrders;
  final double rating;
  final int totalRatings;

  RiderProfile({
    this.rut,
    this.isActive = false,
    this.isVerified = false,
    this.activeVehicleType,
    this.vehicles = const {},
    required this.vehicle,
    required this.documents,
    required this.limits,
    this.verification,
    this.deliveredOrders = 0,
    this.rating = 0.0,
    this.totalRatings = 0,
  });

  String get activeVehicleTypeResolved {
    return activeVehicleType ?? vehicle.type.name;
  }

  Map<String, dynamic>? get activeVehicleEntry {
    final key = activeVehicleTypeResolved;
    final entry = vehicles[key];
    return entry is Map ? Map<String, dynamic>.from(entry) : null;
  }

  VehicleType get activeVehicleTypeEnum {
    return VehicleType.fromString(activeVehicleTypeResolved);
  }

  Vehicle get activeVehicle {
    final entry = activeVehicleEntry;
    final v = entry?['vehicle'];
    if (v is Map) {
      final typeRaw = v['type']?.toString() ?? activeVehicleTypeResolved;
      final type = VehicleType.fromString(typeRaw);
      return Vehicle(
        type: type,
        plateNumber: v['plateNumber']?.toString(),
        model: v['model']?.toString(),
        year: v['year'] is num ? (v['year'] as num).toInt() : null,
        color: v['color']?.toString(),
      );
    }
    // Fallback for legacy riders without `vehicles[activeVehicleType]` entry.
    // Respect the selected activeVehicleType to avoid fetching/claiming orders
    // with an incorrect vehicle type.
    return vehicle.copyWith(type: activeVehicleTypeEnum);
  }

  Documents get activeDocuments {
    final entry = activeVehicleEntry;
    final d = entry?['documents'];
    if (d is Map) {
      return Documents(
        idCardUrl:
            d['idCardUrl']?.toString() ?? d['idCardFrontUrl']?.toString() ?? '',
        licenseUrl: d['licenseUrl']?.toString() ?? d['licenseFrontUrl']?.toString(),
        padronUrl:
            d['padronUrl']?.toString() ?? d['circulationPermitUrl']?.toString(),
      );
    }
    return documents;
  }

  Limits get activeLimits {
    final entry = activeVehicleEntry;
    final l = entry?['limits'];
    if (l is Map) {
      return Limits(
        maxWeightKg: (l['maxWeightKg'] as num?)?.toDouble() ?? limits.maxWeightKg,
        maxDistanceKm:
            (l['maxDistanceKm'] as num?)?.toDouble() ?? limits.maxDistanceKm,
      );
    }
    return limits;
  }

  String? get activeVerificationStatus {
    final entry = activeVehicleEntry;
    final v = entry?['verification'];
    if (v is Map) {
      return v['status']?.toString();
    }
    return null;
  }

  bool get isActiveVehicleVerified {
    final status = activeVerificationStatus;
    return status == 'approved' || status == 'not_required';
  }

  bool get isComplete {
    final v = activeVehicle;
    final d = activeDocuments;
    return v.isValid &&
        d.isValidForVehicle(v.type) &&
        isActiveVehicleVerified;
  }

  bool get canAcceptDeliveries {
    return isActive && isVerified && isComplete;
  }

  String get activeVehicleTypeOrLegacy {
    return activeVehicleTypeResolved;
  }

  RiderProfile copyWith({
    String? rut,
    bool? isActive,
    bool? isVerified,
    String? activeVehicleType,
    Map<String, dynamic>? vehicles,
    Vehicle? vehicle,
    Documents? documents,
    Limits? limits,
    Verification? verification,
    int? deliveredOrders,
    double? rating,
    int? totalRatings,
  }) {
    return RiderProfile(
      rut: rut ?? this.rut,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      activeVehicleType: activeVehicleType ?? this.activeVehicleType,
      vehicles: vehicles ?? this.vehicles,
      vehicle: vehicle ?? this.vehicle,
      documents: documents ?? this.documents,
      limits: limits ?? this.limits,
      verification: verification ?? this.verification,
      deliveredOrders: deliveredOrders ?? this.deliveredOrders,
      rating: rating ?? this.rating,
      totalRatings: totalRatings ?? this.totalRatings,
    );
  }
}

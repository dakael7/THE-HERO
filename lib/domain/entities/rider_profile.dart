import 'vehicle.dart';
import 'documents.dart';
import 'limits.dart';
import 'verification.dart';

class RiderProfile {
  final bool isActive;
  final bool isVerified;
  final Vehicle vehicle;
  final Documents documents;
  final Limits limits;
  final Verification? verification;
  final int deliveredOrders;
  final double rating;

  RiderProfile({
    this.isActive = false,
    this.isVerified = false,
    required this.vehicle,
    required this.documents,
    required this.limits,
    this.verification,
    this.deliveredOrders = 0,
    this.rating = 0.0,
  });

  bool get isComplete {
    return vehicle.isValid && 
           documents.isValidForVehicle(vehicle.type) &&
           verification != null &&
           verification!.isRecent;
  }

  bool get canAcceptDeliveries {
    return isActive && isVerified && isComplete;
  }

  RiderProfile copyWith({
    bool? isActive,
    bool? isVerified,
    Vehicle? vehicle,
    Documents? documents,
    Limits? limits,
    Verification? verification,
    int? deliveredOrders,
    double? rating,
  }) {
    return RiderProfile(
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      vehicle: vehicle ?? this.vehicle,
      documents: documents ?? this.documents,
      limits: limits ?? this.limits,
      verification: verification ?? this.verification,
      deliveredOrders: deliveredOrders ?? this.deliveredOrders,
      rating: rating ?? this.rating,
    );
  }
}

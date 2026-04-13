import '../../domain/entities/rider_profile.dart';
import 'vehicle_model.dart';
import 'documents_model.dart';
import 'limits_model.dart';
import 'verification_model.dart';

class RiderProfileModel {
  final String? rut;
  final bool isActive;
  final bool isVerified;
  final String? activeVehicleType;
  final Map<String, dynamic> vehicles;
  final VehicleModel vehicle;
  final DocumentsModel documents;
  final LimitsModel limits;
  final VerificationModel? verification;
  final int deliveredOrders;
  final double rating;
  final int totalRatings;

  RiderProfileModel({
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

  factory RiderProfileModel.fromJson(Map<String, dynamic> json) {
    return RiderProfileModel(
      rut: json['rut']?.toString(),
      isActive: json['isActive'] as bool? ?? false,
      isVerified: json['isVerified'] as bool? ?? false,
      activeVehicleType: json['activeVehicleType'] as String?,
      vehicles: (json['vehicles'] as Map<String, dynamic>?) ?? const {},
      vehicle: VehicleModel.fromJson(
        json['vehicle'] as Map<String, dynamic>? ?? {},
      ),
      documents: DocumentsModel.fromJson(
        json['documents'] as Map<String, dynamic>? ?? {},
      ),
      limits: LimitsModel.fromJson(
        json['limits'] as Map<String, dynamic>? ?? {},
      ),
      verification: json['verification'] != null
          ? VerificationModel.fromJson(
              json['verification'] as Map<String, dynamic>,
            )
          : null,
      deliveredOrders: (json['deliveredOrders'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalRatings: (json['totalRatings'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rut': rut,
      'isActive': isActive,
      'isVerified': isVerified,
      'activeVehicleType': activeVehicleType,
      'vehicles': vehicles,
      'vehicle': vehicle.toJson(),
      'documents': documents.toJson(),
      'limits': limits.toJson(),
      'verification': verification?.toJson(),
      'deliveredOrders': deliveredOrders,
      'rating': rating,
      'totalRatings': totalRatings,
    };
  }

  RiderProfile toEntity() {
    return RiderProfile(
      rut: rut,
      isActive: isActive,
      isVerified: isVerified,
      activeVehicleType: activeVehicleType,
      vehicles: vehicles,
      vehicle: vehicle.toEntity(),
      documents: documents.toEntity(),
      limits: limits.toEntity(),
      verification: verification?.toEntity(),
      deliveredOrders: deliveredOrders,
      rating: rating,
      totalRatings: totalRatings,
    );
  }

  factory RiderProfileModel.fromEntity(RiderProfile entity) {
    return RiderProfileModel(
      rut: entity.rut,
      isActive: entity.isActive,
      isVerified: entity.isVerified,
      activeVehicleType: entity.activeVehicleType,
      vehicles: entity.vehicles,
      vehicle: VehicleModel.fromEntity(entity.vehicle),
      documents: DocumentsModel.fromEntity(entity.documents),
      limits: LimitsModel.fromEntity(entity.limits),
      verification: entity.verification != null
          ? VerificationModel.fromEntity(entity.verification!)
          : null,
      deliveredOrders: entity.deliveredOrders,
      rating: entity.rating,
      totalRatings: entity.totalRatings,
    );
  }
}

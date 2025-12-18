import '../../domain/entities/rider_profile.dart';
import 'vehicle_model.dart';
import 'documents_model.dart';
import 'limits_model.dart';
import 'verification_model.dart';

class RiderProfileModel {
  final bool isActive;
  final bool isVerified;
  final VehicleModel vehicle;
  final DocumentsModel documents;
  final LimitsModel limits;
  final VerificationModel? verification;
  final int deliveredOrders;
  final double rating;

  RiderProfileModel({
    this.isActive = false,
    this.isVerified = false,
    required this.vehicle,
    required this.documents,
    required this.limits,
    this.verification,
    this.deliveredOrders = 0,
    this.rating = 0.0,
  });

  factory RiderProfileModel.fromJson(Map<String, dynamic> json) {
    return RiderProfileModel(
      isActive: json['isActive'] as bool? ?? false,
      isVerified: json['isVerified'] as bool? ?? false,
      vehicle: VehicleModel.fromJson(json['vehicle'] as Map<String, dynamic>? ?? {}),
      documents: DocumentsModel.fromJson(json['documents'] as Map<String, dynamic>? ?? {}),
      limits: LimitsModel.fromJson(json['limits'] as Map<String, dynamic>? ?? {}),
      verification: json['verification'] != null
          ? VerificationModel.fromJson(json['verification'] as Map<String, dynamic>)
          : null,
      deliveredOrders: json['deliveredOrders'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isActive': isActive,
      'isVerified': isVerified,
      'vehicle': vehicle.toJson(),
      'documents': documents.toJson(),
      'limits': limits.toJson(),
      'verification': verification?.toJson(),
      'deliveredOrders': deliveredOrders,
      'rating': rating,
    };
  }

  RiderProfile toEntity() {
    return RiderProfile(
      isActive: isActive,
      isVerified: isVerified,
      vehicle: vehicle.toEntity(),
      documents: documents.toEntity(),
      limits: limits.toEntity(),
      verification: verification?.toEntity(),
      deliveredOrders: deliveredOrders,
      rating: rating,
    );
  }

  factory RiderProfileModel.fromEntity(RiderProfile entity) {
    return RiderProfileModel(
      isActive: entity.isActive,
      isVerified: entity.isVerified,
      vehicle: VehicleModel.fromEntity(entity.vehicle),
      documents: DocumentsModel.fromEntity(entity.documents),
      limits: LimitsModel.fromEntity(entity.limits),
      verification: entity.verification != null
          ? VerificationModel.fromEntity(entity.verification!)
          : null,
      deliveredOrders: entity.deliveredOrders,
      rating: entity.rating,
    );
  }
}

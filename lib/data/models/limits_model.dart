import '../../domain/entities/limits.dart';

class LimitsModel {
  final double maxDistanceKm;
  final double maxWeightKg;

  LimitsModel({
    required this.maxDistanceKm,
    required this.maxWeightKg,
  });

  factory LimitsModel.fromJson(Map<String, dynamic> json) {
    return LimitsModel(
      maxDistanceKm: (json['maxDistanceKm'] as num?)?.toDouble() ?? 0.0,
      maxWeightKg: (json['maxWeightKg'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxDistanceKm': maxDistanceKm,
      'maxWeightKg': maxWeightKg,
    };
  }

  Limits toEntity() {
    return Limits(
      maxDistanceKm: maxDistanceKm,
      maxWeightKg: maxWeightKg,
    );
  }

  factory LimitsModel.fromEntity(Limits entity) {
    return LimitsModel(
      maxDistanceKm: entity.maxDistanceKm,
      maxWeightKg: entity.maxWeightKg,
    );
  }
}

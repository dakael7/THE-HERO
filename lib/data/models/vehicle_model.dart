import '../../domain/entities/vehicle.dart';

class VehicleModel {
  final String type;
  final String? plateNumber;
  final String? model;
  final int? year;

  VehicleModel({
    required this.type,
    this.plateNumber,
    this.model,
    this.year,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      type: json['type'] as String? ?? 'bicycle',
      plateNumber: json['plateNumber'] as String?,
      model: json['model'] as String?,
      year: json['year'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'plateNumber': plateNumber,
      'model': model,
      'year': year,
    };
  }

  Vehicle toEntity() {
    return Vehicle(
      type: VehicleType.fromString(type),
      plateNumber: plateNumber,
      model: model,
      year: year,
    );
  }

  factory VehicleModel.fromEntity(Vehicle entity) {
    return VehicleModel(
      type: entity.type.name,
      plateNumber: entity.plateNumber,
      model: entity.model,
      year: entity.year,
    );
  }
}

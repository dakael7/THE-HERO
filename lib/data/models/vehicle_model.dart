import '../../domain/entities/vehicle.dart';

class VehicleModel {
  final String type;
  final String? plateNumber;
  final String? model;
  final int? year;
  final String? color;

  VehicleModel({
    required this.type,
    this.plateNumber,
    this.model,
    this.year,
    this.color,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      type: json['type'] as String? ?? 'bicycle',
      plateNumber: json['plateNumber'] as String?,
      model: json['model'] as String?,
      year: json['year'] as int?,
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'plateNumber': plateNumber,
      'model': model,
      'year': year,
      'color': color,
    };
  }

  Vehicle toEntity() {
    return Vehicle(
      type: VehicleType.fromString(type),
      plateNumber: plateNumber,
      model: model,
      year: year,
      color: color,
    );
  }

  factory VehicleModel.fromEntity(Vehicle entity) {
    return VehicleModel(
      type: entity.type.name,
      plateNumber: entity.plateNumber,
      model: entity.model,
      year: entity.year,
      color: entity.color,
    );
  }
}

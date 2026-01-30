import '../../domain/entities/concierge_info.dart';

class ConciergeInfoModel {
  final String buildingName;
  final String instructions;
  final String packageName;
  final String? riderInfo;

  const ConciergeInfoModel({
    required this.buildingName,
    required this.instructions,
    required this.packageName,
    this.riderInfo,
  });

  factory ConciergeInfoModel.fromJson(Map<String, dynamic> json) {
    return ConciergeInfoModel(
      buildingName: json['buildingName'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      riderInfo: json['riderInfo'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'buildingName': buildingName,
      'instructions': instructions,
      'packageName': packageName,
      'riderInfo': riderInfo,
    };
  }

  ConciergeInfo toEntity() {
    return ConciergeInfo(
      buildingName: buildingName,
      instructions: instructions,
      packageName: packageName,
      riderInfo: riderInfo,
    );
  }

  factory ConciergeInfoModel.fromEntity(ConciergeInfo entity) {
    return ConciergeInfoModel(
      buildingName: entity.buildingName,
      instructions: entity.instructions,
      packageName: entity.packageName,
      riderInfo: entity.riderInfo,
    );
  }
}

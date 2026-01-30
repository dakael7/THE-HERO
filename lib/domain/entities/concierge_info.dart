class ConciergeInfo {
  final String buildingName;
  final String instructions;
  final String packageName;
  final String? riderInfo;

  const ConciergeInfo({
    required this.buildingName,
    required this.instructions,
    required this.packageName,
    this.riderInfo,
  });

  bool get isComplete {
    return buildingName.isNotEmpty &&
        instructions.isNotEmpty &&
        packageName.isNotEmpty;
  }

  ConciergeInfo withRiderInfo(String riderName, String riderId) {
    return copyWith(riderInfo: 'Rider: $riderName, ID: $riderId');
  }

  String getRiderSummary() {
    return '''
Retiro en Portería
━━━━━━━━━━━━━━━━
Edificio: $buildingName
Paquete: $packageName

Instrucciones:
$instructions

${riderInfo != null ? '\nRegistrado como:\n$riderInfo' : ''}
''';
  }

  Map<String, dynamic> toJson() {
    return {
      'buildingName': buildingName,
      'instructions': instructions,
      'packageName': packageName,
      'riderInfo': riderInfo,
    };
  }

  factory ConciergeInfo.fromJson(Map<String, dynamic> json) {
    return ConciergeInfo(
      buildingName: json['buildingName'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      riderInfo: json['riderInfo'] as String?,
    );
  }

  ConciergeInfo copyWith({
    String? buildingName,
    String? instructions,
    String? packageName,
    String? riderInfo,
  }) {
    return ConciergeInfo(
      buildingName: buildingName ?? this.buildingName,
      instructions: instructions ?? this.instructions,
      packageName: packageName ?? this.packageName,
      riderInfo: riderInfo ?? this.riderInfo,
    );
  }
}

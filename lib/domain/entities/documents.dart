import 'vehicle.dart';


class Documents {
  final String idCardUrl; 
  final String? licenseUrl; 
  final String? padronUrl; 

  Documents({
    required this.idCardUrl,
    this.licenseUrl,
    this.padronUrl,
  });

  bool isValidForVehicle(VehicleType vehicleType) {
    if (vehicleType == VehicleType.bicycle) {
      return idCardUrl.isNotEmpty;
    }
    return idCardUrl.isNotEmpty && 
           licenseUrl != null && 
           licenseUrl!.isNotEmpty &&
           padronUrl != null && 
           padronUrl!.isNotEmpty;
  }

  Documents copyWith({
    String? idCardUrl,
    String? licenseUrl,
    String? padronUrl,
  }) {
    return Documents(
      idCardUrl: idCardUrl ?? this.idCardUrl,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      padronUrl: padronUrl ?? this.padronUrl,
    );
  }
}

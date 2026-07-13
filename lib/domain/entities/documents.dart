import 'vehicle.dart';

class Documents {
  final String idCardUrl;
  final String? licenseUrl;
  final String? padronUrl;
  final String? soapUrl;
  final String? circulationPermitUrl;
  final String? technicalReviewUrl;

  Documents({
    required this.idCardUrl,
    this.licenseUrl,
    this.padronUrl,
    this.soapUrl,
    this.circulationPermitUrl,
    this.technicalReviewUrl,
  });

  bool isValidForVehicle(VehicleType vehicleType) {
    if (vehicleType == VehicleType.bicycle) {
      return true;
    }
    return licenseUrl != null &&
        licenseUrl!.isNotEmpty &&
        padronUrl != null &&
        padronUrl!.isNotEmpty &&
        soapUrl != null &&
        soapUrl!.isNotEmpty &&
        circulationPermitUrl != null &&
        circulationPermitUrl!.isNotEmpty;
  }

  Documents copyWith({
    String? idCardUrl,
    String? licenseUrl,
    String? padronUrl,
    String? soapUrl,
    String? circulationPermitUrl,
    String? technicalReviewUrl,
  }) {
    return Documents(
      idCardUrl: idCardUrl ?? this.idCardUrl,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      padronUrl: padronUrl ?? this.padronUrl,
      soapUrl: soapUrl ?? this.soapUrl,
      circulationPermitUrl: circulationPermitUrl ?? this.circulationPermitUrl,
      technicalReviewUrl: technicalReviewUrl ?? this.technicalReviewUrl,
    );
  }
}

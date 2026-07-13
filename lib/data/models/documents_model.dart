import '../../domain/entities/documents.dart';

class DocumentsModel {
  final String idCardUrl;
  final String? licenseUrl;
  final String? padronUrl;
  final String? soapUrl;
  final String? circulationPermitUrl;
  final String? technicalReviewUrl;

  DocumentsModel({
    required this.idCardUrl,
    this.licenseUrl,
    this.padronUrl,
    this.soapUrl,
    this.circulationPermitUrl,
    this.technicalReviewUrl,
  });

  factory DocumentsModel.fromJson(Map<String, dynamic> json) {
    return DocumentsModel(
      idCardUrl: json['idCardUrl'] as String? ?? '',
      licenseUrl: json['licenseUrl'] as String?,
      padronUrl:
          json['padronUrl'] as String? ??
          json['registrationCertificateUrl'] as String?,
      soapUrl:
          json['soapUrl'] as String? ?? json['soapInsuranceUrl'] as String?,
      circulationPermitUrl:
          json['circulationPermitUrl'] as String? ??
          json['permisoCirculacionUrl'] as String?,
      technicalReviewUrl:
          json['technicalReviewUrl'] as String? ??
          json['homologationUrl'] as String? ??
          json['revisionTecnicaUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idCardUrl': idCardUrl,
      'licenseUrl': licenseUrl,
      'padronUrl': padronUrl,
      'soapUrl': soapUrl,
      'circulationPermitUrl': circulationPermitUrl,
      'technicalReviewUrl': technicalReviewUrl,
    };
  }

  Documents toEntity() {
    return Documents(
      idCardUrl: idCardUrl,
      licenseUrl: licenseUrl,
      padronUrl: padronUrl,
      soapUrl: soapUrl,
      circulationPermitUrl: circulationPermitUrl,
      technicalReviewUrl: technicalReviewUrl,
    );
  }

  factory DocumentsModel.fromEntity(Documents entity) {
    return DocumentsModel(
      idCardUrl: entity.idCardUrl,
      licenseUrl: entity.licenseUrl,
      padronUrl: entity.padronUrl,
      soapUrl: entity.soapUrl,
      circulationPermitUrl: entity.circulationPermitUrl,
      technicalReviewUrl: entity.technicalReviewUrl,
    );
  }
}

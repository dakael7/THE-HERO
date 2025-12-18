import '../../domain/entities/documents.dart';

class DocumentsModel {
  final String idCardUrl;
  final String? licenseUrl;
  final String? padronUrl;

  DocumentsModel({
    required this.idCardUrl,
    this.licenseUrl,
    this.padronUrl,
  });

  factory DocumentsModel.fromJson(Map<String, dynamic> json) {
    return DocumentsModel(
      idCardUrl: json['idCardUrl'] as String? ?? '',
      licenseUrl: json['licenseUrl'] as String?,
      padronUrl: json['padronUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idCardUrl': idCardUrl,
      'licenseUrl': licenseUrl,
      'padronUrl': padronUrl,
    };
  }

  Documents toEntity() {
    return Documents(
      idCardUrl: idCardUrl,
      licenseUrl: licenseUrl,
      padronUrl: padronUrl,
    );
  }

  factory DocumentsModel.fromEntity(Documents entity) {
    return DocumentsModel(
      idCardUrl: entity.idCardUrl,
      licenseUrl: entity.licenseUrl,
      padronUrl: entity.padronUrl,
    );
  }
}

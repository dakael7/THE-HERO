import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/offer_report.dart';

class OfferReportModel extends OfferReport {
  const OfferReportModel({
    required super.reportId,
    required super.offerId,
    required super.reporterId,
    required super.reason,
    super.description,
    required super.createdAt,
    required super.status,
  });

  factory OfferReportModel.fromJson(Map<String, dynamic> json, String id) {
    return OfferReportModel(
      reportId: id,
      offerId: json['offerId'] as String? ?? '',
      reporterId: json['reporterId'] as String? ?? '',
      reason: ReportOfferReason.values.firstWhere(
        (e) => e.name == (json['reason'] as String? ?? ''),
        orElse: () => ReportOfferReason.other,
      ),
      description: json['description'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: ReportStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? ''),
        orElse: () => ReportStatus.pending,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'offerId': offerId,
        'reporterId': reporterId,
        'reason': reason.name,
        if (description != null) 'description': description,
        'createdAt': FieldValue.serverTimestamp(),
        'status': ReportStatus.pending.name,
      };
}

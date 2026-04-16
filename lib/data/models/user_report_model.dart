import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/offer_report.dart';
import '../../domain/entities/user_report.dart';

class UserReportModel extends UserReport {
  const UserReportModel({
    required super.reportId,
    required super.reportedUserId,
    required super.reportedRole,
    required super.reporterId,
    required super.reason,
    super.description,
    super.relatedOfferId,
    required super.createdAt,
    required super.status,
  });

  factory UserReportModel.fromJson(Map<String, dynamic> json, String id) {
    return UserReportModel(
      reportId: id,
      reportedUserId: json['reportedUserId'] as String? ?? '',
      reportedRole: json['reportedRole'] as String? ?? '',
      reporterId: json['reporterId'] as String? ?? '',
      reason: ReportUserReason.values.firstWhere(
        (e) => e.name == (json['reason'] as String? ?? ''),
        orElse: () => ReportUserReason.other,
      ),
      description: json['description'] as String?,
      relatedOfferId: json['relatedOfferId'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: ReportStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? ''),
        orElse: () => ReportStatus.pending,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'reportedUserId': reportedUserId,
        'reportedRole': reportedRole,
        'reporterId': reporterId,
        'reason': reason.name,
        if (description != null) 'description': description,
        if (relatedOfferId != null) 'relatedOfferId': relatedOfferId,
        'createdAt': FieldValue.serverTimestamp(),
        'status': ReportStatus.pending.name,
      };
}

import 'offer_report.dart';

enum ReportUserReason { harassment, fraud, noShow, fakeProfile, other }

class UserReport {
  final String reportId;
  final String reportedUserId;
  final String reportedRole;
  final String reporterId;
  final ReportUserReason reason;
  final String? description;
  final String? relatedOfferId;
  final DateTime createdAt;
  final ReportStatus status;

  const UserReport({
    required this.reportId,
    required this.reportedUserId,
    required this.reportedRole,
    required this.reporterId,
    required this.reason,
    this.description,
    this.relatedOfferId,
    required this.createdAt,
    required this.status,
  });
}

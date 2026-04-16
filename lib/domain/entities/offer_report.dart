enum ReportOfferReason { inappropriate, spam, fraud, counterfeit, other }

enum ReportStatus { pending, reviewed, dismissed }

class OfferReport {
  final String reportId;
  final String offerId;
  final String reporterId;
  final ReportOfferReason reason;
  final String? description;
  final DateTime createdAt;
  final ReportStatus status;

  const OfferReport({
    required this.reportId,
    required this.offerId,
    required this.reporterId,
    required this.reason,
    this.description,
    required this.createdAt,
    required this.status,
  });
}

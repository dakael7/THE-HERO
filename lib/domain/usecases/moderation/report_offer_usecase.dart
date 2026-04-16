import '../../entities/offer_report.dart';
import '../../repositories/moderation_repository.dart';

class ReportOfferUseCase {
  final ModerationRepository _repository;

  ReportOfferUseCase({required ModerationRepository repository})
      : _repository = repository;

  Future<void> execute({
    required String offerId,
    required String reporterId,
    required ReportOfferReason reason,
    String? description,
  }) async {
    final alreadyReported =
        await _repository.hasUserReportedOffer(offerId, reporterId);
    if (alreadyReported) {
      throw Exception('Ya reportaste esta publicación');
    }

    final report = OfferReport(
      reportId: '',
      offerId: offerId,
      reporterId: reporterId,
      reason: reason,
      description: description,
      createdAt: DateTime.now(),
      status: ReportStatus.pending,
    );

    await _repository.reportOffer(report);
  }
}

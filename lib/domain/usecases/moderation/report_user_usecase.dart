import '../../entities/offer_report.dart';
import '../../entities/user_report.dart';
import '../../repositories/moderation_repository.dart';

class ReportUserUseCase {
  final ModerationRepository _repository;

  ReportUserUseCase({required ModerationRepository repository})
      : _repository = repository;

  Future<void> execute({
    required String reportedUserId,
    required String reportedRole,
    required String reporterId,
    required ReportUserReason reason,
    String? description,
    String? relatedOfferId,
  }) async {
    final alreadyReported =
        await _repository.hasUserReportedUser(reportedUserId, reporterId);
    if (alreadyReported) {
      throw Exception('Ya reportaste este usuario');
    }

    final report = UserReport(
      reportId: '',
      reportedUserId: reportedUserId,
      reportedRole: reportedRole,
      reporterId: reporterId,
      reason: reason,
      description: description,
      relatedOfferId: relatedOfferId,
      createdAt: DateTime.now(),
      status: ReportStatus.pending,
    );

    await _repository.reportUser(report);
  }
}

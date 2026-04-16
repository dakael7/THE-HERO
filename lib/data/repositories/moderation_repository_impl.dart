import '../../domain/entities/offer_report.dart';
import '../../domain/entities/user_report.dart';
import '../../domain/repositories/moderation_repository.dart';
import '../datasources/moderation_remote_data_source.dart';
import '../models/offer_report_model.dart';
import '../models/user_report_model.dart';

class ModerationRepositoryImpl implements ModerationRepository {
  final ModerationRemoteDataSource _remote;

  ModerationRepositoryImpl({required ModerationRemoteDataSource remote})
      : _remote = remote;

  @override
  Future<void> reportOffer(OfferReport report) async {
    final model = OfferReportModel(
      reportId: report.reportId,
      offerId: report.offerId,
      reporterId: report.reporterId,
      reason: report.reason,
      description: report.description,
      createdAt: report.createdAt,
      status: report.status,
    );

    await _remote.reportOffer(model);
  }

  @override
  Future<bool> hasUserReportedOffer(String offerId, String userId) {
    return _remote.hasUserReportedOffer(offerId, userId);
  }

  @override
  Future<void> reportUser(UserReport report) async {
    final model = UserReportModel(
      reportId: report.reportId,
      reportedUserId: report.reportedUserId,
      reportedRole: report.reportedRole,
      reporterId: report.reporterId,
      reason: report.reason,
      description: report.description,
      relatedOfferId: report.relatedOfferId,
      createdAt: report.createdAt,
      status: report.status,
    );

    await _remote.reportUser(model);
  }

  @override
  Future<bool> hasUserReportedUser(String reportedUserId, String reporterId) {
    return _remote.hasUserReportedUser(reportedUserId, reporterId);
  }
}

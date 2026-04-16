import '../entities/offer_report.dart';
import '../entities/user_report.dart';

abstract class ModerationRepository {
  Future<void> reportOffer(OfferReport report);
  Future<bool> hasUserReportedOffer(String offerId, String userId);

  Future<void> reportUser(UserReport report);
  Future<bool> hasUserReportedUser(String reportedUserId, String reporterId);
}

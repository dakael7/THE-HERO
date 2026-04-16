import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/offer_report_model.dart';
import '../models/user_report_model.dart';

abstract class ModerationRemoteDataSource {
  Future<void> reportOffer(OfferReportModel report);
  Future<bool> hasUserReportedOffer(String offerId, String userId);

  Future<void> reportUser(UserReportModel report);
  Future<bool> hasUserReportedUser(String reportedUserId, String reporterId);
}

class ModerationRemoteDataSourceImpl implements ModerationRemoteDataSource {
  final FirebaseFirestore _firestore;

  ModerationRemoteDataSourceImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  @override
  Future<void> reportOffer(OfferReportModel report) async {
    final batch = _firestore.batch();

    final reportRef = _firestore.collection('offer_reports').doc();
    batch.set(reportRef, report.toJson());

    final offerRef = _firestore.collection('offers').doc(report.offerId);
    batch.update(offerRef, {
      'reportCount': FieldValue.increment(1),
      'lastReportedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  @override
  Future<bool> hasUserReportedOffer(String offerId, String userId) async {
    final snap = await _firestore
        .collection('offer_reports')
        .where('offerId', isEqualTo: offerId)
        .where('reporterId', isEqualTo: userId)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  @override
  Future<void> reportUser(UserReportModel report) async {
    final batch = _firestore.batch();

    final reportRef = _firestore.collection('user_reports').doc();
    batch.set(reportRef, report.toJson());

    final userRef = _firestore.collection('users').doc(report.reportedUserId);
    batch.update(userRef, {
      'reportCount': FieldValue.increment(1),
      'lastReportedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  @override
  Future<bool> hasUserReportedUser(String reportedUserId, String reporterId) async {
    final snap = await _firestore
        .collection('user_reports')
        .where('reportedUserId', isEqualTo: reportedUserId)
        .where('reporterId', isEqualTo: reporterId)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }
}

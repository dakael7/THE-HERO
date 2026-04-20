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

    final reportRef = _firestore
        .collection('offers')
        .doc(report.offerId)
        .collection('reports')
        .doc(report.reporterId);
    batch.set(reportRef, report.toJson());

    final offerRef = _firestore.collection('offers').doc(report.offerId);
    batch.update(offerRef, {
      'reportCount': FieldValue.increment(1),
      'lastReportedAt': FieldValue.serverTimestamp(),
      'supportReviewStatus': 'pending',
    });

    await batch.commit();
  }

  @override
  Future<bool> hasUserReportedOffer(String offerId, String userId) async {
    final doc = await _firestore
        .collection('offers')
        .doc(offerId)
        .collection('reports')
        .doc(userId)
        .get();

    return doc.exists;
  }

  @override
  Future<void> reportUser(UserReportModel report) async {
    final batch = _firestore.batch();

    final reportRef = _firestore
        .collection('users')
        .doc(report.reportedUserId)
        .collection('reports')
        .doc(report.reporterId);
    batch.set(reportRef, report.toJson());

    final userRef = _firestore.collection('users').doc(report.reportedUserId);
    batch.update(userRef, {
      'reportCount': FieldValue.increment(1),
      'lastReportedAt': FieldValue.serverTimestamp(),
      'supportReviewStatus': 'pending',
    });

    await batch.commit();
  }

  @override
  Future<bool> hasUserReportedUser(String reportedUserId, String reporterId) async {
    final doc = await _firestore
        .collection('users')
        .doc(reportedUserId)
        .collection('reports')
        .doc(reporterId)
        .get();

    return doc.exists;
  }
}

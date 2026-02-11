import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/notification_model.dart';

abstract class NotificationRemoteDataSource {
  Future<List<NotificationModel>> getUserNotifications();
  Future<void> saveFcmToken(String token);
  Future<void> markAsRead(String notificationId);
  Future<void> deleteNotification(String notificationId);
  Stream<List<NotificationModel>> watchUserNotifications();
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  NotificationRemoteDataSourceImpl({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
  }) : _firebaseAuth = firebaseAuth,
       _firestore = firestore;

  @override
  Future<List<NotificationModel>> getUserNotifications() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return [];
    }

    final query = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    return query.docs
        .map((doc) => NotificationModel.fromJson(doc.data(), doc.id))
        .toList();
  }

  @override
  Future<void> saveFcmToken(String token) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastTokenUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    await _firestore.collection('notifications').doc(notificationId).update({
      'read': true,
    });
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    await _firestore.collection('notifications').doc(notificationId).delete();
  }

  @override
  Stream<List<NotificationModel>> watchUserNotifications() {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationModel.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }
}

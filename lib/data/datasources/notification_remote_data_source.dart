import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/notification_model.dart';

abstract class NotificationRemoteDataSource {
  Future<List<NotificationModel>> getUserNotifications();
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  NotificationRemoteDataSourceImpl({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
  })  : _firebaseAuth = firebaseAuth,
        _firestore = firestore;

  @override
  Future<List<NotificationModel>> getUserNotifications() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return [];
    }

    final query = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .get();

    return query.docs
        .map((doc) => NotificationModel.fromJson(doc.data(), doc.id))
        .toList();
  }
}

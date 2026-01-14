import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_config.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseConfig.auth;
});

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseConfig.firestore;
});

final firebaseStorageProvider = Provider<FirebaseStorage>((ref) {
  return FirebaseConfig.storage;
});

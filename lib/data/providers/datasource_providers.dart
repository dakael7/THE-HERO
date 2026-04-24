import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/chat_remote_data_source.dart';
import '../datasources/invoices_remote_data_source.dart';
import '../datasources/notification_remote_data_source.dart';
import '../datasources/moderation_remote_data_source.dart';
import '../datasources/offers_remote_data_source.dart';
import '../datasources/orders_remote_data_source.dart';
import 'network_providers.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final firebaseAuth = ref.read(firebaseAuthProvider);
  final firestore = ref.read(firebaseFirestoreProvider);
  final googleSignIn = GoogleSignIn.instance;
  return AuthRemoteDataSourceImpl(
    firebaseAuth: firebaseAuth,
    firestore: firestore,
    googleSignIn: googleSignIn,
  );
});

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSourceImpl();
});

final notificationRemoteDataSourceProvider =
    Provider<NotificationRemoteDataSource>((ref) {
  final firebaseAuth = ref.read(firebaseAuthProvider);
  final firestore = ref.read(firebaseFirestoreProvider);
  return NotificationRemoteDataSourceImpl(
    firebaseAuth: firebaseAuth,
    firestore: firestore,
  );
});

final offersRemoteDataSourceProvider = Provider<OffersRemoteDataSource>((ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  final storage = ref.read(firebaseStorageProvider);
  return OffersRemoteDataSourceImpl(
    firestore: firestore,
    storage: storage,
  );
});

final moderationRemoteDataSourceProvider =
    Provider<ModerationRemoteDataSource>((ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return ModerationRemoteDataSourceImpl(firestore: firestore);
});

final ordersRemoteDataSourceProvider = Provider<OrdersRemoteDataSource>((ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return OrdersRemoteDataSourceImpl(firestore: firestore);
});

final chatRemoteDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return ChatRemoteDataSourceImpl(firestore: firestore);
});

final invoicesRemoteDataSourceProvider = Provider<InvoicesRemoteDataSource>((ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return InvoicesRemoteDataSourceImpl(firestore: firestore);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/notification_remote_data_source.dart';
import '../datasources/offers_remote_data_source.dart';
import '../datasources/orders_remote_data_source.dart';
import 'network_providers.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final firebaseAuth = ref.read(firebaseAuthProvider);
  final firestore = ref.read(firebaseFirestoreProvider);
  return AuthRemoteDataSourceImpl(
    firebaseAuth: firebaseAuth,
    firestore: firestore,
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
  return OffersRemoteDataSourceImpl(firestore: firestore);
});

final ordersRemoteDataSourceProvider = Provider<OrdersRemoteDataSource>((ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return OrdersRemoteDataSourceImpl(firestore: firestore);
});

import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/chat_remote_data_source.dart';
import '../datasources/invoices_remote_data_source.dart';
import '../datasources/notification_remote_data_source.dart';
import '../datasources/moderation_remote_data_source.dart';
import '../datasources/offers_remote_data_source.dart';
import '../datasources/orders_remote_data_source.dart';
import 'network_providers.dart';

part 'datasource_providers.g.dart';

@Riverpod(keepAlive: true)
AuthRemoteDataSource authRemoteDataSource(Ref ref) {
  final firebaseAuth = ref.read(firebaseAuthProvider);
  final firestore = ref.read(firebaseFirestoreProvider);
  final googleSignIn = GoogleSignIn.instance;
  return AuthRemoteDataSourceImpl(
    firebaseAuth: firebaseAuth,
    firestore: firestore,
    googleSignIn: googleSignIn,
  );
}

@Riverpod(keepAlive: true)
AuthLocalDataSource authLocalDataSource(Ref ref) {
  return AuthLocalDataSourceImpl();
}

@Riverpod(keepAlive: true)
NotificationRemoteDataSource notificationRemoteDataSource(Ref ref) {
  final firebaseAuth = ref.read(firebaseAuthProvider);
  final firestore = ref.read(firebaseFirestoreProvider);
  return NotificationRemoteDataSourceImpl(
    firebaseAuth: firebaseAuth,
    firestore: firestore,
  );
}

@Riverpod(keepAlive: true)
OffersRemoteDataSource offersRemoteDataSource(Ref ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  final storage = ref.read(firebaseStorageProvider);
  return OffersRemoteDataSourceImpl(
    firestore: firestore,
    storage: storage,
  );
}

@Riverpod(keepAlive: true)
ModerationRemoteDataSource moderationRemoteDataSource(Ref ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return ModerationRemoteDataSourceImpl(firestore: firestore);
}

@Riverpod(keepAlive: true)
OrdersRemoteDataSource ordersRemoteDataSource(Ref ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return OrdersRemoteDataSourceImpl(firestore: firestore);
}

@Riverpod(keepAlive: true)
ChatRemoteDataSource chatRemoteDataSource(Ref ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return ChatRemoteDataSourceImpl(firestore: firestore);
}

@Riverpod(keepAlive: true)
InvoicesRemoteDataSource invoicesRemoteDataSource(Ref ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  return InvoicesRemoteDataSourceImpl(firestore: firestore);
}

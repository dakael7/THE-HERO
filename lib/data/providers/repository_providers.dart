import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/repositories/offers_repository.dart';
import '../../domain/repositories/orders_repository.dart';
import '../../domain/repositories/invoices_repository.dart';
import '../../domain/repositories/moderation_repository.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/chat_repository_impl.dart';
import '../repositories/notification_repository_impl.dart';
import '../repositories/offers_repository_impl.dart';
import '../repositories/orders_repository_impl.dart';
import '../repositories/invoices_repository_impl.dart';
import '../repositories/moderation_repository_impl.dart';
import 'datasource_providers.dart';

part 'repository_providers.g.dart';

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  final remote = ref.read(authRemoteDataSourceProvider);
  final local = ref.read(authLocalDataSourceProvider);
  return AuthRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
  );
}

@Riverpod(keepAlive: true)
NotificationRepository notificationRepository(Ref ref) {
  final remote = ref.read(notificationRemoteDataSourceProvider);
  return NotificationRepositoryImpl(remoteDataSource: remote);
}

@Riverpod(keepAlive: true)
OffersRepository offersRepository(Ref ref) {
  final remote = ref.read(offersRemoteDataSourceProvider);
  return OffersRepositoryImpl(remoteDataSource: remote);
}

@Riverpod(keepAlive: true)
ModerationRepository moderationRepository(Ref ref) {
  final remote = ref.read(moderationRemoteDataSourceProvider);
  return ModerationRepositoryImpl(remote: remote);
}

@Riverpod(keepAlive: true)
OrdersRepository ordersRepository(Ref ref) {
  final remote = ref.read(ordersRemoteDataSourceProvider);
  return OrdersRepositoryImpl(remoteDataSource: remote);
}

@Riverpod(keepAlive: true)
InvoicesRepository invoicesRepository(Ref ref) {
  final remote = ref.read(invoicesRemoteDataSourceProvider);
  return InvoicesRepositoryImpl(remote: remote);
}

@Riverpod(keepAlive: true)
ChatRepository chatRepository(Ref ref) {
  final remote = ref.read(chatRemoteDataSourceProvider);
  return ChatRepositoryImpl(remoteDataSource: remote);
}

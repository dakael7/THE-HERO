import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/repositories/offers_repository.dart';
import '../../domain/repositories/orders_repository.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/chat_repository_impl.dart';
import '../repositories/notification_repository_impl.dart';
import '../repositories/offers_repository_impl.dart';
import '../repositories/orders_repository_impl.dart';
import 'datasource_providers.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remote = ref.read(authRemoteDataSourceProvider);
  final local = ref.read(authLocalDataSourceProvider);
  return AuthRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
  );
});

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) {
  final remote = ref.read(notificationRemoteDataSourceProvider);
  return NotificationRepositoryImpl(remoteDataSource: remote);
});

final offersRepositoryProvider = Provider<OffersRepository>((ref) {
  final remote = ref.read(offersRemoteDataSourceProvider);
  return OffersRepositoryImpl(remoteDataSource: remote);
});

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final remote = ref.read(ordersRemoteDataSourceProvider);
  return OrdersRepositoryImpl(remoteDataSource: remote);
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final remote = ref.read(chatRemoteDataSourceProvider);
  return ChatRepositoryImpl(remoteDataSource: remote);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/notification_repository.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/notification_repository_impl.dart';
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

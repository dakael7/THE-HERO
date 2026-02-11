import '../../domain/entities/notification.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/notification_remote_data_source.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDataSource _remoteDataSource;

  NotificationRepositoryImpl({
    required NotificationRemoteDataSource remoteDataSource,
  }) : _remoteDataSource = remoteDataSource;

  @override
  Future<List<AppNotification>> getUserNotifications() async {
    final models = await _remoteDataSource.getUserNotifications();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> saveFcmToken(String token) async {
    await _remoteDataSource.saveFcmToken(token);
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _remoteDataSource.markAsRead(notificationId);
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    await _remoteDataSource.deleteNotification(notificationId);
  }

  @override
  Stream<List<AppNotification>> watchUserNotifications() {
    return _remoteDataSource.watchUserNotifications().map(
      (models) => models.map((m) => m.toEntity()).toList(),
    );
  }
}

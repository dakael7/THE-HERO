import '../entities/notification.dart';

abstract class NotificationRepository {
  Future<List<AppNotification>> getUserNotifications();
  Future<void> saveFcmToken(String token);
  Future<void> markAsRead(String notificationId);
  Future<void> deleteNotification(String notificationId);
  Stream<List<AppNotification>> watchUserNotifications();
}

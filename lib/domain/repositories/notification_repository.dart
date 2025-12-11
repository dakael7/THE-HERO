import '../entities/notification.dart';

abstract class NotificationRepository {
  Future<List<AppNotification>> getUserNotifications();
}

import 'package:the_hero/domain/entities/notification.dart';
import 'package:the_hero/domain/repositories/notification_repository.dart';

class GetUserNotificationsUseCase {
  final NotificationRepository _repository;

  GetUserNotificationsUseCase(this._repository);

  Future<List<AppNotification>> execute() {
    return _repository.getUserNotifications();
  }
}

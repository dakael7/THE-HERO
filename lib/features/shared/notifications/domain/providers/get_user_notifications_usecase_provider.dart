import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/providers/repository_providers.dart';
import '../usecases/get_user_notifications_usecase.dart';

final getUserNotificationsUseCaseProvider =
    Provider<GetUserNotificationsUseCase>((ref) {
  final repository = ref.read(notificationRepositoryProvider);
  return GetUserNotificationsUseCase(repository);
});

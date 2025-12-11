import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_hero/domain/entities/notification.dart';

import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/providers/get_user_notifications_usecase_provider.dart';

final notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  final authState = ref.watch(authNotifierProvider);

  if (!authState.isAuthenticated) {
    return [];
  }

  final useCase = ref.read(getUserNotificationsUseCaseProvider);
  return useCase.execute();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_hero/domain/entities/notification.dart';

import '../../../../../data/providers/repository_providers.dart';
import '../../../profile/presentation/providers/profile_provider.dart';

const _notificationsLastSeenKey = 'notifications_last_seen_at_ms';

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || userId.trim().isEmpty) {
    return Stream.value(const <AppNotification>[]);
  }

  final repo = ref.read(notificationRepositoryProvider);
  return repo.watchUserNotifications();
});

final notificationsLastSeenProvider = FutureProvider<DateTime?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt(_notificationsLastSeenKey);
  if (ms == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms);
});

final notificationsUnseenCountProvider = Provider<int>((ref) {
  final lastSeenAsync = ref.watch(notificationsLastSeenProvider);
  final notificationsAsync = ref.watch(notificationsProvider);

  final lastSeen = lastSeenAsync.maybeWhen(
    data: (v) => v,
    orElse: () => null,
  );

  return notificationsAsync.maybeWhen(
    data: (notifications) {
      if (notifications.isEmpty) return 0;
      if (lastSeen == null) return notifications.length;
      return notifications.where((n) => n.createdAt.isAfter(lastSeen)).length;
    },
    orElse: () => 0,
  );
});

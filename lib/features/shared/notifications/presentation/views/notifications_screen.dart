import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../providers/notifications_provider.dart';

const _notificationsLastSeenKey = 'notifications_last_seen_at_ms';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _didMarkSeen = false;
  final Set<String> _removedNotificationIds = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_markAllAsSeen);
  }

  Future<void> _markAllAsSeen() async {
    if (_didMarkSeen) return;
    _didMarkSeen = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _notificationsLastSeenKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      ref.invalidate(notificationsLastSeenProvider);
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncNotifications = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
          },
        ),
        title: const Text(
          'Avisos',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: asyncNotifications.when(
        data: (notifications) {
          final visible = notifications
              .where((n) => !_removedNotificationIds.contains(n.id))
              .toList();

          if (visible.isEmpty) {
            return const Center(
              child: Text('No tienes avisos por ahora'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = visible[index];
              return Dismissible(
                key: ValueKey(item.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerRight,
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                  ),
                ),
                onDismissed: (_) async {
                  setState(() {
                    _removedNotificationIds.add(item.id);
                  });

                  try {
                    final repo = ref.read(notificationRepositoryProvider);
                    await repo.deleteNotification(item.id);
                    ref.invalidate(notificationsProvider);
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _removedNotificationIds.remove(item.id);
                      });
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('No se pudo eliminar: $e'),
                      ),
                    );
                    ref.invalidate(notificationsProvider);
                  }
                },
                child: _NotificationCard(
                  title: item.title,
                  subtitle: item.body,
                  time: item.createdAt.toLocal().toString(),
                  icon: Icons.notifications_none_outlined,
                ),
              );
            },
          );
        },
        loading: () {
          return const Center(
            child: CircularProgressIndicator(color: primaryOrange),
          );
        },
        error: (error, stackTrace) {
          return Center(
            child: Text('Error al cargar avisos: $error'),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;

  const _NotificationCard({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderGray100,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: primaryOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: textGray600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 11,
                    color: textGray600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

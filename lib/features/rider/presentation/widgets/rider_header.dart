import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../shared/notifications/presentation/providers/notifications_provider.dart';
import '../../../shared/notifications/presentation/views/notifications_screen.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

/// Delegate para el header del rider (sin buscador)
class RiderHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function() buildLogoSection;
  final Widget Function() buildNotificationIcon;

  RiderHeaderDelegate({
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.buildLogoSection,
    required this.buildNotificationIcon,
  });

  @override
  double get minExtent => collapsedHeight;

  @override
  double get maxExtent => expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double availableRange = maxExtent - minExtent;
    final double t = availableRange > 0
        ? (shrinkOffset / availableRange).clamp(0.0, 1.0)
        : 0.0;

    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double decorOpacity = 1.0 - (t * 0.85);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryOrange, primaryYellow.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: decorOpacity,
                child: Stack(
                  children: [
                    Positioned(
                      top: -40,
                      left: -30,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: backgroundWhite.withOpacity(0.16),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      right: -50,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: backgroundWhite.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 46,
                      left: 40,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Logo y notificaciones centrados verticalmente
          Positioned(
            top: statusBarHeight + paddingNormal,
            left: paddingLarge,
            right: paddingLarge,
            child: Opacity(
              opacity: 1.0 - t,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [buildLogoSection(), buildNotificationIcon()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant RiderHeaderDelegate oldDelegate) {
    return false;
  }
}

/// Widget del header para rider (sin buscador)
class RiderHeader extends ConsumerWidget {
  const RiderHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedHeight = 160.0;
    final collapsedHeight = 100.0;

    return SliverPersistentHeader(
      pinned: true,
      delegate: RiderHeaderDelegate(
        expandedHeight: expandedHeight,
        collapsedHeight: collapsedHeight,
        buildLogoSection: _buildLogoSection,
        buildNotificationIcon: () => _buildNotificationIcon(context, ref),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundWhite.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: backgroundWhite.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/logo_1.png',
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'TheHero',
            style: TextStyle(
              color: textGray900,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: primaryOrange,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Rider',
              style: TextStyle(
                color: backgroundWhite,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon(BuildContext context, WidgetRef ref) {
    final asyncNotifications = ref.watch(notificationsProvider);
    final badgeCount = asyncNotifications.when(
      data: (notifications) => notifications.where((n) => !n.read).length,
      loading: () => 0,
      error: (_, __) => 0,
    );

    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: textGray900.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_none_outlined,
              color: primaryOrange,
              size: 24,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryOrange, Color(0xFFFF6B35)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryYellow, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: backgroundWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

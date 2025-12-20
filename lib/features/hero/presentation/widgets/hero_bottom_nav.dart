import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../viewmodels/hero_home_viewmodel.dart';
import '../../../shared/notifications/presentation/providers/notifications_provider.dart';

class HeroBottomNav extends ConsumerWidget {
  const HeroBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(heroHomeViewModelProvider);
    final viewModel = ref.read(heroHomeViewModelProvider.notifier);
    final notificationsAsync = ref.watch(notificationsProvider);
    final isMobile = ResponsiveUtils.isMobile(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final safeBottom = mediaQuery.padding.bottom;

    final isCompact = screenWidth < 360;
    final navHeight = isMobile ? (isCompact ? 86.0 : 84.0) : 90.0;
    final padding = isMobile ? 8.0 : 16.0;
    final bottomPadding = isMobile ? (safeBottom > 0 ? safeBottom : 12.0) : 24.0;
    final itemPadding = isCompact ? 4.0 : 8.0;
    final fontSize = isCompact ? 10.0 : 11.0;
    final iconSize = isCompact ? 24.0 : 26.0;
    final centerGapWidth = isMobile ? (isCompact ? 52.0 : 64.0) : 72.0;
    final navRadius = isMobile ? 26.0 : 28.0;
    final navBackground = backgroundWhite.withOpacity(0.92);
    final containerWidth = screenWidth - (padding * 2);
    final itemWidth = ((containerWidth - centerGapWidth) / 4).clamp(58.0, 86.0);

    // Calcular el contador de notificaciones no leídas
    int unreadCount = notificationsAsync.when(
      data: (notifications) => notifications.where((n) => !n.read).length,
      loading: () => 0,
      error: (_, __) => 0,
    );

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: false,
      child: Padding(
        padding:
            EdgeInsets.only(left: padding, right: padding, bottom: bottomPadding),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(navRadius),
            border: Border.all(
              color: textGray900.withOpacity(0.06),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: textGray900.withOpacity(0.10),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: primaryOrange.withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(navRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: navBackground,
                child: BottomAppBar(
                  shape: const CircularNotchedRectangle(),
                  notchMargin: 12.0,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  color: Colors.transparent,
                  child: SizedBox(
                    height: navHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        _buildNavItem(
                          context,
                          Icons.home,
                          'Inicio',
                          0,
                          state.selectedNavIndex,
                          () => viewModel.selectNavItem(0),
                          itemPadding: itemPadding,
                          fontSize: fontSize,
                          iconSize: iconSize,
                          itemWidth: itemWidth,
                        ),
                        _buildNavItem(
                          context,
                          Icons.location_on_outlined,
                          'Ubicación',
                          1,
                          state.selectedNavIndex,
                          () => viewModel.selectNavItem(1),
                          itemPadding: itemPadding,
                          fontSize: fontSize,
                          iconSize: iconSize,
                          itemWidth: itemWidth,
                        ),
                        SizedBox(width: centerGapWidth),
                        _buildNavItem(
                          context,
                          Icons.notifications_none_outlined,
                          'Avisos',
                          3,
                          state.selectedNavIndex,
                          () => viewModel.selectNavItem(3),
                          badgeCount: unreadCount > 0 ? unreadCount : null,
                          itemPadding: itemPadding,
                          fontSize: fontSize,
                          iconSize: iconSize,
                          itemWidth: itemWidth,
                        ),
                        _buildNavItem(
                          context,
                          Icons.person_outline,
                          'Perfil',
                          4,
                          state.selectedNavIndex,
                          () => viewModel.selectNavItem(4),
                          itemPadding: itemPadding,
                          fontSize: fontSize,
                          iconSize: iconSize,
                          itemWidth: itemWidth,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    int index,
    int selectedIndex,
    VoidCallback onTap, {
    int? badgeCount,
    required double itemPadding,
    required double fontSize,
    required double iconSize,
    required double itemWidth,
  }) {
    final bool isActive = selectedIndex == index;
    Color iconColor = isActive ? primaryOrange : textGray600;
    Color backgroundColor = isActive ? primaryOrange.withOpacity(0.12) : Colors.transparent;
    Color textColor = isActive ? primaryOrange : textGray600;

    return SizedBox(
      width: itemWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: primaryOrange.withOpacity(0.12),
            highlightColor: primaryOrange.withOpacity(0.06),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
                border: isActive
                    ? Border.all(
                        color: primaryOrange.withOpacity(0.20),
                        width: 1.5,
                      )
                    : Border.all(
                        color: textGray900.withOpacity(0.04),
                        width: 1,
                      ),
                gradient: isActive
                    ? LinearGradient(
                        colors: [
                          primaryOrange.withOpacity(0.16),
                          primaryOrange.withOpacity(0.08),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : null,
              ),
              padding: EdgeInsets.symmetric(vertical: 5, horizontal: itemPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        scale: isActive ? 1.06 : 1.0,
                        child: Icon(icon, color: iconColor, size: iconSize),
                      ),
                      if (badgeCount != null && badgeCount > 0)
                        Positioned(
                          right: -8,
                          top: -8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: primaryOrange,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: primaryOrange.withOpacity(0.35),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 14,
                              minHeight: 14,
                            ),
                            child: Text(
                              badgeCount.toString(),
                              style: const TextStyle(
                                color: backgroundWhite,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: textColor,
                      fontSize: fontSize,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: isActive ? 0.2 : 0,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

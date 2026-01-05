import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../viewmodels/hero_home_viewmodel.dart';
import '../../../shared/chat/presentation/providers/chat_providers.dart';

class HeroBottomNav extends ConsumerWidget {
  const HeroBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(
      heroHomeViewModelProvider.select((state) => state.selectedNavIndex),
    );
    final viewModel = ref.read(heroHomeViewModelProvider.notifier);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final safeBottom = mediaQuery.padding.bottom;

    // Responsive breakpoints
    final isVeryCompact = screenWidth < 340;
    final isCompact = screenWidth < 360;
    final isSmall = screenWidth < 375;
    final isMedium = screenWidth < 414;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;

    // Calculate scale factor based on screen width
    // Base reference: 375px (iPhone SE/8)
    final scaleFactor = (screenWidth / 375.0).clamp(0.85, 1.5);

    // Responsive navbar height
    final navHeight = isVeryCompact
        ? 82.0
        : isCompact
        ? 84.0
        : isSmall
        ? 86.0
        : isMedium
        ? 88.0
        : isTablet
        ? 92.0
        : isDesktop
        ? 96.0
        : 88.0;

    // Responsive padding
    final padding = (8.0 * scaleFactor).clamp(6.0, 20.0);
    final bottomPadding = safeBottom > 0
        ? safeBottom
        : (12.0 * scaleFactor).clamp(10.0, 24.0);

    // Responsive item padding
    final itemPadding = (6.0 * scaleFactor).clamp(4.0, 12.0);

    // Responsive font size
    final fontSize = (11.0 * scaleFactor).clamp(9.5, 14.0);

    // Responsive icon size
    final iconSize = (26.0 * scaleFactor).clamp(22.0, 32.0);

    // Responsive center gap (for FAB)
    final centerGapWidth = (64.0 * scaleFactor).clamp(50.0, 80.0);

    // Responsive border radius
    final navRadius = (26.0 * scaleFactor).clamp(22.0, 32.0);

    final navBackground = backgroundWhite.withOpacity(0.92);

    // Responsive badge size
    final badgeFontSize = (8.0 * scaleFactor).clamp(7.0, 10.0);
    final badgeMinSize = (14.0 * scaleFactor).clamp(12.0, 18.0);

    final int chatCount = ref.watch(
      userChatsProvider.select(
        (async) => async.maybeWhen(
          data: (chats) => chats.length,
          orElse: () => 0,
        ),
      ),
    );

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: padding,
          right: padding,
          bottom: bottomPadding,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(navRadius),
            border: Border.all(color: textGray900.withOpacity(0.06), width: 1),
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
                      children: <Widget>[
                        Expanded(
                          child: _buildNavItem(
                            context,
                            Icons.home,
                            'Inicio',
                            0,
                            selectedIndex,
                            () => viewModel.selectNavItem(0),
                            itemPadding: itemPadding,
                            fontSize: fontSize,
                            iconSize: iconSize,
                            badgeFontSize: badgeFontSize,
                            badgeMinSize: badgeMinSize,
                          ),
                        ),
                        Expanded(
                          child: _buildNavItem(
                            context,
                            Icons.location_on_outlined,
                            'Ubicación',
                            1,
                            selectedIndex,
                            () => viewModel.selectNavItem(1),
                            itemPadding: itemPadding,
                            fontSize: fontSize,
                            iconSize: iconSize,
                            badgeFontSize: badgeFontSize,
                            badgeMinSize: badgeMinSize,
                          ),
                        ),
                        SizedBox(width: centerGapWidth),
                        Expanded(
                          child: _buildNavItem(
                            context,
                            Icons.chat_bubble_outline,
                            'Chat',
                            3,
                            selectedIndex,
                            () => viewModel.selectNavItem(3),
                            badgeCount: chatCount > 0 ? chatCount : null,
                            itemPadding: itemPadding,
                            fontSize: fontSize,
                            iconSize: iconSize,
                            badgeFontSize: badgeFontSize,
                            badgeMinSize: badgeMinSize,
                          ),
                        ),
                        Expanded(
                          child: _buildNavItem(
                            context,
                            Icons.person_outline,
                            'Perfil',
                            4,
                            selectedIndex,
                            () => viewModel.selectNavItem(4),
                            itemPadding: itemPadding,
                            fontSize: fontSize,
                            iconSize: iconSize,
                            badgeFontSize: badgeFontSize,
                            badgeMinSize: badgeMinSize,
                          ),
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
    required double badgeFontSize,
    required double badgeMinSize,
  }) {
    final bool isActive = selectedIndex == index;
    Color iconColor = isActive ? primaryOrange : textGray600;
    Color backgroundColor = isActive
        ? primaryOrange.withOpacity(0.12)
        : Colors.transparent;
    Color textColor = isActive ? primaryOrange : textGray600;

    return ClipRRect(
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
                  : Border.all(color: textGray900.withOpacity(0.04), width: 1),
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
                          constraints: BoxConstraints(
                            minWidth: badgeMinSize,
                            minHeight: badgeMinSize,
                          ),
                          child: Text(
                            badgeCount.toString(),
                            style: TextStyle(
                              color: backgroundWhite,
                              fontSize: badgeFontSize,
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
    );
  }
}

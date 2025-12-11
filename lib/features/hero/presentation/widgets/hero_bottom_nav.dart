import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../viewmodels/hero_home_viewmodel.dart';

/// Widget del navbar inferior con animaciones
class HeroBottomNav extends ConsumerWidget {
  const HeroBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(heroHomeViewModelProvider);
    final viewModel = ref.read(heroHomeViewModelProvider.notifier);

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: textGray900.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, -6),
              spreadRadius: 3,
            ),
            BoxShadow(
              color: primaryOrange.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BottomAppBar(
            shape: const CircularNotchedRectangle(),
            notchMargin: 12.0,
            elevation: 0,
            color: backgroundWhite,
            child: SizedBox(
              height: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  _buildNavItem(
                    context,
                    Icons.home,
                    'Inicio',
                    0,
                    state.selectedNavIndex,
                    () => viewModel.selectNavItem(0),
                  ),
                  _buildNavItem(
                    context,
                    Icons.location_on_outlined,
                    'Ubicación',
                    1,
                    state.selectedNavIndex,
                    () => viewModel.selectNavItem(1),
                  ),
                  const Spacer(flex: 2),
                  _buildNavItem(
                    context,
                    Icons.notifications_none_outlined,
                    'Avisos',
                    3,
                    state.selectedNavIndex,
                    () => viewModel.selectNavItem(3),
                    badgeCount: 2,
                  ),
                  _buildNavItem(
                    context,
                    Icons.person_outline,
                    'Perfil',
                    4,
                    state.selectedNavIndex,
                    () => viewModel.selectNavItem(4),
                  ),
                ],
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
  }) {
    final bool isActive = selectedIndex == index;
    Color iconColor = isActive ? primaryOrange : textGray600;
    Color backgroundColor = isActive ? primaryOrange.withOpacity(0.12) : Colors.transparent;
    Color textColor = isActive ? primaryOrange : textGray600;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: primaryOrange.withOpacity(0.15),
          highlightColor: primaryOrange.withOpacity(0.08),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: isActive
                  ? Border.all(
                      color: primaryOrange.withOpacity(0.2),
                      width: 1.5,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: iconColor, size: 26),
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
                                color: primaryOrange.withOpacity(0.4),
                                blurRadius: 6,
                                spreadRadius: 2,
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
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: isActive ? 0.3 : 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

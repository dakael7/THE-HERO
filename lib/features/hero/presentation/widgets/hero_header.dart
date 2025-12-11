import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';

const double paddingNormal = 16.0;
const double paddingLarge = 24.0;

/// Delegate para el header colapsable con logo, notificación y barra de búsqueda
class HeroHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function() buildLogoSection;
  final Widget Function() buildNotificationIcon;
  final Widget Function() buildSearchBar;

  HeroHeaderDelegate({
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.buildLogoSection,
    required this.buildNotificationIcon,
    required this.buildSearchBar,
  });

  @override
  double get minExtent => collapsedHeight;

  @override
  double get maxExtent => expandedHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double availableRange = maxExtent - minExtent;
    final double t = availableRange > 0
        ? (shrinkOffset / availableRange).clamp(0.0, 1.0)
        : 0.0;

    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      decoration: const BoxDecoration(
        color: primaryYellow,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Stack(
        children: [
          // Fila superior (logo + notificaciones) que se oculta al hacer scroll
          Positioned(
            top: statusBarHeight + paddingNormal - 8 * t,
            left: paddingLarge,
            right: paddingLarge,
            child: Opacity(
              opacity: 1.0 - t,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  buildLogoSection(),
                  buildNotificationIcon(),
                ],
              ),
            ),
          ),

          // Barra de búsqueda fija en la parte inferior del header
          Positioned(
            left: paddingNormal,
            right: paddingNormal,
            bottom: 12.0,
            child: buildSearchBar(),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HeroHeaderDelegate oldDelegate) {
    return expandedHeight != oldDelegate.expandedHeight ||
        collapsedHeight != oldDelegate.collapsedHeight ||
        buildLogoSection != oldDelegate.buildLogoSection ||
        buildNotificationIcon != oldDelegate.buildNotificationIcon ||
        buildSearchBar != oldDelegate.buildSearchBar;
  }
}

/// Widget del header con logo, notificación y buscador
class HeroHeader extends StatelessWidget {
  final VoidCallback? onSearchChanged;

  const HeroHeader({
    super.key,
    this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveUtils.isMobile(context);
    final expandedHeight = isMobile ? 220.0 : 200.0;
    final collapsedHeight = isMobile ? 140.0 : 130.0;
    
    return SliverPersistentHeader(
      pinned: true,
      delegate: HeroHeaderDelegate(
        expandedHeight: expandedHeight,
        collapsedHeight: collapsedHeight,
        buildLogoSection: _buildLogoSection,
        buildNotificationIcon: _buildNotificationIcon,
        buildSearchBar: _buildSearchBar,
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo_1.png', height: 36, fit: BoxFit.contain),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: backgroundWhite.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: textGray900.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.notifications_none_outlined,
            color: primaryOrange,
            size: 26,
          ),
        ),
        Positioned(
          right: 0,
          top: -4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: primaryOrange,
              shape: BoxShape.circle,
              border: Border.all(color: backgroundWhite, width: 1.5),
            ),
            constraints: const BoxConstraints(
              minWidth: 16,
              minHeight: 16,
            ),
            child: const Text(
              '1',
              style: TextStyle(
                color: backgroundWhite,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: paddingNormal),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: textGray900.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: primaryOrange.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          hintStyle: const TextStyle(color: textGray600, fontSize: 15),
          prefixIcon: const Icon(Icons.search, color: primaryOrange, size: 24),
          suffixIcon: Icon(Icons.tune, color: primaryOrange.withOpacity(0.6), size: 22),
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        ),
        style: const TextStyle(color: textGray900, fontSize: 15),
        cursorColor: primaryOrange,
      ),
    );
  }
}

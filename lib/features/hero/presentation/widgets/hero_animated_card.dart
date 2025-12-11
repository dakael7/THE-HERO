import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';

const double paddingNormal = 16.0;

/// Widget de tarjeta animada para "Sé un Héroe" y "Encuentra"
class AnimatedHeroCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const AnimatedHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  State<AnimatedHeroCard> createState() => _AnimatedHeroCardState();
}

class _AnimatedHeroCardState extends State<AnimatedHeroCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 0.1,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    _controller.forward();
  }

  void _onTapUp(_) {
    _controller.reverse().then((_) {
      widget.onTap();
    });
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  Widget _buildCardContent(BuildContext context) {
    final padding = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: paddingNormal,
      tabletPadding: 20.0,
      desktopPadding: 24.0,
    );
    final titleFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 17,
      tabletSize: 18,
      desktopSize: 19,
    );
    final subtitleFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 14,
      tabletSize: 15,
      desktopSize: 16,
    );
    final iconSize = ResponsiveUtils.isMobile(context) ? 36.0 : 40.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: textGray900.withOpacity(0.1),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(padding * 0.6),
            decoration: BoxDecoration(
              color: primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, color: primaryOrange, size: iconSize),
          ),
          SizedBox(height: padding * 0.75),
          Text(
            widget.title,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.w700,
              color: textGray900,
            ),
          ),
          SizedBox(height: padding * 0.25),
          Text(
            widget.subtitle,
            style: TextStyle(fontSize: subtitleFontSize, color: textGray600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: _buildCardContent(context),
      ),
    );
  }
}

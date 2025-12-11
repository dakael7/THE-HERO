import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';

const double paddingNormal = 16.0;

class AnimatedHeroCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? accentColor;
  final Color? backgroundColor;
  final Color? iconBackgroundColor;

  const AnimatedHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accentColor,
    this.backgroundColor,
    this.iconBackgroundColor,
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
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );
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
    final Color accentColor = widget.accentColor ?? primaryOrange;
    final Color cardBackgroundColor =
        widget.backgroundColor ?? backgroundWhite;
    final Color iconBackgroundColor =
        widget.iconBackgroundColor ?? accentColor.withOpacity(0.12);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 0.7,
      ),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: textGray900.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(padding * 0.55),
            decoration: BoxDecoration(
              color: iconBackgroundColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              widget.icon,
              color: accentColor,
              size: iconSize,
            ),
          ),
          SizedBox(height: padding * 0.6),
          Text(
            widget.title,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          SizedBox(height: padding * 0.25),
          Text(
            widget.subtitle,
            style: TextStyle(fontSize: subtitleFontSize, color: textGray600),
          ),
          SizedBox(height: padding * 0.35),
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

import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';

const double paddingNormal = 16.0;

class AnimatedHeroCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
    final Color accentColor = this.accentColor ?? primaryOrange;
    final Color cardBackgroundColor = backgroundColor ?? backgroundWhite;
    final Color iconBackgroundColor =
        this.iconBackgroundColor ?? accentColor.withOpacity(0.12);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: accentColor.withOpacity(0.08),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: padding,
            vertical: padding * 0.8,
          ),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withOpacity(0.15),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(padding * 0.5),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: iconSize),
              ),
              SizedBox(height: padding * 0.7),
              Text(
                title,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              SizedBox(height: padding * 0.3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: subtitleFontSize,
                  color: textGray600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: padding * 0.2),
            ],
          ),
        ),
      ),
    );
  }
}

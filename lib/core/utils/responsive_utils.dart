import 'package:flutter/material.dart';

class ResponsiveUtils {
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1200;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1200;
  }

  static double getScreenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static double getScreenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  static double responsiveFontSize(
    BuildContext context, {
    required double mobileSize,
    double? tabletSize,
    double? desktopSize,
  }) {
    final width = getScreenWidth(context);
    if (width < 600) {
      return mobileSize;
    } else if (width < 1200) {
      return tabletSize ?? mobileSize * 1.1;
    } else {
      return desktopSize ?? mobileSize * 1.2;
    }
  }

  static double responsivePadding(
    BuildContext context, {
    required double mobilePadding,
    double? tabletPadding,
    double? desktopPadding,
  }) {
    final width = getScreenWidth(context);
    if (width < 600) {
      return mobilePadding;
    } else if (width < 1200) {
      return tabletPadding ?? mobilePadding * 1.2;
    } else {
      return desktopPadding ?? mobilePadding * 1.5;
    }
  }

  static double responsiveWidth(
    BuildContext context, {
    required double mobileWidth,
    double? tabletWidth,
    double? desktopWidth,
  }) {
    final width = getScreenWidth(context);
    if (width < 600) {
      return mobileWidth;
    } else if (width < 1200) {
      return tabletWidth ?? mobileWidth * 1.1;
    } else {
      return desktopWidth ?? mobileWidth * 1.2;
    }
  }

  static int getGridColumns(BuildContext context) {
    final width = getScreenWidth(context);
    if (width < 600) {
      return 2;
    } else if (width < 1200) {
      return 3;
    } else {
      return 4;
    }
  }

  static double getMaxContentWidth(BuildContext context) {
    final width = getScreenWidth(context);
    if (width < 600) {
      return width - 32;
    } else if (width < 1200) {
      return 600;
    } else {
      return 900;
    }
  }
}

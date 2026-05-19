import 'package:flutter/material.dart';

/// Responsive sizing utilities for industry-standard screen adaptation.
///
/// All values are calculated relative to a reference design (1920x1080)
/// and scaled based on the current screen size using MediaQuery.
class ScreenUtils {
  static const double _referenceWidth = 1920.0;
  static const double _referenceHeight = 1080.0;
  static const double _referenceDiagonal = 2202.9;

  static late BuildContext _context;

  static void init(BuildContext context) {
    _context = context;
  }

  static double get width => MediaQuery.sizeOf(_context).width;
  static double get height => MediaQuery.sizeOf(_context).height;
  static double get diagonal {
    final size = MediaQuery.sizeOf(_context);
    final sum = size.width * size.width + size.height * size.height;
    return _sqrt(sum);
  }

  static double get scaleWidth => width / _referenceWidth;
  static double get scaleHeight => height / _referenceHeight;
  static double get scaleDiagonal => diagonal / _referenceDiagonal;

  /// Scale a dimension using the geometric mean of width and height scaling.
  static double get scaleFactor => _sqrt(scaleWidth * scaleHeight);

  /// Scale a width value proportionally.
  static double w(double width) => width * scaleWidth;

  /// Scale a height value proportionally.
  static double h(double height) => height * scaleHeight;

  /// Scale a font size using diagonal scaling for better readability.
  static double sp(double fontSize) => fontSize * scaleDiagonal;

  /// Scale a value using the geometric mean factor.
  static double r(double value) => value * scaleFactor;

  /// Responsive padding that adapts to screen size.
  static EdgeInsets padding({
    double horizontal = 32,
    double vertical = 24,
    double all = 0,
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) {
    if (all > 0) {
      return EdgeInsets.all(r(all));
    }
    return EdgeInsets.only(
      left: left > 0 ? w(left) : w(horizontal),
      top: top > 0 ? h(top) : h(vertical),
      right: right > 0 ? w(right) : w(horizontal),
      bottom: bottom > 0 ? h(bottom) : h(vertical),
    );
  }

  /// Responsive border radius.
  static double radius(double value) => r(value);

  /// Clamp font size to a reasonable range to prevent extreme values.
  static double clampedSp(double fontSize, {double min = 8, double max = 120}) {
    return sp(fontSize).clamp(min, max);
  }

  /// Get responsive grid configuration based on capacity and screen size.
  static SliverGridDelegate gridDelegate({
    required int capacity,
    double baseMaxExtent = 60,
    double baseMainSpacing = 12,
    double baseCrossSpacing = 12,
  }) {
    final maxExtent = r(baseMaxExtent).clamp(30.0, 100.0);
    final mainSpacing = r(baseMainSpacing).clamp(4.0, 24.0);
    final crossSpacing = r(baseCrossSpacing).clamp(4.0, 24.0);

    if (capacity > 200) {
      return SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent * 0.8,
        mainAxisSpacing: mainSpacing * 0.7,
        crossAxisSpacing: crossSpacing * 0.7,
        childAspectRatio: 1,
      );
    } else if (capacity > 100) {
      return SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        mainAxisSpacing: mainSpacing,
        crossAxisSpacing: crossSpacing,
        childAspectRatio: 1,
      );
    } else {
      return SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent * 1.2,
        mainAxisSpacing: mainSpacing * 1.2,
        crossAxisSpacing: crossSpacing * 1.2,
        childAspectRatio: 1,
      );
    }
  }

  /// Responsive header height.
  static double headerHeight() => h(72).clamp(56.0, 96.0);

  /// Responsive footer height.
  static double footerHeight() => h(72).clamp(56.0, 96.0);
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}

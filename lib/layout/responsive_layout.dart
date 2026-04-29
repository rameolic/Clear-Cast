import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Window-aware spacing and typography used across [lib/] screens.
///
/// Built from the tight [Size] from [LayoutBuilder] or [MediaQuery.sizeOf].
class ResponsiveLayout {
  const ResponsiveLayout(this.size);

  final Size size;

  double get w => size.width;
  double get h => size.height;
  double get shortestSide => math.min(w, h);

  /// Narrow phone / small floating window.
  bool get isCompactWidth => w < 520;

  /// Short window (e.g. snapped desktop).
  bool get isCompactHeight => h < 420;

  // --- Grid (home) ---
  double gridSpacing() => (w * 0.012).clamp(8.0, 22.0);
  double gridHorizontalPadding() => (w * 0.04).clamp(16.0, 56.0);
  double gridBottomPadding() => (h * 0.055).clamp(20.0, 56.0);
  double gridMaxCrossAxisExtent() => (w * 0.26).clamp(220.0, 380.0);

  static const double gridAspectRatio = 16 / 11;

  // --- Home header ---
  EdgeInsets headerPadding() => EdgeInsets.fromLTRB(
        gridHorizontalPadding(),
        (h * 0.042).clamp(18.0, 44.0),
        gridHorizontalPadding(),
        (h * 0.028).clamp(14.0, 32.0),
      );

  double headerLogoBox() => (shortestSide * 0.055).clamp(32.0, 52.0);
  double headerLogoIcon() => headerLogoBox() * 0.58;
  double headerTitleSize() => (w * 0.017).clamp(16.0, 26.0);
  double headerSubtitleSize() => (w * 0.009).clamp(10.0, 14.0);
  double headerTitleLetterSpacing() => (w * 0.003).clamp(1.5, 4.0);

  EdgeInsets refreshButtonPadding() => EdgeInsets.symmetric(
        horizontal: (w * 0.012).clamp(12.0, 24.0),
        vertical: (h * 0.012).clamp(8.0, 14.0),
      );

  double refreshIconSize() => (shortestSide * 0.028).clamp(16.0, 22.0);
  double refreshLabelSize() => (w * 0.008).clamp(11.0, 15.0);

  // --- Home body: loading / error / empty ---
  EdgeInsets centeredHorizontalPadding() =>
      EdgeInsets.symmetric(horizontal: gridHorizontalPadding());

  double bodyIconLarge() => (shortestSide * 0.14).clamp(40.0, 72.0);
  double bodyTitleSize() => (w * 0.014).clamp(16.0, 22.0);
  double bodyBodySize() => (w * 0.009).clamp(11.0, 15.0);
  double bodyGapLarge() => (h * 0.022).clamp(12.0, 28.0);
  double bodyGapSmall() => (h * 0.012).clamp(6.0, 14.0);

  EdgeInsets retryButtonPadding() => EdgeInsets.symmetric(
        horizontal: (w * 0.02).clamp(18.0, 36.0),
        vertical: (h * 0.014).clamp(10.0, 16.0),
      );

  double retryLabelSize() => (w * 0.008).clamp(13.0, 17.0);

  /// Max width for centered messages so text wraps on ultra-wide displays.
  double centeredContentMaxWidth() => (w * 0.92).clamp(280.0, 560.0);

  // --- WebView toolbar ---
  double toolbarHeight() => (shortestSide * 0.065).clamp(44.0, 68.0);
  double toolbarHorizontalPadding() => (w * 0.018).clamp(10.0, 24.0);
  double toolbarTitleSize() => (w * 0.009).clamp(12.0, 16.0);
  double toolbarBadgeFontSize() => (w * 0.007).clamp(8.0, 11.0);
  EdgeInsets toolbarBadgePadding() => EdgeInsets.symmetric(
        horizontal: (w * 0.008).clamp(6.0, 14.0),
        vertical: (h * 0.005).clamp(3.0, 8.0),
      );

  EdgeInsets tvButtonPadding() => EdgeInsets.symmetric(
        horizontal: (w * 0.01).clamp(10.0, 18.0),
        vertical: (h * 0.01).clamp(6.0, 12.0),
      );

  double tvButtonIconSize() => (shortestSide * 0.026).clamp(14.0, 20.0);
  double tvButtonLabelSize() => (w * 0.0075).clamp(10.0, 14.0);

  // --- Grid tile ([size] = LayoutBuilder constraints for that tile region) ---
  double tileThumbDisplayHeight() => math.min(w * 9 / 16, h);

  double tileThumbIconSize() =>
      (math.min(w, tileThumbDisplayHeight()) * 0.38).clamp(20.0, 52.0);

  double tileInfoPadH() => (w * 0.07).clamp(4.0, 14.0);
  double tileInfoPadV() => (h * 0.06).clamp(2.0, 12.0);
  double tileInfoGapSmall() => (h * 0.06).clamp(2.0, 6.0);
  double tileInfoGapBeforeBadge() => (h * 0.08).clamp(4.0, 10.0);
  double tileTitleSize() => (w * 0.052).clamp(11.0, 15.0);
  double tileDescSize() => (w * 0.038).clamp(9.0, 11.0);
  double tileBadgeSize() => (w * 0.032).clamp(7.0, 10.0);

  double tileBadgeInnerPaddingH(double innerWidth) =>
      (innerWidth * 0.06).clamp(4.0, 10.0);
}

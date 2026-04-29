import 'package:flutter/material.dart';

import 'clearcast_colors.dart';

ThemeData buildClearCastTheme() {
  const primary = ClearCastColors.lime;
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: ClearCastColors.scaffold,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: ClearCastColors.onLime,
      surface: ClearCastColors.surface,
      onSurface: Colors.white,
      secondary: ClearCastColors.darkGreen,
    ),
    focusColor: primary.withValues(alpha: 0.22),
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
  );
}

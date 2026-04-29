import 'package:flutter/material.dart';

/// Brand palette aligned with ClearCast logo (forest → lime gradient).
abstract final class ClearCastColors {
  static const Color darkGreen = Color(0xFF1B8E41);
  static const Color lime = Color(0xFF93C643);

  static const Color scaffold = Color(0xFF0C1510);
  static const Color scaffoldDeep = Color(0xFF080E0C);

  static const Color surface = Color(0xFF142318);
  static const Color surfaceMuted = Color(0xFF1A2E20);

  /// Text / icons on lime fills (buttons, badges).
  static const Color onLime = Color(0xFF071209);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [darkGreen, lime],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

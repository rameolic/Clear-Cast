import 'package:flutter/material.dart';

import '../theme/clearcast_colors.dart';

/// Lime focus ring drawn above the WebView on Android TV (always visible to the user).
class TvWebCursorOverlay extends StatelessWidget {
  final Offset position;

  const TvWebCursorOverlay({super.key, required this.position});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 15,
      top: position.dy - 15,
      child: IgnorePointer(
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ClearCastColors.lime, width: 3),
            color: ClearCastColors.lime.withValues(alpha: 0.4),
            boxShadow: [
              BoxShadow(
                color: ClearCastColors.lime.withValues(alpha: 0.75),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: ClearCastColors.lime,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

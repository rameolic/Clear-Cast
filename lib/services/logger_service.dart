import 'package:flutter/foundation.dart';

class AppLogger {
  static const String _tag = 'ClearCast';

  static void info(String message) {
    if (kDebugMode) {
      debugPrint('[$_tag][INFO] $message');
    }
  }

  static void warn(String message) {
    if (kDebugMode) {
      debugPrint('[$_tag][WARN] $message');
    }
  }

  static void error(String message, [Object? error]) {
    if (!kDebugMode) {
      return;
    }
    if (error == null) {
      debugPrint('[$_tag][ERROR] $message');
      return;
    }
    debugPrint('[$_tag][ERROR] $message | $error');
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logger_service.dart';

/// Runtime device class: Android TV / Android handheld / other.
class DeviceProfile {
  final bool isAndroidTv;
  final bool isAndroidHandheld;
  final bool prefersDpadNavigation;

  const DeviceProfile({
    required this.isAndroidTv,
    required this.isAndroidHandheld,
    required this.prefersDpadNavigation,
  });

  static const DeviceProfile desktop = DeviceProfile(
    isAndroidTv: false,
    isAndroidHandheld: false,
    prefersDpadNavigation: false,
  );

  static const DeviceProfile androidTv = DeviceProfile(
    isAndroidTv: true,
    isAndroidHandheld: false,
    prefersDpadNavigation: true,
  );

  static const DeviceProfile androidHandheld = DeviceProfile(
    isAndroidTv: false,
    isAndroidHandheld: true,
    prefersDpadNavigation: false,
  );
}

class DeviceProfileService {
  DeviceProfileService._();
  static final DeviceProfileService instance = DeviceProfileService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.flutter_tv_app/device');

  DeviceProfile _profile = DeviceProfile.desktop;
  bool _initialized = false;

  DeviceProfile get profile => _profile;
  bool get isAndroidTv => _profile.isAndroidTv;
  bool get isAndroidHandheld => _profile.isAndroidHandheld;
  bool get prefersDpadNavigation => _profile.prefersDpadNavigation;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb) {
      _profile = DeviceProfile.desktop;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      var isTv = false;
      try {
        final result = await _channel.invokeMethod<bool>('isAndroidTv');
        isTv = result ?? false;
      } catch (e) {
        AppLogger.warn('Android TV detection failed, assuming phone/tablet: $e');
      }
      _profile = isTv ? DeviceProfile.androidTv : DeviceProfile.androidHandheld;
    } else {
      _profile = DeviceProfile.desktop;
    }

    _initialized = true;
    AppLogger.info(
      'Device profile: '
      '${_profile.isAndroidTv ? 'Android TV' : _profile.isAndroidHandheld ? 'Android handheld' : 'desktop/other'}',
    );
  }
}

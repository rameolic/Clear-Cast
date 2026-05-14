import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/ad_blocker_service.dart';
import 'services/device_profile_service.dart';
import 'theme/clearcast_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await DeviceProfileService.instance.initialize();
    if (DeviceProfileService.instance.isAndroidTv) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  } else {
    await DeviceProfileService.instance.initialize();
  }

  await AdBlockerService().initialize();
  runApp(const ClearCastApp());
}

class ClearCastApp extends StatelessWidget {
  const ClearCastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClearCast',
      debugShowCheckedModeBanner: false,
      theme: buildClearCastTheme(),
      home: const HomeScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/settings_providers.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the saved theme mode before the first frame so there's no flash.
  // Heavier startup work (DB, background service, tile cache) runs in
  // SplashScreen so the branded loader is visible while it happens.
  final mode = await SettingsService.instance.loadThemeMode();
  final unit = await SettingsService.instance.loadSpeedUnit();
  final recordView = await SettingsService.instance.loadRecordView();
  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((ref) => ThemeModeController(mode)),
        speedUnitProvider.overrideWith((ref) => SpeedUnitController(unit)),
        recordViewProvider
            .overrideWith((ref) => RecordViewController(recordView)),
      ],
      child: const ThrottlePathApp(),
    ),
  );
}

class ThrottlePathApp extends ConsumerWidget {
  const ThrottlePathApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'ThrottlePath',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: mode,
      home: const SplashScreen(),
    );
  }
}

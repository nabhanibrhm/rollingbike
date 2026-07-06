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
  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((ref) => ThemeModeController(mode)),
      ],
      child: const RollingBikeApp(),
    ),
  );
}

class RollingBikeApp extends ConsumerWidget {
  const RollingBikeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'RollingBike',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: mode,
      home: const SplashScreen(),
    );
  }
}

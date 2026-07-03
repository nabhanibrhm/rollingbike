import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';
import 'ui/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Startup work (open the DB, register the background tracking service) runs
  // inside SplashScreen so the branded loader is visible while it happens.
  runApp(const ProviderScope(child: RollingBikeApp()));
}

class RollingBikeApp extends StatelessWidget {
  const RollingBikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RollingBike',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}

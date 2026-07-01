import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database_service.dart';
import 'services/tracking_service.dart';
import 'theme/app_theme.dart';
import 'ui/tracking_map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Open the local DB and register the background tracking service before the
  // first frame so the map screen can start a ride immediately.
  await DatabaseService.instance.open();
  await TrackingService.instance.configure();
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
      home: const TrackingMapScreen(),
    );
  }
}

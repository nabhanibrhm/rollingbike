import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';

/// Holds the active [ThemeMode] and persists every change.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(super.state);

  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await SettingsService.instance.saveThemeMode(mode);
  }

  /// Flip between dark and light.
  Future<void> toggle() =>
      setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

/// The app's theme mode. Seeded in `main()` (via override) with the persisted
/// value so there is no theme flash on launch.
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ThemeMode.dark),
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/units.dart';
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

/// Holds the display speed/distance unit and persists every change.
class SpeedUnitController extends StateNotifier<SpeedUnit> {
  SpeedUnitController(super.state);

  Future<void> setUnit(SpeedUnit unit) async {
    if (unit == state) return;
    state = unit;
    await SettingsService.instance.saveSpeedUnit(unit);
  }

  /// Flip between km/h and mph.
  Future<void> toggle() =>
      setUnit(state == SpeedUnit.kmh ? SpeedUnit.mph : SpeedUnit.kmh);
}

/// The display unit for speeds and distances. Seeded in `main()` (via override)
/// with the persisted value.
final speedUnitProvider =
    StateNotifierProvider<SpeedUnitController, SpeedUnit>(
  (ref) => SpeedUnitController(SpeedUnit.kmh),
);

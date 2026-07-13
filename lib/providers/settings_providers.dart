import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/record_view.dart';
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

/// Holds the Record screen's backdrop view (map / chart / none) and persists
/// every change.
class RecordViewController extends StateNotifier<RecordView> {
  RecordViewController(super.state);

  Future<void> set(RecordView view) async {
    if (view == state) return;
    state = view;
    await SettingsService.instance.saveRecordView(view);
  }

  /// Advance to the next view in the cycle map → chart → none → map.
  Future<void> cycle() => set(state.next);
}

/// The Record screen's backdrop view. Seeded in `main()` (via override) with
/// the persisted value so the last-used view is shown without a flash.
final recordViewProvider =
    StateNotifierProvider<RecordViewController, RecordView>(
  (ref) => RecordViewController(RecordView.none),
);

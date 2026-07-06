import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny file-backed store for user preferences. Kept dependency-free (plain file
/// via path_provider, no shared_preferences) in keeping with the offline-first
/// ethos — currently just the theme mode.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _fileName = 'settings.txt';

  File? _file;

  Future<File> _resolve() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    return _file = File('${dir.path}/$_fileName');
  }

  /// Loads the saved theme mode. Defaults to dark (the app's original look) on
  /// first run or any read error.
  Future<ThemeMode> loadThemeMode() async {
    try {
      final f = await _resolve();
      if (!await f.exists()) return ThemeMode.dark;
      return switch ((await f.readAsString()).trim()) {
        'light' => ThemeMode.light,
        _ => ThemeMode.dark,
      };
    } catch (_) {
      return ThemeMode.dark;
    }
  }

  /// Persists the theme mode. Best-effort — a write failure is non-fatal.
  Future<void> saveThemeMode(ThemeMode mode) async {
    try {
      final f = await _resolve();
      await f.writeAsString(mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {
      // best-effort; the choice still applies for this session
    }
  }
}

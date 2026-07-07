import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'location_source.dart';

/// Tiny file-backed store for user preferences. Kept dependency-free (plain file
/// via path_provider, no shared_preferences) in keeping with the offline-first
/// ethos — currently the theme mode and the (temporary) GPS-source A/B choice.
///
/// Each preference lives in its own tiny file so the background isolate can read
/// the GPS-source choice without parsing a shared format.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _fileName = 'settings.txt';
  static const _gpsSourceFileName = 'gps_source.txt';

  File? _file;

  Future<File> _resolve() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    return _file = File('${dir.path}/$_fileName');
  }

  Future<File> _resolveNamed(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$name');
  }

  /// Loads the chosen GPS source. Defaults to [LocationSourceKind.fused] (the
  /// app's original behaviour) on first run or any read error. Read from the
  /// background isolate at ride start.
  Future<LocationSourceKind> loadGpsSource() async {
    try {
      final f = await _resolveNamed(_gpsSourceFileName);
      if (!await f.exists()) return LocationSourceKind.fused;
      return LocationSourceKind.fromTag((await f.readAsString()).trim());
    } catch (_) {
      return LocationSourceKind.fused;
    }
  }

  /// Persists the GPS-source choice. Best-effort.
  Future<void> saveGpsSource(LocationSourceKind kind) async {
    try {
      final f = await _resolveNamed(_gpsSourceFileName);
      await f.writeAsString(kind.tag);
    } catch (_) {
      // best-effort; the choice still applies once written next time
    }
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

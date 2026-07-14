import 'package:geocoding/geocoding.dart';

/// Best-effort reverse geocoding for ride start/end place names.
///
/// Online-only (the platform Geocoder needs network). Every failure — offline,
/// no result, platform error, or timeout — resolves to `null`, so callers
/// persist a place name when one is available and simply omit it otherwise. The
/// app stays offline-first: place names are a nicety, never a requirement.
class GeocodingService {
  const GeocodingService._();

  /// Cap each lookup so a slow/unreachable geocoder can't hang the caller.
  static const Duration _timeout = Duration(seconds: 8);

  /// Reverse-geocodes [lat]/[lon] to a short, human place label (e.g.
  /// "Bandung"), or `null` if it can't be resolved.
  static Future<String?> placeName(double lat, double lon) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(lat, lon).timeout(_timeout);
      if (placemarks.isEmpty) return null;
      return _label(placemarks.first);
    } catch (_) {
      return null; // offline / no service / no result — best-effort.
    }
  }

  /// Picks the most useful city/town-level field, most specific first, skipping
  /// blanks (the platform leaves unknown fields empty rather than null).
  static String? _label(Placemark p) {
    for (final candidate in [
      p.locality,
      p.subAdministrativeArea,
      p.subLocality,
      p.administrativeArea,
    ]) {
      final v = candidate?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }
}

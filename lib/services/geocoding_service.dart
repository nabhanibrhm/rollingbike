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

  /// How many times to try a single lookup. Android's platform `Geocoder` is
  /// rate-limited and often fails a call that's fired right after another
  /// ("Service not Available" / empty result), which is exactly what left rides
  /// with only one of the two place names. A couple of backed-off retries ride
  /// that out.
  static const int _maxAttempts = 3;

  /// Base delay between retries (grows linearly per attempt).
  static const Duration _retryBackoff = Duration(milliseconds: 400);

  /// Reverse-geocodes [lat]/[lon] to a short, human place label (e.g.
  /// "Bandung"), or `null` if it can't be resolved. Retries transient failures
  /// (rate-limit / timeout / empty) with backoff; a resolved placemark that
  /// simply has no useful field returns `null` without retrying.
  static Future<String?> placeName(double lat, double lon) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (attempt > 0) await Future.delayed(_retryBackoff * attempt);
      try {
        final placemarks =
            await placemarkFromCoordinates(lat, lon).timeout(_timeout);
        if (placemarks.isEmpty) continue; // often a transient rate-limit — retry
        return _label(placemarks.first);
      } catch (_) {
        // offline / no service / rate-limited / timeout — retry, then give up.
      }
    }
    return null; // best-effort: never a hard requirement.
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

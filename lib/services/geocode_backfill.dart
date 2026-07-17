import '../data/database_service.dart';
import 'geocoding_service.dart';

/// Best-effort backfill of missing ride start/end place names.
///
/// Geocoding runs once, fire-and-forget, right after a ride is saved
/// ([_geocodeRide]) — so a ride saved while offline (common straight after a
/// ride, especially in a tunnel/train) never gets place names, and was never
/// retried. This fills that gap: whenever the History screen is shown it
/// re-attempts a bounded number of rides that still lack a place, so they fill
/// in later once the phone is back online.
///
/// Stays offline-first: every lookup is best-effort and online-only, so this is
/// a silent no-op when offline. A guard prevents overlapping runs.
class GeocodeBackfill {
  GeocodeBackfill._();
  static final GeocodeBackfill instance = GeocodeBackfill._();

  /// Max rides to attempt per invocation — keeps the platform Geocoder within
  /// its rate limit and avoids a burst on a long history. Older rides are
  /// picked up on later visits.
  static const int _maxPerRun = 4;

  bool _running = false;

  /// Attempts to resolve places for rides still missing them. Calls [onUpdated]
  /// once if any ride was filled in, so the caller can refresh the list.
  Future<void> run({required void Function() onUpdated}) async {
    if (_running) return;
    _running = true;
    try {
      final db = DatabaseService.instance;
      final missing = await db.getRidesMissingPlaces();
      var updated = 0;
      for (final ride in missing.take(_maxPerRun)) {
        // Only look up the field(s) actually missing; keep any already resolved.
        var startPlace = ride.startPlace;
        var endPlace = ride.endPlace;

        if (startPlace == null) {
          final start = await db.getFirstTrackPoint(ride.id);
          if (start != null) {
            startPlace =
                await GeocodingService.placeName(start.latitude, start.longitude);
          }
        }
        if (endPlace == null) {
          final end = await db.getLastTrackPoint(ride.id);
          if (end != null) {
            endPlace =
                await GeocodingService.placeName(end.latitude, end.longitude);
          }
        }

        // Nothing new resolved (still offline / genuinely unresolvable) — skip
        // the write and try again on a later visit.
        if (startPlace == ride.startPlace && endPlace == ride.endPlace) continue;

        await db.setRidePlaces(ride.id,
            startPlace: startPlace, endPlace: endPlace);
        updated++;
      }
      if (updated > 0) onUpdated();
    } finally {
      _running = false;
    }
  }
}

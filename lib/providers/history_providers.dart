import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_service.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';
import '../services/geocode_backfill.dart';

/// All saved rides, newest first. Auto-disposes so re-entering the History
/// screen always refetches — picking up rides saved since the last visit and
/// dropping any deleted in-screen (via `ref.invalidate`).
final rideHistoryProvider = FutureProvider.autoDispose<List<Ride>>((ref) {
  return DatabaseService.instance.getAllRides();
});

/// Fires the best-effort geocode backfill when watched (i.e. when the History
/// screen builds). Re-attempts rides that still lack place names and refreshes
/// the list as they fill in. Invalidated alongside [rideHistoryProvider] on
/// each History-tab entry so a newly-online session gets another pass.
final geocodeBackfillProvider = FutureProvider.autoDispose<void>((ref) async {
  await GeocodeBackfill.instance.run(
    onUpdated: () => ref.invalidate(rideHistoryProvider),
  );
});

/// The recorded track for a single ride (in capture order), keyed by ride id —
/// used to replay the route polyline on the detail screen.
final rideTrackProvider = FutureProvider.autoDispose
    .family<List<TrackPoint>, int>((ref, rideId) {
      return DatabaseService.instance.getTrackPointsForRide(rideId);
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_service.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';

/// All saved rides, newest first. Auto-disposes so re-entering the History
/// screen always refetches — picking up rides saved since the last visit and
/// dropping any deleted in-screen (via `ref.invalidate`).
final rideHistoryProvider = FutureProvider.autoDispose<List<Ride>>((ref) {
  return DatabaseService.instance.getAllRides();
});

/// The recorded track for a single ride (in capture order), keyed by ride id —
/// used to replay the route polyline on the detail screen.
final rideTrackProvider = FutureProvider.autoDispose
    .family<List<TrackPoint>, int>((ref, rideId) {
      return DatabaseService.instance.getTrackPointsForRide(rideId);
    });

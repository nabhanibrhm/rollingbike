import 'package:isar_community/isar.dart';

part 'track_point.g.dart';

/// A single GPS sample captured during a ride.
///
/// Belongs to a [Ride] via [rideId]. Stored as a flat collection (rather than
/// an Isar link) so the background GPS engine can append points with a single
/// cheap `put` and the map can stream them back by [rideId].
@collection
class TrackPoint {
  /// Auto-incrementing primary key assigned by Isar on first `put`.
  Id id = Isar.autoIncrement;

  /// Foreign key to the owning [Ride.id]. Indexed for fast per-ride lookups.
  @Index()
  late int rideId;

  late double latitude;
  late double longitude;

  /// Altitude in meters above the WGS84 ellipsoid. Nullable because not every
  /// fix provides it. Kept now (free from geolocator) to enable future
  /// elevation-gain stats without a schema migration.
  double? altitude;

  /// Instantaneous ground speed, in meters/second, as reported by the fix.
  double speedMps = 0;

  /// Capture time of this fix. Indexed so points replay in chronological order.
  @Index()
  late DateTime timestamp;
}

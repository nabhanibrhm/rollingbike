import 'package:isar_community/isar.dart';

part 'ride.g.dart';

/// A single completed (or in-progress) ride session.
///
/// One [Ride] owns many [TrackPoint]s, linked by [TrackPoint.rideId] == [id].
/// Aggregate stats are denormalised onto the ride so the summary UI never has
/// to scan the full point set.
@collection
class Ride {
  /// Auto-incrementing primary key assigned by Isar on first `put`.
  Id id = Isar.autoIncrement;

  /// When the ride started. Indexed for chronological "ride history" queries.
  @Index()
  late DateTime startTime;

  /// When the ride ended. Null while the ride is still being recorded.
  DateTime? endTime;

  /// Total distance travelled, in meters (Haversine-summed in the GPS engine).
  double totalDistanceMeters = 0;

  /// Elapsed riding time, in whole seconds.
  int durationSeconds = 0;

  /// Mean speed across the ride, in km/h.
  double averageSpeedKmh = 0;

  /// Peak speed reached during the ride, in km/h.
  double maxSpeedKmh = 0;
}

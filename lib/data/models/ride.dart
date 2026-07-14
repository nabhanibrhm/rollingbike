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

  /// User-given trip name, set when the rider saves the ride from the summary
  /// screen. Null until named (an unnamed, freshly-recorded ride). A discarded
  /// ride is deleted outright rather than left unnamed.
  String? name;

  /// Total distance travelled, in meters (Haversine-summed in the GPS engine).
  double totalDistanceMeters = 0;

  /// Total elapsed riding time (start→stop wall clock), in whole seconds.
  /// Strava's "Elapsed time".
  int durationSeconds = 0;

  /// Time spent actually moving (speed above the stop threshold), in whole
  /// seconds. Strava's "Moving time" — excludes stops at lights, breaks, etc.
  int movingSeconds = 0;

  /// Mean speed across the ride, in km/h.
  double averageSpeedKmh = 0;

  /// Peak speed reached during the ride, in km/h.
  double maxSpeedKmh = 0;

  /// Which GPS source recorded this ride ('fused' / 'raw') — a temporary A/B
  /// tag so diagnostics can compare the two pipelines. Null for rides recorded
  /// before the switch existed. Remove once a source is chosen.
  String? gpsSource;

  /// Human-readable place name reverse-geocoded from the ride's first GPS fix
  /// (e.g. "Bandung"). Null when geocoding hasn't run — old rides, or rides
  /// saved while offline (best-effort, online-only lookup).
  String? startPlace;

  /// Human-readable place name reverse-geocoded from the ride's last GPS fix
  /// (e.g. "Lembang"). Null under the same conditions as [startPlace].
  String? endPlace;
}

import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models/ride.dart';
import 'models/track_point.dart';

/// Single owner of the Isar instance for the whole app.
///
/// Call [open] once at startup (before any query). Everything else funnels
/// through the [isar] getter. Kept as a plain singleton — Riverpod wiring lands
/// in Phase 3 when the GPS engine becomes the first real consumer.
class DatabaseService {
  DatabaseService._();

  /// App-wide shared instance.
  static final DatabaseService instance = DatabaseService._();

  Isar? _isar;

  /// The live Isar handle. Throws if [open] hasn't completed yet — fail loud
  /// rather than silently opening a second instance.
  Isar get isar {
    final db = _isar;
    if (db == null || !db.isOpen) {
      throw StateError('DatabaseService.open() must be awaited before use.');
    }
    return db;
  }

  /// Opens (or returns the already-open) Isar instance. Idempotent.
  Future<Isar> open() async {
    final existing = _isar;
    if (existing != null && existing.isOpen) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final db = await Isar.open(
      [RideSchema, TrackPointSchema],
      directory: dir.path,
    );
    _isar = db;
    return db;
  }

  // --- Ride helpers --------------------------------------------------------

  /// Inserts a new ride (or updates an existing one) and returns its id.
  Future<int> saveRide(Ride ride) {
    return isar.writeTxn(() => isar.rides.put(ride));
  }

  /// All rides, newest first.
  Future<List<Ride>> getAllRides() {
    return isar.rides.where().sortByStartTimeDesc().findAll();
  }

  Future<Ride?> getRideById(int id) => isar.rides.get(id);

  /// Deletes a ride and every track point that belongs to it.
  Future<void> deleteRide(int rideId) {
    return isar.writeTxn(() async {
      await isar.trackPoints.filter().rideIdEqualTo(rideId).deleteAll();
      await isar.rides.delete(rideId);
    });
  }

  // --- TrackPoint helpers --------------------------------------------------

  /// Appends a single GPS sample; returns its id.
  Future<int> addTrackPoint(TrackPoint point) {
    return isar.writeTxn(() => isar.trackPoints.put(point));
  }

  /// Appends a batch of GPS samples in one transaction.
  Future<List<int>> addTrackPoints(List<TrackPoint> points) {
    return isar.writeTxn(() => isar.trackPoints.putAll(points));
  }

  /// All points for a ride, in capture order.
  Future<List<TrackPoint>> getTrackPointsForRide(int rideId) {
    return isar.trackPoints
        .filter()
        .rideIdEqualTo(rideId)
        .sortByTimestamp()
        .findAll();
  }

  // --- Maintenance ---------------------------------------------------------

  /// Wipes all rides and track points. Primarily for tests / "reset" actions.
  Future<void> clearAll() {
    return isar.writeTxn(() async {
      await isar.rides.clear();
      await isar.trackPoints.clear();
    });
  }
}

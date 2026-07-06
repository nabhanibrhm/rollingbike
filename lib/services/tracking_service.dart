import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import '../core/gps_kalman.dart';
import '../data/database_service.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';

/// Foreground-service notification id (arbitrary, stable across the app).
const int _kNotificationId = 888;

/// Speed floor (km/h) below which the rider counts as "stopped" — moving time
/// stops accruing. Mirrors Strava/Super Biker auto-pause behaviour; kept a
/// touch high so a motorcycle idling at a light doesn't count as moving.
const double _kMovingSpeedThresholdKmh = 3.0;

/// Below this ground speed (m/s) the GPS course/heading is too noisy to trust,
/// so the Doppler velocity is not fused into the Kalman filter — position
/// updates alone then pull the estimate toward a standstill.
const double _kDopplerMinSpeedMps = 1.0;

/// Discard fixes whose reported accuracy is worse than this (meters) — junk GPS
/// that would otherwise add phantom distance and speed.
const double _kMaxAccuracyMeters = 25.0;

/// A segment implying a speed above this (km/h) is treated as GPS drift rather
/// than real movement, and dropped so it can't inflate distance/max speed.
const double _kMaxPlausibleSpeedKmh = 220.0;

/// After this many consecutive dropped "jumps", assume our reference point has
/// gone stale and re-anchor to the latest fix — prevents getting stuck
/// rejecting every fix if the anchor itself was bad.
const int _kMaxRejectStreak = 3;

/// The telemetry stream ticks at 1 Hz for a smooth on-screen clock, but the
/// foreground notification does not need per-second updates. Re-posting it every
/// second causes needless notification churn / log spam and extra wakeups, so we
/// rate-limit notification refreshes to once per this many seconds (with an
/// immediate refresh whenever the paused state flips, so pause/resume shows
/// promptly).
const int _kNotificationThrottleSeconds = 5;

/// Live snapshot pushed from the background isolate to the UI on each fix (and
/// once more, finalised, when a ride stops).
class LiveTelemetry {
  const LiveTelemetry({
    required this.rideId,
    required this.distanceMeters,
    required this.speedKmh,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.durationSeconds,
    required this.movingSeconds,
    required this.pointCount,
    required this.finished,
    this.paused = false,
    this.lat,
    this.lon,
  });

  final int rideId;
  final double distanceMeters;
  final double speedKmh;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final int durationSeconds;

  /// Time spent moving (speed above the stop threshold), in whole seconds.
  final int movingSeconds;
  final int pointCount;
  final bool finished;

  /// True while the ride is paused (clock/distance frozen).
  final bool paused;
  final double? lat;
  final double? lon;

  /// Values cross an isolate boundary as JSON, so numbers may arrive as int or
  /// double — normalise via `num`.
  factory LiveTelemetry.fromMap(Map<String, dynamic> m) => LiveTelemetry(
        rideId: (m['rideId'] as num).toInt(),
        distanceMeters: (m['distanceMeters'] as num).toDouble(),
        speedKmh: (m['speedKmh'] as num?)?.toDouble() ?? 0,
        maxSpeedKmh: (m['maxSpeedKmh'] as num).toDouble(),
        avgSpeedKmh: (m['avgSpeedKmh'] as num).toDouble(),
        durationSeconds: (m['durationSeconds'] as num).toInt(),
        movingSeconds: (m['movingSeconds'] as num?)?.toInt() ?? 0,
        pointCount: (m['pointCount'] as num).toInt(),
        finished: (m['finished'] as bool?) ?? false,
        paused: (m['paused'] as bool?) ?? false,
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
      );
}

/// UI-side handle to the background tracking service. Configure once at
/// startup, then start/stop rides and listen to [telemetry].
class TrackingService {
  TrackingService._();
  static final TrackingService instance = TrackingService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Registers the background service. Call once in `main()` before use.
  Future<void> configure() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        initialNotificationTitle: 'RollingBike',
        initialNotificationContent: 'Preparing to record…',
        foregroundServiceTypes: const [AndroidForegroundType.location],
        // notificationChannelId intentionally omitted: the plugin then creates
        // its own low-importance FOREGROUND_DEFAULT channel, so we avoid pulling
        // in flutter_local_notifications just to declare one.
        foregroundServiceNotificationId: _kNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// True while a ride is being recorded.
  Future<bool> isTracking() => _service.isRunning();

  /// Starts the foreground service, which begins a new ride immediately.
  Future<void> startRide() async {
    await _service.startService();
  }

  /// Asks the background isolate to finalise the ride and stop the service.
  void stopRide() => _service.invoke('stop');

  /// Pauses recording (freezes the clock/distance; stops GPS).
  void pauseRide() => _service.invoke('pause');

  /// Resumes a paused recording.
  void resumeRide() => _service.invoke('resume');

  /// Per-fix live telemetry while recording.
  Stream<LiveTelemetry> get telemetry => _service
      .on('telemetry')
      .where((e) => e != null)
      .map((e) => LiveTelemetry.fromMap(e!));

  /// Fires once when a ride is finalised (final aggregates).
  Stream<LiveTelemetry> get onStopped => _service
      .on('stopped')
      .where((e) => e != null)
      .map((e) => LiveTelemetry.fromMap(e!));
}

/// iOS background fetch handler — Android is the MVP target, so this is a stub
/// that simply keeps the isolate alive.
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async => true;

/// Background-isolate entrypoint. Runs the whole GPS recording loop:
/// creates a [Ride], streams positions, accumulates distance + max speed,
/// persists each [TrackPoint], live-updates the ride aggregates, and pushes
/// telemetry to the UI. Finalises and stops on a 'stop' event.
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // The background isolate has its own plugin registry — must initialise it
  // before touching geolocator / path_provider / isar.
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  final db = DatabaseService.instance;
  await db.open();

  final startedAt = DateTime.now();
  final ride = Ride()..startTime = startedAt;
  final rideId = await db.saveRide(ride);

  var totalDistanceMeters = 0.0;
  var maxSpeedKmh = 0.0;
  var currentSpeedKmh = 0.0;
  var movingSeconds = 0;
  var pointCount = 0;
  var rejectedStreak = 0;

  // Kalman filter fusing position + Doppler velocity into a smoothed track and
  // speed. `smoothLat/Lon` is its latest output — it drives the map, distance,
  // and telemetry, and is kept distinct from the raw jump-gate anchor below.
  final kalman = GpsKalmanFilter();
  double? smoothLat;
  double? smoothLon;

  // Pause state. A "standard" pause: while paused the position stream is stopped
  // and paused wall-clock time is excluded from elapsed/avg (and moving time).
  var paused = false;
  DateTime? pauseStartedAt;
  var totalPaused = Duration.zero;
  double? lastLat;
  double? lastLon;
  var lastFixAt = startedAt;

  // Notification is refreshed on a slower cadence than the 1 Hz tick to avoid
  // per-second notification churn. Seeded at the threshold so the first tick
  // posts immediately; lastNotifiedPaused forces a refresh on pause/resume.
  var ticksSinceNotify = _kNotificationThrottleSeconds;
  bool? lastNotifiedPaused;

  StreamSubscription<Position>? positionSub;
  Timer? ticker;

  // Wall-clock since start, minus all paused time (completed + any in-progress
  // pause) — so the ride clock freezes while paused.
  int elapsedSeconds() {
    var pausedTotal = totalPaused;
    if (paused && pauseStartedAt != null) {
      pausedTotal += DateTime.now().difference(pauseStartedAt!);
    }
    final elapsed = DateTime.now().difference(startedAt) - pausedTotal;
    return elapsed.isNegative ? 0 : elapsed.inSeconds;
  }

  double avgSpeedKmh() {
    final d = elapsedSeconds();
    return d > 0 ? (totalDistanceMeters / d) * 3.6 : 0.0;
  }

  void emitTelemetry() {
    service.invoke('telemetry', {
      'rideId': rideId,
      'distanceMeters': totalDistanceMeters,
      'speedKmh': currentSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'avgSpeedKmh': avgSpeedKmh(),
      'durationSeconds': elapsedSeconds(),
      'movingSeconds': movingSeconds,
      'pointCount': pointCount,
      'finished': false,
      'paused': paused,
      'lat': smoothLat,
      'lon': smoothLon,
    });
  }

  Future<void> finalizeAndStop() async {
    ticker?.cancel();
    await positionSub?.cancel();
    final endedAt = DateTime.now();
    // Exclude paused time from the recorded duration (and thus the average).
    final durationSeconds = elapsedSeconds();
    final finalAvg =
        durationSeconds > 0 ? (totalDistanceMeters / durationSeconds) * 3.6 : 0.0;

    ride
      ..endTime = endedAt
      ..totalDistanceMeters = totalDistanceMeters
      ..durationSeconds = durationSeconds
      ..movingSeconds = movingSeconds
      ..averageSpeedKmh = finalAvg
      ..maxSpeedKmh = maxSpeedKmh;
    await db.saveRide(ride);

    service.invoke('stopped', {
      'rideId': rideId,
      'distanceMeters': totalDistanceMeters,
      'speedKmh': 0.0,
      'maxSpeedKmh': maxSpeedKmh,
      'avgSpeedKmh': finalAvg,
      'durationSeconds': durationSeconds,
      'movingSeconds': movingSeconds,
      'pointCount': pointCount,
      'finished': true,
    });

    await service.stopSelf();
  }

  service.on('stop').listen((_) => finalizeAndStop());

  // 1 Hz heartbeat: keeps the duration/avg (and the notification) advancing even
  // while stationary — GPS fixes are gated by the distance filter, so without
  // this the on-screen timer would freeze between fixes.
  ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
    // Decay the shown speed to zero if no fresh fix has arrived (rider stopped).
    if (DateTime.now().difference(lastFixAt).inSeconds >= 3) {
      currentSpeedKmh = 0.0;
    }
    // Accrue moving time once per tick while above the stop threshold — but not
    // while paused (paused time is excluded from every stat).
    if (!paused && currentSpeedKmh > _kMovingSpeedThresholdKmh) {
      movingSeconds++;
    }
    emitTelemetry();
    // Throttle the notification: refresh every _kNotificationThrottleSeconds, or
    // right away when the paused state changes (so the title flips promptly).
    if (service is AndroidServiceInstance) {
      ticksSinceNotify++;
      final pausedChanged = lastNotifiedPaused != paused;
      if (ticksSinceNotify >= _kNotificationThrottleSeconds || pausedChanged) {
        ticksSinceNotify = 0;
        lastNotifiedPaused = paused;
        await service.setForegroundNotificationInfo(
          title: paused ? 'RollingBike — paused' : 'RollingBike — recording',
          content: '${(totalDistanceMeters / 1000).toStringAsFixed(2)} km · '
              '${_formatDuration(elapsedSeconds())}',
        );
      }
    }
  });

  final settings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 5, // meters; suppress jitter while stationary
  );

  // Wrapped in a function so resume can restart it after pause cancels it.
  void startPositionStream() {
    positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) async {
      // Accuracy gate: ignore junk fixes outright, keeping the last good anchor.
      if (pos.accuracy.isFinite && pos.accuracy > _kMaxAccuracyMeters) return;

      final now = DateTime.now();

      // Raw displacement speed since the last accepted fix — used only by the
      // jump gate below (distance/speed themselves come from the filter).
      double? displacementSpeedKmh;
      if (lastLat != null && lastLon != null) {
        final segMeters =
            haversineMeters(lastLat!, lastLon!, pos.latitude, pos.longitude);
        final dtSeconds = now.difference(lastFixAt).inMilliseconds / 1000.0;
        if (dtSeconds > 0) displacementSpeedKmh = (segMeters / dtSeconds) * 3.6;
      }

      // Impossible-jump gate: a segment implying a wild speed is GPS drift, not
      // real movement — drop it. But if we drop too many in a row the anchor
      // itself is probably stale, so re-anchor to this fix (resetting the filter
      // so the gap isn't counted) and carry on.
      if (displacementSpeedKmh != null &&
          displacementSpeedKmh > _kMaxPlausibleSpeedKmh) {
        rejectedStreak++;
        if (rejectedStreak <= _kMaxRejectStreak) return;
        lastLat = pos.latitude;
        lastLon = pos.longitude;
        lastFixAt = now;
        kalman.reset();
        smoothLat = null;
        smoothLon = null;
        rejectedStreak = 0;
        return;
      }
      rejectedStreak = 0;

      // Accepted fix: advance the raw anchor.
      lastLat = pos.latitude;
      lastLon = pos.longitude;
      lastFixAt = now;

      // Feed the Kalman filter. Fuse the Doppler velocity only when moving fast
      // enough for the reported heading to be meaningful.
      final useDoppler = pos.speed.isFinite &&
          pos.speed > _kDopplerMinSpeedMps &&
          pos.heading.isFinite &&
          pos.heading >= 0;
      kalman.update(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracyMeters: pos.accuracy,
        timeMs: now.millisecondsSinceEpoch.toDouble(),
        speed: useDoppler ? pos.speed : null,
        speedAccuracy: pos.speedAccuracy,
        headingDegrees: useDoppler ? pos.heading : null,
      );

      // Accumulate distance along the *smoothed* track — GPS noise while
      // (near-)stationary can't inflate it the way raw fixes would.
      final (sLat, sLon) = kalman.position;
      if (smoothLat != null && smoothLon != null) {
        totalDistanceMeters +=
            haversineMeters(smoothLat!, smoothLon!, sLat, sLon);
      }
      smoothLat = sLat;
      smoothLon = sLon;

      // Speed comes straight from the filter's velocity estimate — no EMA.
      currentSpeedKmh = kalman.speedKmh;
      if (currentSpeedKmh > maxSpeedKmh) maxSpeedKmh = currentSpeedKmh;

      // Persist the raw fix as the ground-truth track point.
      await db.addTrackPoint(
        TrackPoint()
          ..rideId = rideId
          ..latitude = pos.latitude
          ..longitude = pos.longitude
          ..altitude = pos.altitude
          ..speedMps = pos.speed
          ..timestamp = pos.timestamp,
      );
      pointCount++;

      // Persist the running aggregates so a crash mid-ride keeps a sane summary.
      ride
        ..totalDistanceMeters = totalDistanceMeters
        ..durationSeconds = elapsedSeconds()
        ..movingSeconds = movingSeconds
        ..averageSpeedKmh = avgSpeedKmh()
        ..maxSpeedKmh = maxSpeedKmh;
      await db.saveRide(ride);

      emitTelemetry();
    });
  }

  startPositionStream();

  // Pause: freeze the clock, stop GPS, and drop the anchor so the distance
  // covered while paused is not counted when tracking resumes.
  service.on('pause').listen((_) {
    if (paused) return;
    paused = true;
    pauseStartedAt = DateTime.now();
    currentSpeedKmh = 0.0;
    positionSub?.cancel();
    positionSub = null;
    lastLat = null;
    lastLon = null;
    // Drop the filter/anchor so distance covered while paused isn't counted and
    // the estimate re-seeds cleanly from the first fix after resume.
    kalman.reset();
    smoothLat = null;
    smoothLon = null;
    emitTelemetry();
  });

  // Resume: bank the paused duration (so it stays excluded) and restart GPS.
  service.on('resume').listen((_) {
    if (!paused) return;
    if (pauseStartedAt != null) {
      totalPaused += DateTime.now().difference(pauseStartedAt!);
      pauseStartedAt = null;
    }
    paused = false;
    lastFixAt = DateTime.now();
    startPositionStream();
    emitTelemetry();
  });
}

/// Formats seconds as `m:ss` (or `h:mm:ss` past an hour) for the notification.
String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

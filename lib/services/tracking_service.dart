import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_background_service/flutter_background_service.dart';

import '../core/geo.dart';
import '../core/gps_kalman.dart';
import '../data/database_service.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';
import 'location_source.dart';
import 'settings_service.dart';

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

/// Windowed-standstill guard. If the rider's net ground displacement over the
/// last [_kStationaryWindowSeconds] implies a speed below [_kStationarySpeedKmh],
/// the shown speed is snapped to 0 — killing the phantom "creep" both GPS
/// pipelines report at a standstill (fused worst, up to ~4 km/h; raw ~1.4) so
/// the gauge holds a rock-steady 0 at lights/stops. Source-independent: it works
/// off positions, not the reported speed, so it hardens whichever pipeline runs.
const double _kStationaryWindowSeconds = 5.0;
const double _kStationarySpeedKmh = 3.0;

/// Blackout threshold (seconds). If no usable fix arrives for this long while
/// recording, GPS is treated as lost (tunnel / train / metal enclosure): the
/// ride clock freezes (signal-loss auto-pause) and the next returning fix is
/// re-anchored rather than bridged into distance — otherwise a far-away first
/// fix after the dead zone adds a phantom straight-line segment and the paused
/// wall-clock inflates the duration. Must sit well above the normal fix cadence
/// (raw ~1.4 s, fused ~1 s) and above [_kSpeedStaleSeconds] so ordinary gaps
/// between fixes don't trip it.
const int _kSignalLossSeconds = 12;

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

/// Grace period (seconds) since the last accepted fix before the shown speed
/// starts easing toward zero. Real fixes land roughly 5-6s apart even while
/// riding normally (per on-device track-point diagnostics), so this must
/// clear that with margin or the speed readout falsely flashes to zero
/// mid-ride.
const double _kSpeedStaleSeconds = 8.0;

/// Once [_kSpeedStaleSeconds] is exceeded without a fresh fix, the shown speed
/// eases linearly to zero over this many additional seconds instead of
/// cutting instantly, so a genuine stop doesn't read as a display glitch.
const double _kSpeedDecaySeconds = 4.0;

/// The telemetry stream ticks at 1 Hz for a smooth on-screen clock, but the
/// foreground notification does not need per-second updates. Re-posting it every
/// second causes needless notification churn / log spam and extra wakeups, so we
/// rate-limit notification refreshes to once per this many seconds (with an
/// immediate refresh whenever the paused state flips, so pause/resume shows
/// promptly).
const int _kNotificationThrottleSeconds = 5;

/// Cold-start acquisition: wait this long for the first usable GPS fix after the
/// rider taps START before giving up and cancelling (no orphan ride is written).
const int _kAcquireTimeoutSeconds = 30;

/// Length (seconds) of the "3… 2… 1…" countdown shown after GPS is acquired,
/// before the ride clock actually starts.
const int _kCountdownSeconds = 3;

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
    this.hasFix = false,
    this.paused = false,
    this.lat,
    this.lon,
    this.phase = 'recording',
    this.countdown = 0,
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

  /// False until the first GPS fix of the ride is accepted — lets the UI show
  /// an "acquiring GPS" state instead of a misleading 0 km/h at cold start.
  final bool hasFix;

  /// True while the ride is paused (clock/distance frozen).
  final bool paused;
  final double? lat;
  final double? lon;

  /// Ride lifecycle phase: 'acquiring' (waiting for the first usable fix),
  /// 'countdown' (GPS locked, 3-2-1 before the clock starts), or 'recording'.
  final String phase;

  /// Remaining countdown seconds while [phase] == 'countdown' (0 otherwise).
  final int countdown;

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
        hasFix: (m['hasFix'] as bool?) ?? false,
        paused: (m['paused'] as bool?) ?? false,
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        phase: (m['phase'] as String?) ?? 'recording',
        countdown: (m['countdown'] as num?)?.toInt() ?? 0,
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

  /// Fires when acquisition is aborted before the ride ever started (Cancel or
  /// the acquire timeout). Emits an optional human-readable reason (null when the
  /// rider cancelled deliberately). No ride is written in this case.
  Stream<String?> get onCancelled => _service
      .on('cancelled')
      .map((e) => e?['reason'] as String?);
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

  // Which GPS pipeline to record with — chosen in the UI before start and
  // persisted so this isolate can read it. Temporary A/B switch.
  final sourceKind = await SettingsService.instance.loadGpsSource();
  final locationSource = LocationSource.forKind(sourceKind);

  // Ride lifecycle: 'acquiring' (waiting for the first usable fix) → 'countdown'
  // (GPS locked, 3-2-1) → 'recording'. The ride clock and the Ride row don't
  // exist until recording begins, so the GPS acquisition delay is never counted
  // as ride time and a cancelled acquisition leaves no orphan ride behind.
  var phase = 'acquiring';
  var countdown = 0;

  // Stamped only when recording actually begins (end of countdown); null while
  // acquiring / counting down so elapsedSeconds() reads zero.
  DateTime? startedAt;
  // Created lazily at that same moment, so a cancelled acquisition writes nothing.
  Ride? ride;
  var rideId = 0;

  var totalDistanceMeters = 0.0;
  var maxSpeedKmh = 0.0;
  var currentSpeedKmh = 0.0;
  // Speed at the moment of the last accepted fix — the frozen baseline the
  // ticker eases down from on a gap, instead of recomputing off a value it
  // may itself already be decaying.
  var speedAtLastFix = 0.0;
  // Rolling window of recent smoothed fixes (time, lat, lon) for the windowed
  // standstill guard — see _kStationaryWindowSeconds.
  final recentFixes = <(DateTime, double, double)>[];
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
  // Set while GPS is blacked out mid-ride (signal-loss auto-pause). While
  // non-null the ride clock is frozen (see elapsedSeconds); its interval is
  // banked into totalPaused and the marker cleared when a fix returns.
  DateTime? signalLostAt;
  double? lastLat;
  double? lastLon;
  var lastFixAt = DateTime.now();

  // Notification is refreshed on a slower cadence than the 1 Hz tick to avoid
  // per-second notification churn. Seeded at the threshold so the first tick
  // posts immediately; lastNotifiedPaused forces a refresh on pause/resume.
  var ticksSinceNotify = _kNotificationThrottleSeconds;
  bool? lastNotifiedPaused;
  String? lastNotifiedPhase;

  StreamSubscription<GpsFix>? positionSub;
  Timer? ticker;
  Timer? countdownTimer;
  Timer? acquireTimeout;

  // Wall-clock since start, minus all paused time (completed + any in-progress
  // pause) — so the ride clock freezes while paused.
  int elapsedSeconds() {
    if (startedAt == null) return 0; // still acquiring / counting down
    var pausedTotal = totalPaused;
    if (paused && pauseStartedAt != null) {
      pausedTotal += DateTime.now().difference(pauseStartedAt!);
    }
    // A signal blackout in progress freezes the clock the same way a pause does.
    if (signalLostAt != null) {
      pausedTotal += DateTime.now().difference(signalLostAt!);
    }
    final elapsed = DateTime.now().difference(startedAt!) - pausedTotal;
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
      // False until the first fix of this ride is accepted, so the UI can show
      // an "acquiring GPS" state instead of a misleading 0 km/h at cold start.
      'hasFix': pointCount > 0,
      'finished': false,
      'paused': paused,
      'lat': smoothLat,
      'lon': smoothLon,
      'phase': phase,
      'countdown': countdown,
    });
  }

  Future<void> finalizeAndStop() async {
    ticker?.cancel();
    countdownTimer?.cancel();
    acquireTimeout?.cancel();
    await positionSub?.cancel();
    final r = ride;
    if (r == null) {
      // Defensive: stop is only wired to finalise while recording, but never
      // crash if it somehow fires before a ride exists.
      await service.stopSelf();
      return;
    }
    final endedAt = DateTime.now();
    // Exclude paused time from the recorded duration (and thus the average).
    final durationSeconds = elapsedSeconds();
    final finalAvg =
        durationSeconds > 0 ? (totalDistanceMeters / durationSeconds) * 3.6 : 0.0;

    r
      ..endTime = endedAt
      ..totalDistanceMeters = totalDistanceMeters
      ..durationSeconds = durationSeconds
      ..movingSeconds = movingSeconds
      ..averageSpeedKmh = finalAvg
      ..maxSpeedKmh = maxSpeedKmh;
    await db.saveRide(r);

    service.invoke('stopped', {
      'rideId': rideId,
      'distanceMeters': totalDistanceMeters,
      'speedKmh': 0.0,
      'maxSpeedKmh': maxSpeedKmh,
      'avgSpeedKmh': finalAvg,
      'durationSeconds': durationSeconds,
      'movingSeconds': movingSeconds,
      'pointCount': pointCount,
      'hasFix': true,
      'finished': true,
    });

    await service.stopSelf();
  }

  // Abort before recording ever started (Cancel button or acquire timeout):
  // tear everything down and tell the UI to return to idle. No Ride was created,
  // so there is nothing to delete.
  Future<void> cancelAcquire({String? reason}) async {
    ticker?.cancel();
    countdownTimer?.cancel();
    acquireTimeout?.cancel();
    await positionSub?.cancel();
    service.invoke(
        'cancelled', reason == null ? <String, dynamic>{} : {'reason': reason});
    await service.stopSelf();
  }

  // Countdown finished → the ride truly begins here. Stamp the clock and create
  // the Ride only now, and reset every accumulator + the filter/anchors so that
  // nothing sampled during acquisition or countdown leaks into the ride.
  Future<void> beginRecording() async {
    final now = DateTime.now();
    totalDistanceMeters = 0;
    maxSpeedKmh = 0;
    currentSpeedKmh = 0;
    speedAtLastFix = 0;
    recentFixes.clear();
    movingSeconds = 0;
    pointCount = 0;
    rejectedStreak = 0;
    kalman.reset();
    smoothLat = null;
    smoothLon = null;
    lastLat = null;
    lastLon = null;
    lastFixAt = now;
    signalLostAt = null;
    startedAt = now;
    ride = Ride()
      ..startTime = now
      ..gpsSource = sourceKind.tag;
    rideId = await db.saveRide(ride!);
    // Flip to recording only after the ride row exists, so an in-flight fix
    // can't try to persist against rideId 0.
    phase = 'recording';
    countdown = 0;
    emitTelemetry();
  }

  // First usable fix arrived → start the 3-2-1 countdown, then record.
  void beginCountdown() {
    if (phase != 'acquiring') return;
    acquireTimeout?.cancel();
    phase = 'countdown';
    countdown = _kCountdownSeconds;
    emitTelemetry();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      countdown--;
      if (countdown <= 0) {
        countdownTimer?.cancel();
        beginRecording();
      } else {
        emitTelemetry();
      }
    });
  }

  // STOP means "finalise the ride" while recording, but "cancel acquisition"
  // during the acquiring/countdown phases (no ride to save).
  service.on('stop').listen((_) {
    if (phase == 'recording') {
      finalizeAndStop();
    } else {
      cancelAcquire();
    }
  });

  // 1 Hz heartbeat: keeps the duration/avg (and the notification) advancing even
  // while stationary — GPS fixes are gated by the distance filter, so without
  // this the on-screen timer would freeze between fixes.
  ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
    // The clock, speed decay, and moving-time only advance while recording —
    // during acquiring/countdown the tick just refreshes the UI/notification.
    if (phase == 'recording' && !paused) {
      final sinceLastFixS =
          DateTime.now().difference(lastFixAt).inMilliseconds / 1000.0;
      // Signal-loss auto-pause: once fixes stop arriving for a full blackout
      // window (tunnel / train dead-zone), freeze the ride clock by marking
      // signalLostAt — elapsedSeconds() then excludes the ongoing gap, so the
      // blackout no longer inflates duration/avg. Banked and cleared when a fix
      // returns (see the re-anchor in the position stream).
      if (sinceLastFixS >= _kSignalLossSeconds && signalLostAt == null) {
        signalLostAt = DateTime.now();
      }
      // Ease the shown speed to zero once fixes stop arriving for a while
      // (rider stopped — fixes largely cease at a standstill because of the
      // position stream's distance filter).
      if (sinceLastFixS >= _kSpeedStaleSeconds) {
        final decayFraction =
            ((sinceLastFixS - _kSpeedStaleSeconds) / _kSpeedDecaySeconds)
                .clamp(0.0, 1.0);
        currentSpeedKmh = speedAtLastFix * (1 - decayFraction);
      }
      // Accrue moving time once per tick while above the stop threshold — but
      // not during a blackout (no data = not known to be moving).
      if (signalLostAt == null && currentSpeedKmh > _kMovingSpeedThresholdKmh) {
        movingSeconds++;
      }
    }
    emitTelemetry();
    // Throttle the notification: refresh every _kNotificationThrottleSeconds, or
    // right away when the paused state or lifecycle phase changes.
    if (service is AndroidServiceInstance) {
      ticksSinceNotify++;
      final pausedChanged = lastNotifiedPaused != paused;
      final phaseChanged = lastNotifiedPhase != phase;
      if (ticksSinceNotify >= _kNotificationThrottleSeconds ||
          pausedChanged ||
          phaseChanged) {
        ticksSinceNotify = 0;
        lastNotifiedPaused = paused;
        lastNotifiedPhase = phase;
        final String title;
        final String content;
        if (phase == 'acquiring') {
          title = 'RollingBike — acquiring GPS…';
          content = 'Waiting for a GPS signal';
        } else if (phase == 'countdown') {
          title = 'RollingBike — starting…';
          content = 'Ride begins in $countdown';
        } else if (signalLostAt != null) {
          title = 'RollingBike — GPS signal lost';
          content = 'Clock paused · '
              '${(totalDistanceMeters / 1000).toStringAsFixed(2)} km · '
              '${_formatDuration(elapsedSeconds())}';
        } else {
          title = paused ? 'RollingBike — paused' : 'RollingBike — recording';
          content = '${(totalDistanceMeters / 1000).toStringAsFixed(2)} km · '
              '${_formatDuration(elapsedSeconds())}';
        }
        await service.setForegroundNotificationInfo(
            title: title, content: content);
      }
    }
  });

  // Wrapped in a function so resume can restart it after pause cancels it.
  // The fix source (fused / raw GPS) was chosen above from the persisted A/B
  // setting; the engine below is identical regardless of which one feeds it.
  void startPositionStream() {
    positionSub = locationSource.positions().listen((fix) async {
      // Accuracy gate: ignore junk fixes outright, keeping the last good anchor.
      if (fix.accuracyMeters.isFinite &&
          fix.accuracyMeters > _kMaxAccuracyMeters) {
        return;
      }

      // Before the ride clock starts, fixes are used only to (a) detect GPS lock
      // so the countdown can begin and (b) show the rider's position — nothing is
      // accumulated or persisted until recording begins.
      if (phase == 'acquiring') {
        smoothLat = fix.latitude;
        smoothLon = fix.longitude;
        beginCountdown();
        emitTelemetry();
        return;
      }
      if (phase == 'countdown') {
        smoothLat = fix.latitude;
        smoothLon = fix.longitude;
        return;
      }

      final now = DateTime.now();
      // Seconds since the last accepted fix. A gap beyond _kSignalLossSeconds
      // means GPS blacked out (tunnel/train) — the ticker froze the clock, and
      // this fix's segment must not be bridged into distance (see the re-anchor
      // below).
      final gapSeconds = now.difference(lastFixAt).inMilliseconds / 1000.0;
      final longGap = pointCount > 0 && gapSeconds >= _kSignalLossSeconds;

      // Raw displacement speed since the last accepted fix — used only by the
      // jump gate below (distance/speed themselves come from the filter).
      double? displacementSpeedKmh;
      if (lastLat != null && lastLon != null && gapSeconds > 0) {
        final segMeters =
            haversineMeters(lastLat!, lastLon!, fix.latitude, fix.longitude);
        displacementSpeedKmh = (segMeters / gapSeconds) * 3.6;
      }

      // Impossible-jump gate: a segment implying a wild speed is GPS drift, not
      // real movement — drop it. But if we drop too many in a row the anchor
      // itself is probably stale, so re-anchor to this fix (resetting the filter
      // so the gap isn't counted) and carry on.
      if (displacementSpeedKmh != null &&
          displacementSpeedKmh > _kMaxPlausibleSpeedKmh) {
        rejectedStreak++;
        if (rejectedStreak <= _kMaxRejectStreak) return;
        lastLat = fix.latitude;
        lastLon = fix.longitude;
        lastFixAt = now;
        kalman.reset();
        smoothLat = null;
        smoothLon = null;
        recentFixes.clear();
        rejectedStreak = 0;
        // A blackout that ended with a far jump — bank the frozen time so it
        // stays out of duration/avg.
        if (signalLostAt != null) {
          totalPaused += now.difference(signalLostAt!);
          signalLostAt = null;
        }
        return;
      }
      rejectedStreak = 0;

      // Accepted fix: advance the raw anchor.
      lastLat = fix.latitude;
      lastLon = fix.longitude;
      lastFixAt = now;

      // Long-gap re-anchor: GPS was out (blackout) and a fix is back. Reseed the
      // filter from here rather than interpolating across the dead zone, drop the
      // stale standstill window, and bank the frozen blackout time. Nulling the
      // smoothed anchor makes the distance step below skip this segment — a
      // straight line across a tunnel is phantom, not ridden.
      if (longGap) {
        kalman.reset();
        smoothLat = null;
        smoothLon = null;
        recentFixes.clear();
        if (signalLostAt != null) {
          totalPaused += now.difference(signalLostAt!);
          signalLostAt = null;
        }
      }

      // Feed the Kalman filter. Fuse the Doppler velocity only when moving fast
      // enough for the reported heading to be meaningful.
      final useDoppler = fix.speedMps.isFinite &&
          fix.speedMps > _kDopplerMinSpeedMps &&
          fix.headingDegrees.isFinite &&
          fix.headingDegrees >= 0;
      kalman.update(
        lat: fix.latitude,
        lon: fix.longitude,
        accuracyMeters: fix.accuracyMeters,
        timeMs: now.millisecondsSinceEpoch.toDouble(),
        speed: useDoppler ? fix.speedMps : null,
        speedAccuracy: fix.speedAccuracyMps,
        headingDegrees: useDoppler ? fix.headingDegrees : null,
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

      // Windowed standstill snap: if net ground displacement over the recent
      // window is negligible, the reported speed is GPS "creep", not real
      // motion — force it to 0 so the gauge holds steady at stops (both
      // pipelines creep; fused worst). Distance already can't grow while
      // stationary (it accrues along the smoothed track), so this only corrects
      // the displayed/peak speed and keeps moving-time from ticking at a stop.
      recentFixes.add((now, sLat, sLon));
      while (recentFixes.length > 1 &&
          now.difference(recentFixes.first.$1).inMilliseconds / 1000.0 >
              _kStationaryWindowSeconds) {
        recentFixes.removeAt(0);
      }
      if (recentFixes.length >= 2) {
        final oldest = recentFixes.first;
        final spanS = now.difference(oldest.$1).inMilliseconds / 1000.0;
        if (spanS >= _kStationaryWindowSeconds * 0.6) {
          final netM = haversineMeters(oldest.$2, oldest.$3, sLat, sLon);
          if ((netM / spanS) * 3.6 < _kStationarySpeedKmh) currentSpeedKmh = 0.0;
        }
      }

      speedAtLastFix = currentSpeedKmh;
      if (currentSpeedKmh > maxSpeedKmh) maxSpeedKmh = currentSpeedKmh;

      // Persist the raw fix as the ground-truth track point.
      await db.addTrackPoint(
        TrackPoint()
          ..rideId = rideId
          ..latitude = fix.latitude
          ..longitude = fix.longitude
          ..altitude = fix.altitude
          ..speedMps = fix.speedMps
          ..timestamp = fix.timestamp,
      );
      pointCount++;

      // Persist the running aggregates so a crash mid-ride keeps a sane summary.
      // Only reached while recording, so the ride row exists.
      ride!
        ..totalDistanceMeters = totalDistanceMeters
        ..durationSeconds = elapsedSeconds()
        ..movingSeconds = movingSeconds
        ..averageSpeedKmh = avgSpeedKmh()
        ..maxSpeedKmh = maxSpeedKmh;
      await db.saveRide(ride!);

      emitTelemetry();
    });
  }

  startPositionStream();

  // If GPS never locks, don't hang forever in "acquiring" — cancel cleanly and
  // let the UI surface the reason.
  acquireTimeout = Timer(const Duration(seconds: _kAcquireTimeoutSeconds), () {
    if (phase == 'acquiring') {
      cancelAcquire(
          reason:
              "Couldn't get a GPS signal. Move to an open area and try again.");
    }
  });

  // Pause: freeze the clock, stop GPS, and drop the anchor so the distance
  // covered while paused is not counted when tracking resumes.
  service.on('pause').listen((_) {
    if (phase != 'recording' || paused) return;
    // If a blackout was in progress, bank its frozen time before the manual
    // pause takes over, so the two freezes can't double-count.
    if (signalLostAt != null) {
      totalPaused += DateTime.now().difference(signalLostAt!);
      signalLostAt = null;
    }
    paused = true;
    pauseStartedAt = DateTime.now();
    currentSpeedKmh = 0.0;
    recentFixes.clear();
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

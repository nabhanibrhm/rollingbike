import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import '../data/database_service.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';

/// Foreground-service notification id (arbitrary, stable across the app).
const int _kNotificationId = 888;

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
    required this.pointCount,
    required this.finished,
    this.lat,
    this.lon,
  });

  final int rideId;
  final double distanceMeters;
  final double speedKmh;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final int durationSeconds;
  final int pointCount;
  final bool finished;
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
        pointCount: (m['pointCount'] as num).toInt(),
        finished: (m['finished'] as bool?) ?? false,
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
  var pointCount = 0;
  double? lastLat;
  double? lastLon;

  StreamSubscription<Position>? positionSub;

  Future<void> finalizeAndStop() async {
    await positionSub?.cancel();
    final endedAt = DateTime.now();
    final durationSeconds = endedAt.difference(startedAt).inSeconds;
    final avgSpeedKmh =
        durationSeconds > 0 ? (totalDistanceMeters / durationSeconds) * 3.6 : 0.0;

    ride
      ..endTime = endedAt
      ..totalDistanceMeters = totalDistanceMeters
      ..durationSeconds = durationSeconds
      ..averageSpeedKmh = avgSpeedKmh
      ..maxSpeedKmh = maxSpeedKmh;
    await db.saveRide(ride);

    service.invoke('stopped', {
      'rideId': rideId,
      'distanceMeters': totalDistanceMeters,
      'speedKmh': 0.0,
      'maxSpeedKmh': maxSpeedKmh,
      'avgSpeedKmh': avgSpeedKmh,
      'durationSeconds': durationSeconds,
      'pointCount': pointCount,
      'finished': true,
    });

    await service.stopSelf();
  }

  service.on('stop').listen((_) => finalizeAndStop());

  final settings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 5, // meters; suppress jitter while stationary
  );

  positionSub =
      Geolocator.getPositionStream(locationSettings: settings).listen((pos) async {
    if (lastLat != null && lastLon != null) {
      totalDistanceMeters +=
          haversineMeters(lastLat!, lastLon!, pos.latitude, pos.longitude);
    }
    lastLat = pos.latitude;
    lastLon = pos.longitude;

    final rawSpeed = (pos.speed.isFinite && pos.speed > 0) ? pos.speed : 0.0;
    final speedKmh = rawSpeed * 3.6;
    if (speedKmh > maxSpeedKmh) maxSpeedKmh = speedKmh;

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

    final durationSeconds = DateTime.now().difference(startedAt).inSeconds;
    final avgSpeedKmh =
        durationSeconds > 0 ? (totalDistanceMeters / durationSeconds) * 3.6 : 0.0;

    ride
      ..totalDistanceMeters = totalDistanceMeters
      ..durationSeconds = durationSeconds
      ..averageSpeedKmh = avgSpeedKmh
      ..maxSpeedKmh = maxSpeedKmh;
    await db.saveRide(ride);

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'RollingBike — recording',
        content: '${(totalDistanceMeters / 1000).toStringAsFixed(2)} km · '
            '${speedKmh.toStringAsFixed(0)} km/h',
      );
    }

    service.invoke('telemetry', {
      'rideId': rideId,
      'distanceMeters': totalDistanceMeters,
      'speedKmh': speedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'avgSpeedKmh': avgSpeedKmh,
      'durationSeconds': durationSeconds,
      'pointCount': pointCount,
      'finished': false,
      'lat': pos.latitude,
      'lon': pos.longitude,
    });
  });
}

import 'package:geolocator/geolocator.dart';

/// A single normalised GPS fix, decoupling the tracking engine from geolocator's
/// [Position] so the fix source can be swapped (or mocked in tests) without
/// touching the engine.
class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedMps,
    required this.speedAccuracyMps,
    required this.headingDegrees,
    required this.altitude,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;

  /// Estimated horizontal accuracy radius, in meters.
  final double accuracyMeters;

  /// Ground speed, in m/s (Doppler when the platform provides it).
  final double speedMps;

  /// Reported confidence in [speedMps], in m/s (0 / non-finite if unknown).
  final double speedAccuracyMps;

  /// Course over ground, in degrees.
  final double headingDegrees;
  final double altitude;
  final DateTime timestamp;

  factory GpsFix.fromPosition(Position p) => GpsFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        speedMps: p.speed,
        speedAccuracyMps: p.speedAccuracy,
        headingDegrees: p.heading,
        altitude: p.altitude,
        timestamp: p.timestamp,
      );
}

/// A stream of GPS fixes; the tracking engine consumes only this interface.
///
/// The app records with raw GNSS — the pipeline that won the fused-vs-raw
/// comparison (honest speed peaks, no synthesised fused positions). See the
/// gps-source-ab-test notes for why. The `fused` / `fused_fast` variants that
/// existed while that A/B ran have been removed now the decision is final.
abstract class LocationSource {
  Stream<GpsFix> positions();

  /// The raw GNSS pipeline: force the Android *LocationManager*
  /// (`GPS_PROVIDER`, pure GNSS, no Play Services fusion), poll ~1 Hz, and take
  /// every fix (no distance filter) so the engine sees the chip's true cadence.
  factory LocationSource.raw() => _GeolocatorSource(_rawSettings);

  static final LocationSettings _rawSettings = AndroidSettings(
    accuracy: LocationAccuracy.best,
    forceLocationManager: true,
    intervalDuration: const Duration(seconds: 1),
    distanceFilter: 0,
  );
}

/// geolocator-backed source: geolocator under the hood, feeding [LocationSettings]
/// to the position stream and normalising each [Position] to a [GpsFix].
class _GeolocatorSource implements LocationSource {
  _GeolocatorSource(this._settings);

  final LocationSettings _settings;

  @override
  Stream<GpsFix> positions() => Geolocator.getPositionStream(
        locationSettings: _settings,
      ).map(GpsFix.fromPosition);
}

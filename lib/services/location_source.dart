import 'package:geolocator/geolocator.dart';

/// Which GPS pipeline a ride is recorded with. This is a temporary A/B testing
/// switch — the loser will be deleted once we've decided which behaves better
/// for real motorcycle riding.
///
/// - [fused]: geolocator's default (Google Play Services *fused* provider),
///   with a 5 m distance filter — the app's original behaviour.
/// - [raw]: geolocator forced onto the Android *LocationManager* (`GPS_PROVIDER`,
///   pure GNSS, no Play Services fusion), polling ~1 Hz with no distance filter
///   so we see every fix the chip produces.
/// - [fusedFast]: the *fused* provider (Play Services sensor fusion, poor-signal
///   help) but at raw's fast cadence — 1 s interval, no distance filter. Tests
///   whether fused's coarseness was the 5 m filter rather than the provider.
enum LocationSourceKind {
  fused,
  raw,
  fusedFast;

  /// Short stable tag persisted on the ride and shown in diagnostics.
  String get tag => switch (this) {
        LocationSourceKind.fused => 'fused',
        LocationSourceKind.raw => 'raw',
        LocationSourceKind.fusedFast => 'fused_fast',
      };

  /// Human label for the picker / summary.
  String get label => switch (this) {
        LocationSourceKind.fused => 'Fused (default)',
        LocationSourceKind.raw => 'Raw GPS',
        LocationSourceKind.fusedFast => 'Fused fast',
      };

  static LocationSourceKind fromTag(String? tag) => switch (tag) {
        'raw' => LocationSourceKind.raw,
        'fused_fast' => LocationSourceKind.fusedFast,
        _ => LocationSourceKind.fused,
      };
}

/// A single normalised GPS fix, decoupling the tracking engine from geolocator's
/// [Position] so the fix source can be swapped without touching the engine.
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

/// A stream of GPS fixes. One implementation per [LocationSourceKind]; the
/// tracking engine consumes only this interface.
abstract class LocationSource {
  Stream<GpsFix> positions();

  static LocationSource forKind(LocationSourceKind kind) => switch (kind) {
        LocationSourceKind.fused => _GeolocatorSource(_fusedSettings),
        LocationSourceKind.raw => _GeolocatorSource(_rawSettings),
        LocationSourceKind.fusedFast => _GeolocatorSource(_fusedFastSettings),
      };

  /// Original behaviour: fused provider, 5 m distance filter to suppress jitter.
  static final LocationSettings _fusedSettings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 5,
  );

  /// Raw GNSS: force the LocationManager (`GPS_PROVIDER`), poll ~1 Hz, and take
  /// every fix (no distance filter) so we can measure the chip's true cadence.
  static final LocationSettings _rawSettings = AndroidSettings(
    accuracy: LocationAccuracy.best,
    forceLocationManager: true,
    intervalDuration: const Duration(seconds: 1),
    distanceFilter: 0,
  );

  /// Fused provider (Play Services fusion) at raw's fast cadence: 1 s interval,
  /// no distance filter. `forceLocationManager: false` keeps the fused provider;
  /// this isolates "provider" from "cadence" vs the original [_fusedSettings].
  static final LocationSettings _fusedFastSettings = AndroidSettings(
    accuracy: LocationAccuracy.best,
    forceLocationManager: false,
    intervalDuration: const Duration(seconds: 1),
    distanceFilter: 0,
  );
}

/// Both current sources are geolocator under the hood — they differ only in the
/// [LocationSettings] handed to the position stream.
class _GeolocatorSource implements LocationSource {
  _GeolocatorSource(this._settings);

  final LocationSettings _settings;

  @override
  Stream<GpsFix> positions() => Geolocator.getPositionStream(
        locationSettings: _settings,
      ).map(GpsFix.fromPosition);
}

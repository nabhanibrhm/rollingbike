import 'package:geolocator/geolocator.dart';

/// Which GPS pipeline a ride is recorded with. This is a temporary A/B testing
/// switch — the loser will be deleted once we've decided which behaves better
/// for real motorcycle riding. (The original 5 m-filtered `fused` provider has
/// already been dropped; the comparison is now raw vs fusedFast.)
///
/// - [raw]: geolocator forced onto the Android *LocationManager* (`GPS_PROVIDER`,
///   pure GNSS, no Play Services fusion), polling ~1 Hz with no distance filter
///   so we see every fix the chip produces.
/// - [fusedFast]: the *fused* provider (Play Services sensor fusion, poor-signal
///   help) but at raw's fast cadence — 1 s interval, no distance filter.
enum LocationSourceKind {
  raw,
  fusedFast;

  /// Short stable tag persisted on the ride and shown in diagnostics.
  String get tag => switch (this) {
        LocationSourceKind.raw => 'raw',
        LocationSourceKind.fusedFast => 'fused_fast',
      };

  /// Human label for the picker / summary.
  String get label => switch (this) {
        LocationSourceKind.raw => 'Raw GPS (default)',
        LocationSourceKind.fusedFast => 'Fused fast',
      };

  /// Maps a persisted tag back to a kind. Unknown tags — including the retired
  /// `'fused'` — fall back to [raw] (the default/committed pipeline).
  static LocationSourceKind fromTag(String? tag) => switch (tag) {
        'fused_fast' => LocationSourceKind.fusedFast,
        _ => LocationSourceKind.raw,
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
        LocationSourceKind.raw => _GeolocatorSource(_rawSettings),
        LocationSourceKind.fusedFast => _GeolocatorSource(_fusedFastSettings),
      };

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
  /// pairs the fused provider with raw's fast, unfiltered cadence.
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

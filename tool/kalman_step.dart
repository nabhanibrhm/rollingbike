// Diagnostic: measure the speed-response latency of GpsKalmanFilter.
// Feeds a synthetic step change in true speed and reports how long the
// filter's output takes to reach 63% / 90% / 95% of the change.
// Run: dart run tool/kalman_step.dart
import 'package:rollingbike/core/gps_kalman.dart';

/// Drive the filter through a step from v0 -> v1 (m/s) at a fixed fix cadence,
/// with or without Doppler fusion, and print the rise times.
void runStep({
  required String label,
  required double v0,
  required double v1,
  required double dt, // seconds between fixes
  required bool doppler,
  double accuracyMeters = 5.0,
  double speedAccuracy = 1.0,
}) {
  final k = GpsKalmanFilter(); // accelerationNoise = 2.0 (production default)
  double t = 0;
  double east = 0; // metres travelled east
  const lat0 = -6.3, lon0 = 106.9;
  const mPerDegLat = 111320.0;
  final mPerDegLon = 111320.0 * 0.994; // ~cos(6.3°)

  void feed(double v) {
    east += v * dt;
    final lon = lon0 + east / mPerDegLon;
    k.update(
      lat: lat0,
      lon: lon,
      accuracyMeters: accuracyMeters,
      timeMs: t * 1000.0,
      speed: doppler ? v : null,
      speedAccuracy: doppler ? speedAccuracy : null,
      headingDegrees: doppler ? 90.0 : null, // due east
    );
  }

  // Settle at v0.
  for (var i = 0; i < 40; i++) {
    feed(v0);
    t += dt;
  }

  final start = k.speedMps;
  final delta = v1 - v0;
  final tgt63 = v0 + 0.632 * delta;
  final tgt90 = v0 + 0.90 * delta;
  final tgt95 = v0 + 0.95 * delta;
  bool rising = delta > 0;
  bool hit(double cur, double tgt) => rising ? cur >= tgt : cur <= tgt;

  double? t63, t90, t95;
  final tStep = t;
  for (var i = 0; i < 200; i++) {
    feed(v1);
    t += dt;
    final cur = k.speedMps;
    final elapsed = t - tStep;
    if (t63 == null && hit(cur, tgt63)) t63 = elapsed;
    if (t90 == null && hit(cur, tgt90)) t90 = elapsed;
    if (t95 == null && hit(cur, tgt95)) t95 = elapsed;
    if (t95 != null) break;
  }

  String s(double? x) => x == null ? '  >n/a' : '${x.toStringAsFixed(1)}s'.padLeft(6);
  print('$label');
  print('  step ${(v0 * 3.6).toStringAsFixed(0)} -> ${(v1 * 3.6).toStringAsFixed(0)} km/h  '
      '@ ${dt.toStringAsFixed(0)}s fixes, doppler=${doppler ? "on " : "off"}, '
      'startOut=${(start * 3.6).toStringAsFixed(1)} km/h');
  print('    63% (1 time-const): ${s(t63)}   90%: ${s(t90)}   95%: ${s(t95)}');
}

void main() {
  print('=== SPEED-UP  (accelerating) ===');
  runStep(label: '[1] Doppler, 1s fixes', v0: 15, v1: 25, dt: 1, doppler: true);
  runStep(label: '[2] Doppler, 2s fixes', v0: 15, v1: 25, dt: 2, doppler: true);
  runStep(label: '[3] Doppler, 3s fixes', v0: 15, v1: 25, dt: 3, doppler: true);
  runStep(label: '[4] Position-only, 1s fixes', v0: 15, v1: 25, dt: 1, doppler: false);
  runStep(label: '[5] Position-only, 3s fixes', v0: 15, v1: 25, dt: 3, doppler: false);

  print('\n=== SLOW-DOWN (braking) ===');
  runStep(label: '[6] Doppler, 1s fixes', v0: 25, v1: 8, dt: 1, doppler: true);
  runStep(label: '[7] Doppler, 3s fixes', v0: 25, v1: 8, dt: 3, doppler: true);
  runStep(label: '[8] Position-only, 1s fixes', v0: 25, v1: 8, dt: 1, doppler: false);

  print('\n=== effect of reported speedAccuracy (Doppler, 1s) ===');
  runStep(label: '[9]  sa=0.5 (good)', v0: 15, v1: 25, dt: 1, doppler: true, speedAccuracy: 0.5);
  runStep(label: '[10] sa=2.0 (poor)', v0: 15, v1: 25, dt: 1, doppler: true, speedAccuracy: 2.0);
}

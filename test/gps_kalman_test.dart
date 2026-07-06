import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rollingbike/core/gps_kalman.dart';

void main() {
  const metersPerDegLat = 111320.0;

  group('GpsKalmanFilter', () {
    test('is uninitialised until the first fix', () {
      final kf = GpsKalmanFilter();
      expect(kf.isInitialised, isFalse);
      kf.update(lat: 0, lon: 0, accuracyMeters: 5, timeMs: 0);
      expect(kf.isInitialised, isTrue);
    });

    test('first fix seeds position exactly and zero speed', () {
      final kf = GpsKalmanFilter();
      kf.update(lat: -6.2, lon: 106.8, accuracyMeters: 5, timeMs: 0);
      final (lat, lon) = kf.position;
      expect(lat, closeTo(-6.2, 1e-9));
      expect(lon, closeTo(106.8, 1e-9));
      expect(kf.speedKmh, closeTo(0, 1e-9));
    });

    test('a stationary noisy rider reads near-zero speed', () {
      final kf = GpsKalmanFilter();
      final rnd = math.Random(42);
      for (var i = 0; i < 60; i++) {
        // ±4 m of position noise around a fixed point, position-only (no Doppler)
        final dLat = (rnd.nextDouble() - 0.5) * 8 / metersPerDegLat;
        final dLon = (rnd.nextDouble() - 0.5) * 8 / metersPerDegLat;
        kf.update(
          lat: 0 + dLat,
          lon: 0 + dLon,
          accuracyMeters: 5,
          timeMs: i * 1000.0,
        );
      }
      // Jitter must not masquerade as real movement.
      expect(kf.speedKmh, lessThan(5));
    });

    test('constant eastward motion converges to the true speed', () {
      final kf = GpsKalmanFilter();
      const speedMps = 10.0; // 36 km/h due east
      const metersPerDegLon = metersPerDegLat; // at the equator, cos(0) = 1
      for (var i = 0; i < 40; i++) {
        final east = speedMps * i; // metres east after i seconds
        kf.update(
          lat: 0,
          lon: east / metersPerDegLon,
          accuracyMeters: 5,
          timeMs: i * 1000.0,
        );
      }
      // Position-only, so it takes a few fixes to settle; 5% tolerance.
      expect(kf.speedKmh, closeTo(36, 36 * 0.05));
      final (lat, _) = kf.position;
      expect(lat, closeTo(0, 1e-4)); // no northward drift
    });

    test('fusing Doppler velocity locks on faster than position alone', () {
      final withDoppler = GpsKalmanFilter();
      final positionOnly = GpsKalmanFilter();
      const speedMps = 20.0; // 72 km/h due east
      const metersPerDegLon = metersPerDegLat;
      for (var i = 0; i < 6; i++) {
        final lon = (speedMps * i) / metersPerDegLon;
        withDoppler.update(
          lat: 0,
          lon: lon,
          accuracyMeters: 5,
          timeMs: i * 1000.0,
          speed: speedMps,
          speedAccuracy: 1,
          headingDegrees: 90, // due east
        );
        positionOnly.update(
          lat: 0,
          lon: lon,
          accuracyMeters: 5,
          timeMs: i * 1000.0,
        );
      }
      // With Doppler the velocity state should be much closer to truth early on.
      final dopplerErr = (withDoppler.speedKmh - 72).abs();
      final posErr = (positionOnly.speedKmh - 72).abs();
      expect(dopplerErr, lessThan(posErr));
      expect(withDoppler.speedKmh, closeTo(72, 72 * 0.1));
    });

    test('reset() forces a fresh re-seed', () {
      final kf = GpsKalmanFilter();
      kf.update(lat: 1, lon: 1, accuracyMeters: 5, timeMs: 0);
      kf.reset();
      expect(kf.isInitialised, isFalse);
      kf.update(lat: 2, lon: 2, accuracyMeters: 5, timeMs: 1000);
      final (lat, lon) = kf.position;
      expect(lat, closeTo(2, 1e-9));
      expect(lon, closeTo(2, 1e-9));
    });
  });
}

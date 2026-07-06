import 'dart:math' as math;

/// A constant-velocity Kalman filter for GPS fixes.
///
/// Fuses noisy position — and, when trustworthy, Doppler velocity — into a
/// smoothed position + velocity estimate. This replaces the earlier EMA speed
/// smoothing with a proper motion model, which both cleans the drawn route and
/// yields a stable speed with far less lag and jitter than an EMA.
///
/// The maths run in a local east/north metric plane anchored at the first fix,
/// so a standard 2-state (`[position, velocity]`) linear model applies
/// independently per axis. The lat/lon <-> metres transform uses the same
/// constants both ways, so round-tripping a smoothed estimate back to lat/lon is
/// self-consistent (no drift is introduced by the projection itself).
class GpsKalmanFilter {
  GpsKalmanFilter({double accelerationNoise = 2.0}) : _qAccel = accelerationNoise;

  /// Process noise: the expected unmodelled acceleration, in m/s². Higher trusts
  /// the measurements more (snappier, noisier); lower is smoother (more lag).
  /// 2 m/s² suits a motorcycle's ordinary speed changes.
  final double _qAccel;

  /// Metres per degree of latitude (near-constant across the globe).
  static const double _metersPerDegLat = 111320.0;

  // Local-frame origin (first fix) and the longitude scale at that latitude.
  double _lat0 = 0;
  double _lon0 = 0;
  double _metersPerDegLon = _metersPerDegLat;

  bool _initialised = false;
  double? _lastTimeMs;

  final _east = _AxisState();
  final _north = _AxisState();

  /// Whether a first fix has seeded the filter.
  bool get isInitialised => _initialised;

  /// Drop all state so the next [update] re-seeds from scratch. Called on
  /// pause and after re-anchoring past a run of rejected GPS jumps.
  void reset() {
    _initialised = false;
    _lastTimeMs = null;
  }

  /// Feed one accepted fix.
  ///
  /// [timeMs] must be a monotonically non-decreasing timestamp in milliseconds.
  /// Supply [speed]/[headingDegrees] to fuse a Doppler velocity; omit them (or
  /// pass a null [speed]) to update from position only.
  void update({
    required double lat,
    required double lon,
    required double accuracyMeters,
    required double timeMs,
    double? speed, // m/s (Doppler)
    double? speedAccuracy, // m/s
    double? headingDegrees, // course over ground
  }) {
    // Measurement noise variance, with a floor — some devices report 0 accuracy.
    final acc = math.max(1.0, accuracyMeters);
    final rPos = acc * acc;

    if (!_initialised) {
      _lat0 = lat;
      _lon0 = lon;
      _metersPerDegLon = _metersPerDegLat * math.cos(lat * math.pi / 180.0);
      _east.init(0, rPos);
      _north.init(0, rPos);
      _lastTimeMs = timeMs;
      _initialised = true;
      return;
    }

    // Predict forward to this fix's time.
    var dt = (timeMs - (_lastTimeMs ?? timeMs)) / 1000.0;
    if (dt < 0) dt = 0;
    _lastTimeMs = timeMs;
    _east.predict(dt, _qAccel);
    _north.predict(dt, _qAccel);

    // Position measurement update.
    final mEast = (lon - _lon0) * _metersPerDegLon;
    final mNorth = (lat - _lat0) * _metersPerDegLat;
    _east.updatePosition(mEast, rPos);
    _north.updatePosition(mNorth, rPos);

    // Optional Doppler velocity update — decompose speed along its heading into
    // east/north components. Only trusted when actually moving, since heading is
    // unreliable at a near-standstill.
    if (speed != null &&
        speed.isFinite &&
        speed >= 0 &&
        headingDegrees != null &&
        headingDegrees.isFinite) {
      final sa = (speedAccuracy != null && speedAccuracy.isFinite && speedAccuracy > 0)
          ? speedAccuracy
          : 1.0;
      final rVel = sa * sa;
      final h = headingDegrees * math.pi / 180.0;
      _east.updateVelocity(speed * math.sin(h), rVel);
      _north.updateVelocity(speed * math.cos(h), rVel);
    }
  }

  /// Smoothed position as (latitude, longitude). Only valid once [isInitialised].
  (double lat, double lon) get position => (
        _lat0 + _north.pos / _metersPerDegLat,
        _lon0 + _east.pos / _metersPerDegLon,
      );

  /// Smoothed ground speed in metres per second.
  double get speedMps => math.sqrt(_east.vel * _east.vel + _north.vel * _north.vel);

  /// Smoothed ground speed in km/h.
  double get speedKmh => speedMps * 3.6;
}

/// One axis's `[position, velocity]` state and its 2x2 covariance `P`.
class _AxisState {
  double pos = 0;
  double vel = 0;
  // P = [[p00, p01], [p10, p11]] (kept symmetric: p01 == p10).
  double _p00 = 0, _p01 = 0, _p10 = 0, _p11 = 0;

  void init(double position, double rPos) {
    pos = position;
    vel = 0;
    _p00 = rPos;
    _p01 = 0;
    _p10 = 0;
    _p11 = rPos; // no velocity info yet — start uncertain
  }

  /// Predict: x' = F x, P' = F P Fᵀ + Q, with F = [[1, dt], [0, 1]] and Q the
  /// discretised continuous white-noise-acceleration model.
  void predict(double dt, double qAccel) {
    if (dt <= 0) return;

    pos += vel * dt;

    // F P
    final fp00 = _p00 + dt * _p10;
    final fp01 = _p01 + dt * _p11;
    final fp10 = _p10;
    final fp11 = _p11;
    // (F P) Fᵀ
    var np00 = fp00 + fp01 * dt;
    final np01 = fp01;
    final np10 = fp10 + fp11 * dt;
    final np11 = fp11;
    // + Q
    final s = qAccel * qAccel;
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt2 * dt2;
    _p00 = np00 + s * dt4 / 4.0;
    _p01 = np01 + s * dt3 / 2.0;
    _p10 = np10 + s * dt3 / 2.0;
    _p11 = np11 + s * dt2;
  }

  /// Correct with a position measurement (H = [1, 0]).
  void updatePosition(double z, double r) {
    final y = z - pos;
    final s = _p00 + r;
    final k0 = _p00 / s;
    final k1 = _p10 / s;
    pos += k0 * y;
    vel += k1 * y;
    // P = (I - K H) P
    final np00 = (1 - k0) * _p00;
    final np01 = (1 - k0) * _p01;
    final np10 = _p10 - k1 * _p00;
    final np11 = _p11 - k1 * _p01;
    _p00 = np00;
    _p01 = np01;
    _p10 = np10;
    _p11 = np11;
  }

  /// Correct with a velocity measurement (H = [0, 1]).
  void updateVelocity(double z, double r) {
    final y = z - vel;
    final s = _p11 + r;
    final k0 = _p01 / s;
    final k1 = _p11 / s;
    pos += k0 * y;
    vel += k1 * y;
    // P = (I - K H) P
    final np00 = _p00 - k0 * _p10;
    final np01 = _p01 - k0 * _p11;
    final np10 = (1 - k1) * _p10;
    final np11 = (1 - k1) * _p11;
    _p00 = np00;
    _p01 = np01;
    _p10 = np10;
    _p11 = np11;
  }
}

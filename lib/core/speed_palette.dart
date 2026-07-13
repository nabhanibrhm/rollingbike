import 'package:flutter/painting.dart';

/// Turbo-style speed ramp for coloring a route by ground speed:
/// blue (slow) → cyan → green → yellow → orange → red (fast). A perceptually
/// improved rainbow — vivid endpoints chosen so the peak *glows* red and a
/// standstill reads clearly blue on the dark basemap. [t] is a normalized speed
/// (`speed / maxSpeed`), clamped to 0..1.
class SpeedPalette {
  const SpeedPalette._();

  /// Anchor stops `(position, color)`, interpolated linearly in RGB.
  static const List<(double, Color)> _stops = [
    (0.00, Color(0xFF2E7DF2)), // blue
    (0.22, Color(0xFF17C0D4)), // cyan
    (0.44, Color(0xFF24D65C)), // green
    (0.64, Color(0xFFE8D62B)), // yellow
    (0.82, Color(0xFFF58B1E)), // orange
    (1.00, Color(0xFFF5321E)), // red
  ];

  /// The ramp colors in order — feed to a [LinearGradient] for a legend bar.
  static List<Color> get gradient => [for (final s in _stops) s.$2];

  /// The ramp stop positions in order, paired with [gradient].
  static List<double> get gradientStops => [for (final s in _stops) s.$1];

  /// Color for a normalized speed [t] (clamped to 0..1).
  static Color at(double t) {
    final v = t.clamp(0.0, 1.0);
    for (var i = 1; i < _stops.length; i++) {
      final (p1, c1) = _stops[i];
      if (v <= p1) {
        final (p0, c0) = _stops[i - 1];
        final f = p1 == p0 ? 0.0 : (v - p0) / (p1 - p0);
        return Color.lerp(c0, c1, f)!;
      }
    }
    return _stops.last.$2;
  }
}

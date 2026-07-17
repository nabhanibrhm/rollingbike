import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

/// Shared axis/plot helpers for the speed charts (full-ride overview + live
/// follow-cam), so both draw gridlines on the same "nice" round numbers and
/// thin long series the same way.

/// A "nice" round step (1/2/5 × 10ⁿ) that splits [range] into roughly [target]
/// intervals — so gridlines and labels land on readable numbers.
double niceInterval(double range, int target) {
  if (range <= 0) return 1;
  final raw = range / target;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final double nice = norm < 1.5
      ? 1
      : norm < 3
          ? 2
          : norm < 7
              ? 5
              : 10;
  return nice * mag;
}

/// Axis tick label: one decimal when the step is sub-unit, else whole numbers.
String fmtTick(double v, double interval) =>
    interval < 1 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

/// Uniformly thins [spots] to at most [max] points, always keeping the first
/// and last, so a long series stays cheap to redraw without changing its shape.
List<FlSpot> downsampleSpots(List<FlSpot> spots, int max) {
  if (spots.length <= max) return spots;
  final stride = spots.length / max;
  final out = <FlSpot>[];
  for (var i = 0; i < max; i++) {
    out.add(spots[(i * stride).floor()]);
  }
  out.add(spots.last);
  return out;
}

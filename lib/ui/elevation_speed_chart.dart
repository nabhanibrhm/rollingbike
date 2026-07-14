import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/units.dart';
import '../data/models/track_point.dart';
import '../theme/app_theme.dart';

/// Dual-axis profile over time: a filled green **elevation** area in the
/// background with the **speed** line laid over it. Gives the speed data
/// physical context — you can see speed bleed off on a climb and peak on a
/// descent. Left axis is speed (rider's unit), right axis is elevation (m).
///
/// fl_chart shares one y-scale, so elevation is linearly mapped onto the speed
/// axis and the right-hand tick labels are mapped back to real metres. Skipped
/// entirely when the track has no usable altitude or no real elevation change.
class ElevationSpeedChart extends StatelessWidget {
  const ElevationSpeedChart({
    super.key,
    required this.points,
    required this.unit,
  });

  final List<TrackPoint> points;
  final SpeedUnit unit;

  static const Color _speedColor = Color(0xFF3B82F6); // blue
  static const Color _elevColor = Color(0xFF22C55E); // green

  /// Minimum elevation swing (m) for the chart to be worth showing.
  static const double _minElevRange = 2.0;

  /// Per-step altitude change below this (m) is GPS noise, not real gain/loss.
  static const double _gainNoiseFloor = 1.0;

  static const int _maxPoints = 300;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final start = points.first.timestamp;

    // Elevation series (only points that carry altitude).
    final elev = <FlSpot>[]; // (tSec, metres) — real metres for now
    double? eMin, eMax;
    var gain = 0.0, loss = 0.0;
    double? prevAlt;
    for (final p in points) {
      final alt = p.altitude;
      if (alt == null) continue;
      final tSec = p.timestamp.difference(start).inMilliseconds / 1000.0;
      elev.add(FlSpot(tSec, alt));
      eMin = eMin == null ? alt : (alt < eMin ? alt : eMin);
      eMax = eMax == null ? alt : (alt > eMax ? alt : eMax);
      if (prevAlt != null) {
        final d = alt - prevAlt;
        if (d.abs() >= _gainNoiseFloor) {
          if (d > 0) {
            gain += d;
          } else {
            loss += -d;
          }
        }
      }
      prevAlt = alt;
    }

    if (elev.length < 2 ||
        eMin == null ||
        eMax == null ||
        (eMax - eMin) < _minElevRange) {
      return const SizedBox.shrink();
    }

    // Speed series (all points), in the display unit.
    final speed = <FlSpot>[
      for (final p in points)
        FlSpot(
          p.timestamp.difference(start).inMilliseconds / 1000.0,
          unit.speed(p.speedMps * 3.6),
        ),
    ];

    final maxSpeed = speed.fold(0.0, (m, s) => s.y > m ? s.y : m);
    final maxY = maxSpeed <= 0 ? 1.0 : maxSpeed;
    final eRange = eMax - eMin;
    // Map real metres onto the shared speed axis.
    double ePlot(double metres) => (metres - eMin!) / eRange * maxY;
    final elevScaled = [
      for (final s in elev) FlSpot(s.x, ePlot(s.y)),
    ];

    final totalSec =
        points.last.timestamp.difference(start).inMilliseconds / 1000.0;
    final maxX = totalSec <= 0 ? 1.0 : totalSec;

    return Container(
      width: double.infinity,
      color: cx.canvas,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ELEVATION VS. SPEED PROFILE',
            style: TextStyle(
              color: cx.textBright,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Dual-axis profile over time',
            style: TextStyle(color: cx.textDim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LegendDot(color: _speedColor, label: 'Speed (${unit.speedLabel})'),
              const SizedBox(width: 16),
              _LegendDot(color: _elevColor, label: 'Elevation (m)'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 2,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: cx.border.withValues(alpha: 0.4), strokeWidth: 1),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: cx.border),
                    right: BorderSide(color: cx.border),
                    bottom: BorderSide(color: cx.border),
                  ),
                ),
                lineTouchData: const LineTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: maxY / 2,
                      getTitlesWidget: (v, meta) => Text(
                        v.toStringAsFixed(0),
                        style: _tick(cx, _speedColor),
                      ),
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: maxY / 2,
                      getTitlesWidget: (v, meta) {
                        final metres = eMin! + (v / maxY) * eRange;
                        return Text(
                          metres.toStringAsFixed(0),
                          style: _tick(cx, _elevColor),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: maxX / 4,
                      getTitlesWidget: (v, meta) => Text(
                        _fmtClock(v.round()),
                        style: TextStyle(color: cx.textDim, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  // Elevation area first, so the speed line draws on top.
                  LineChartBarData(
                    spots: _downsample(elevScaled),
                    isCurved: true,
                    curveSmoothness: 0.2,
                    preventCurveOverShooting: true,
                    color: _elevColor.withValues(alpha: 0.7),
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _elevColor.withValues(alpha: 0.22),
                    ),
                  ),
                  LineChartBarData(
                    spots: _downsample(speed),
                    isCurved: true,
                    curveSmoothness: 0.2,
                    preventCurveOverShooting: true,
                    color: _speedColor,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Time',
              style: TextStyle(color: cx.textDim, fontSize: 11),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _ElevStat(label: 'ELEV GAIN', value: '${gain.round()} m'),
              _ElevStat(label: 'ELEV LOSS', value: '${loss.round()} m'),
              _ElevStat(label: 'MAX ELEV', value: '${eMax.round()} m'),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _tick(AppPalette cx, Color color) =>
      TextStyle(color: color.withValues(alpha: 0.9), fontSize: 10);

  /// Uniformly thins [spots] to at most [_maxPoints], always keeping the last.
  static List<FlSpot> _downsample(List<FlSpot> spots) {
    if (spots.length <= _maxPoints) return spots;
    final stride = spots.length / _maxPoints;
    final out = <FlSpot>[];
    for (var i = 0; i < _maxPoints; i++) {
      out.add(spots[(i * stride).floor()]);
    }
    out.add(spots.last);
    return out;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: cx.textDim, fontSize: 12)),
      ],
    );
  }
}

class _ElevStat extends StatelessWidget {
  const _ElevStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cx.textDim, fontSize: 11)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: cx.textBright,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seconds → `m:ss` (or `h:mm:ss`) for the time axis.
String _fmtClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

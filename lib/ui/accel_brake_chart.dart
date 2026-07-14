import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/models/track_point.dart';
import '../theme/app_theme.dart';

/// Longitudinal acceleration scatter over time: each dot is the rate of change
/// of speed (Δv/Δt) between two fixes. Blue dots above the zero line are
/// acceleration, red dots below are braking. Spikes past ±[_eventThreshold]
/// count as "rapid acceleration" / "hard braking" events — a read on riding
/// smoothness and brake / drivetrain wear.
class AccelBrakeChart extends StatelessWidget {
  const AccelBrakeChart({super.key, required this.points});

  final List<TrackPoint> points;

  static const Color _accelColor = Color(0xFF3B82F6); // blue
  static const Color _brakeColor = Color(0xFFEF4444); // red

  /// |a| beyond this (m/s²) is a hard event.
  static const double _eventThreshold = 1.5;

  /// Intervals outside this range (s) are sub-second noise or gaps — skipped so
  /// they can't manufacture huge spurious accelerations.
  static const double _minDt = 0.5;
  static const double _maxDt = 10.0;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final start = points.first.timestamp;

    final spots = <ScatterSpot>[];
    var accelEvents = 0;
    var brakeEvents = 0;
    var maxAbs = 1.0;

    for (var i = 1; i < points.length; i++) {
      final dt = points[i].timestamp
              .difference(points[i - 1].timestamp)
              .inMilliseconds /
          1000.0;
      if (dt < _minDt || dt > _maxDt) continue;
      final a = (points[i].speedMps - points[i - 1].speedMps) / dt;
      final tSec =
          points[i].timestamp.difference(start).inMilliseconds / 1000.0;
      spots.add(
        ScatterSpot(
          tSec,
          a,
          dotPainter: FlDotCirclePainter(
            radius: 2.5,
            color: a >= 0 ? _accelColor : _brakeColor,
          ),
        ),
      );
      if (a > _eventThreshold) accelEvents++;
      if (a < -_eventThreshold) brakeEvents++;
      if (a.abs() > maxAbs) maxAbs = a.abs();
    }

    if (spots.isEmpty) return const SizedBox.shrink();

    final maxY = maxAbs * 1.15;
    final totalSec =
        points.last.timestamp.difference(start).inMilliseconds / 1000.0;
    final maxX = totalSec <= 0 ? 1.0 : totalSec;
    final gridStyle = FlLine(color: cx.border.withValues(alpha: 0.4), strokeWidth: 1);

    return Container(
      width: double.infinity,
      color: cx.canvas,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACCELERATION & BRAKING INTENSITY',
            style: TextStyle(
              color: cx.textBright,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Rate of change of speed over time',
            style: TextStyle(color: cx.textDim, fontSize: 12),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: ScatterChart(
              ScatterChartData(
                scatterSpots: spots,
                minX: 0,
                maxX: maxX,
                minY: -maxY,
                maxY: maxY,
                scatterTouchData: ScatterTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY,
                  // Emphasise the y = 0 baseline; other lines stay faint.
                  getDrawingHorizontalLine: (v) => v.abs() < 0.001
                      ? FlLine(color: cx.textDim, strokeWidth: 1)
                      : gridStyle,
                  checkToShowHorizontalLine: (v) => true,
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: cx.border),
                    bottom: BorderSide(color: cx.border),
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: maxY,
                      getTitlesWidget: (v, meta) {
                        if (v.abs() < 0.001) {
                          return Text('0', style: _tick(cx));
                        }
                        return Text(v.toStringAsFixed(1), style: _tick(cx));
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
                        style: _tick(cx),
                      ),
                    ),
                  ),
                ),
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
          const SizedBox(height: 16),
          _EventLine(
            color: _accelColor,
            title: 'Rapid Acceleration',
            detail: '> $_eventThreshold m/s²',
            events: accelEvents,
          ),
          const SizedBox(height: 12),
          _EventLine(
            color: _brakeColor,
            title: 'Hard Braking',
            detail: '< -$_eventThreshold m/s²',
            events: brakeEvents,
          ),
        ],
      ),
    );
  }

  TextStyle _tick(AppPalette cx) => TextStyle(color: cx.textDim, fontSize: 10);
}

/// One summary line under the scatter: colour dot + label + detail + count.
class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.color,
    required this.title,
    required this.detail,
    required this.events,
  });

  final Color color;
  final String title;
  final String detail;
  final int events;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              text: title,
              style: TextStyle(
                color: cx.textBright,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              children: [
                TextSpan(
                  text: '   $detail',
                  style: TextStyle(
                    color: cx.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          'Events: $events',
          style: TextStyle(
            color: cx.textBright,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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

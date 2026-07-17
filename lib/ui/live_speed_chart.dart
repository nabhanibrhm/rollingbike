import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/units.dart';
import '../theme/app_theme.dart';
import 'chart_math.dart';

/// Live "follow-cam" speed chart for the Record tab. Rather than showing the
/// whole ride, it pins the current moment (the latest sample) at the horizontal
/// **centre** — like the bird in Flappy Bird — and lets the trailing speed line
/// and the dashed gridlines scroll leftward toward it as distance accrues. The
/// centred dot rides up and down with live speed; the right half is the open
/// "runway" ahead.
///
/// [spots] are cumulative `FlSpot(distanceKm, speedKmh)` (metric); they're
/// converted to the display [unit] up front so the scrolling distance ticks and
/// the speed scale stay on round numbers in either km or mi.
class LiveSpeedChart extends StatelessWidget {
  const LiveSpeedChart({
    super.key,
    required this.spots,
    required this.unit,
    this.windowSpan = 2.0,
    this.maxPoints = 180,
  });

  final List<FlSpot> spots;
  final SpeedUnit unit;

  /// Visible distance window (in the display unit). The latest point sits at
  /// its centre, so half trails behind and half is the runway ahead.
  final double windowSpan;

  final int maxPoints;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    if (spots.isEmpty) return const SizedBox.shrink();

    // Work in display space (km or mi) so scrolling ticks land on round values.
    final disp = <FlSpot>[
      for (final s in spots) FlSpot(unit.distanceKm(s.x), unit.speed(s.y)),
    ];
    final dNow = disp.last.x; // "now" — pinned at the horizontal centre
    final vNow = disp.last.y;

    final half = windowSpan / 2;
    final minX = dNow - half; // may be < 0 in the first metres of a ride
    final maxX = dNow + half;

    // Only the windowed tail needs drawing; thin it for cheap live redraws.
    final windowed = [for (final s in disp) if (s.x >= minX) s];
    final data = downsampleSpots(windowed, maxPoints);

    // Speed ceiling from the whole ride so the dot's height reads as speed and
    // the scale only ever grows — it never jumps around beneath the bird. Keep
    // at least half an interval of headroom above the peak so the bird dot never
    // rides tight against the top edge (it bobs up to the ride max).
    final rideMax = disp.fold(0.0, (m, s) => math.max(m, s.y));
    final yInterval = niceInterval(rideMax, 4);
    final ceilY = (rideMax / yInterval).ceil() * yInterval;
    final maxY = rideMax <= 0
        ? yInterval
        : (ceilY - rideMax < yInterval * 0.5 ? ceilY + yInterval : ceilY);
    // Whole-unit distance ticks (every 1 km / 1 mi) rather than every 0.5 — fewer
    // gridlines, so the trailing trace reads as more stretched between them.
    final xInterval = niceInterval(windowSpan, 2);

    final gridLine = FlLine(
      color: cx.border.withValues(alpha: 0.55),
      strokeWidth: 1,
      dashArray: const [4, 4],
    );
    const hiddenLine = FlLine(color: Color(0x00000000), strokeWidth: 0);
    final tickStyle = TextStyle(color: cx.textDim, fontSize: 11);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 4),
      child: Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawHorizontalLine: true,
                  drawVerticalLine: true,
                  horizontalInterval: yInterval,
                  verticalInterval: xInterval,
                  getDrawingHorizontalLine: (_) => gridLine,
                  // No gridline in the pre-start (negative distance) runway.
                  getDrawingVerticalLine: (v) => v < 0 ? hiddenLine : gridLine,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: yInterval,
                      getTitlesWidget: (v, meta) =>
                          Text(fmtTick(v, yInterval), style: tickStyle),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: xInterval,
                      // Round-number ticks only — no ragged edge labels, and
                      // nothing in the negative-distance runway.
                      minIncluded: false,
                      maxIncluded: false,
                      getTitlesWidget: (v, meta) => v < 0
                          ? const SizedBox.shrink()
                          : Text(fmtTick(v, xInterval), style: tickStyle),
                    ),
                  ),
                ),
                lineTouchData: const LineTouchData(enabled: false),
                clipData: const FlClipData.all(),
                lineBarsData: [
                  LineChartBarData(
                    spots: data,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    preventCurveOverShooting: true,
                    color: cx.accent,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      // Only the newest point — the "bird" — carries a marker.
                      checkToShowDot: (spot, _) =>
                          spot.x == dNow && spot.y == vNow,
                      getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                        radius: 4.5,
                        color: cx.accent,
                        strokeWidth: 5,
                        strokeColor: cx.accent.withValues(alpha: 0.28),
                      ),
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _legend(cx),
        ],
      ),
    );
  }

  Widget _legend(AppPalette cx) {
    Widget dot() => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cx.accent.withValues(alpha: 0.28),
          ),
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: cx.accent),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dot(),
        const SizedBox(width: 7),
        Text(
          'SPEED (${unit.speedLabel})',
          style: TextStyle(
            color: cx.textBright,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'DISTANCE (${unit.distanceLabel})',
          style: TextStyle(
            color: cx.textDim,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

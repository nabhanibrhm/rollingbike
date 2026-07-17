import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/units.dart';
import '../theme/app_theme.dart';
import 'chart_math.dart';

/// Speed-vs-distance line chart in the "Hyper" template style: a smooth amber
/// line over a faint **dashed grid** (both axes), round-interval numeric labels,
/// no surrounding frame, and haloed dot markers only at the points worth
/// calling out — the **start**, the **end**, and the **fastest** sample. A
/// continuous ride would turn a dot-per-sample into an unreadable blob, so the
/// Hyper marker treatment is reserved for those three.
///
/// [spots] arrive as `FlSpot(distanceKm, speedKmh)` (metric). They're
/// downsampled, then converted to the display [unit] up front so the axis ticks
/// land on round display numbers in either km or mi. Long series are thinned to
/// [maxPoints] for smooth live redraws.
class SpeedDistanceChart extends StatelessWidget {
  const SpeedDistanceChart({
    super.key,
    required this.spots,
    required this.avgSpeedKmh,
    required this.unit,
    this.maxPoints = 240,
    this.interactive = false,
  });

  final List<FlSpot> spots;

  /// Ride average (distance/time). Retained for API compatibility with the
  /// call sites; the Hyper layout uses round-interval ticks rather than an
  /// avg reference mark, so it's not currently drawn.
  final double avgSpeedKmh;

  final SpeedUnit unit;
  final int maxPoints;

  /// When true, touching/dragging along the line snaps to the nearest data
  /// point and shows a tooltip with that point's distance + speed. Off for the
  /// live ride chart (no one pokes it mid-ride); on for the saved-ride detail.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);

    // Downsample in metric, then convert to the display unit so every axis
    // tick, gridline and label works in one consistent (display) space.
    final raw = downsampleSpots(spots, maxPoints);
    final data = <FlSpot>[
      for (final s in raw) FlSpot(unit.distanceKm(s.x), unit.speed(s.y)),
    ];
    if (data.isEmpty) return const SizedBox.shrink();

    final maxSpeed = data.fold(0.0, (m, s) => math.max(m, s.y));
    final totalDist = data.last.x;

    // The three points that get a haloed marker.
    final first = data.first;
    final last = data.last;
    var maxSpot = data.first;
    for (final s in data) {
      if (s.y > maxSpot.y) maxSpot = s;
    }
    bool isKey(FlSpot s) =>
        (s.x == first.x && s.y == first.y) ||
        (s.x == last.x && s.y == last.y) ||
        (s.x == maxSpot.x && s.y == maxSpot.y);

    final yInterval = niceInterval(maxSpeed, 5);
    final xInterval = niceInterval(totalDist, 4);
    // Round the top up to the next gridline so the peak isn't glued to the edge.
    final maxY =
        maxSpeed <= 0 ? yInterval : ((maxSpeed / yInterval).floor() + 1) * yInterval;
    final maxX = totalDist <= 0 ? xInterval : totalDist;

    final gridLine = FlLine(
      color: cx.border.withValues(alpha: 0.55),
      strokeWidth: 1,
      dashArray: const [4, 4],
    );
    final tickStyle = TextStyle(color: cx.textDim, fontSize: 11);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
      child: Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
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
                  getDrawingVerticalLine: (_) => gridLine,
                ),
                borderData: FlBorderData(show: false),
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
                      // Skip the ragged label at the exact right edge (maxX =
                      // total distance); keep only the round-number ticks.
                      maxIncluded: false,
                      getTitlesWidget: (v, meta) =>
                          Text(fmtTick(v, xInterval), style: tickStyle),
                    ),
                  ),
                ),
                lineTouchData: interactive
                    ? LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => cx.surface,
                          tooltipRoundedRadius: 8,
                          tooltipBorder: BorderSide(color: cx.accentInk, width: 1),
                          tooltipPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (touched) => [
                            for (final s in touched)
                              LineTooltipItem(
                                '${s.x.toStringAsFixed(2)} ${unit.distanceLabel}\n',
                                TextStyle(
                                  color: cx.textDim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                children: [
                                  TextSpan(
                                    text: '${s.y.toStringAsFixed(0)} '
                                        '${unit.speedLabel}',
                                    style: TextStyle(
                                      color: cx.textBright,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        getTouchedSpotIndicator: (bar, indices) => [
                          for (final _ in indices)
                            TouchedSpotIndicatorData(
                              FlLine(color: cx.accentInk, strokeWidth: 1.5),
                              FlDotData(
                                show: true,
                                getDotPainter: (spot, a, b, c) =>
                                    FlDotCirclePainter(
                                  radius: 4,
                                  color: cx.accent,
                                  strokeWidth: 2,
                                  strokeColor: cx.canvas,
                                ),
                              ),
                            ),
                        ],
                      )
                    : const LineTouchData(enabled: false),
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
                      checkToShowDot: (spot, _) => isKey(spot),
                      getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                        radius: 3.5,
                        color: cx.accent,
                        strokeWidth: 4,
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

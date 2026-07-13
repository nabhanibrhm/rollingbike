import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/units.dart';
import '../theme/app_theme.dart';

/// Minimal speed-vs-distance line chart matching the design mockup: a black
/// canvas with only an L-shaped pair of amber axes and a single thin, smooth
/// amber line. The only reference values ("legend") are three per axis —
/// SPEED shows `0 / avg / max`, DISTANCE shows `0 / half / total` — placed at
/// their exact positions rather than on an evenly-spaced grid.
///
/// [spots] are `FlSpot(distanceKm, speedKmh)` (metric — the shape is unaffected
/// by the display unit; only the tick labels are converted). [avgSpeedKmh] is
/// the ride's average (distance/time), which can't be derived from the samples
/// alone. Long series are downsampled to [maxPoints] for smooth live redraws.
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
  final double avgSpeedKmh;
  final SpeedUnit unit;
  final int maxPoints;

  /// When true, touching/dragging along the line snaps to the nearest data
  /// point and shows a tooltip with that point's distance + speed. Off for the
  /// live ride chart (no one pokes it mid-ride); on for the saved-ride detail.
  final bool interactive;

  // Gutters around the plot: room for the axis-name + tick labels.
  static const double _gutterLeft = 46;
  static const double _gutterBottom = 26;
  static const double _gutterTop = 30;
  static const double _gutterRight = 84;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final data = _downsample(spots, maxPoints);
    final maxSpeed = data.fold(0.0, (m, s) => math.max(m, s.y));
    final totalDist = data.isNotEmpty ? data.last.x : 0.0;
    final maxY = maxSpeed <= 0 ? 1.0 : maxSpeed;
    final maxX = totalDist <= 0 ? 1.0 : totalDist;

    final tickStyle = TextStyle(color: cx.textDim, fontSize: 11);
    final nameStyle = TextStyle(
      color: cx.textBright,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final chartLeft = _gutterLeft;
          final chartTop = _gutterTop;
          final chartW = math.max(1.0, c.maxWidth - _gutterLeft - _gutterRight);
          final chartH =
              math.max(1.0, c.maxHeight - _gutterTop - _gutterBottom);
          final chartBottom = chartTop + chartH;
          double yPix(double v) => chartTop + chartH * (1 - v / maxY);
          double xPix(double v) => chartLeft + chartW * (v / maxX);

          // SPEED: 0 / avg / max (avg only if it's a sane in-range value).
          final yTicks = <double>{0, maxSpeed};
          if (avgSpeedKmh > 0 && avgSpeedKmh < maxSpeed) yTicks.add(avgSpeedKmh);
          // DISTANCE: 0 / half / total.
          final xTicks = <double>[0, totalDist / 2, totalDist];

          return Stack(
            children: [
              Positioned(
                left: chartLeft,
                top: chartTop,
                width: chartW,
                height: chartH,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: maxX,
                    minY: 0,
                    maxY: maxY,
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        left: BorderSide(color: cx.accentInk, width: 3),
                        bottom: BorderSide(color: cx.accentInk, width: 3),
                      ),
                    ),
                    lineTouchData: interactive
                        ? LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => cx.surface,
                              tooltipRoundedRadius: 8,
                              tooltipBorder:
                                  BorderSide(color: cx.accentInk, width: 1),
                              tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItems: (touched) => [
                                for (final s in touched)
                                  LineTooltipItem(
                                    '${unit.distanceKm(s.x).toStringAsFixed(2)} '
                                    '${unit.distanceLabel}\n',
                                    TextStyle(
                                      color: cx.textDim,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    children: [
                                      TextSpan(
                                        text:
                                            '${unit.speed(s.y).toStringAsFixed(0)} '
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
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
              // SPEED tick labels — right-aligned in the left gutter.
              for (final v in yTicks)
                Positioned(
                  left: 0,
                  width: _gutterLeft - 8,
                  top: yPix(v) - 8,
                  child: Text(
                    unit.speed(v).toStringAsFixed(0),
                    textAlign: TextAlign.right,
                    style: tickStyle,
                  ),
                ),
              // DISTANCE tick labels — centered under the x-axis.
              for (final v in xTicks)
                Positioned(
                  left: xPix(v) - 26,
                  width: 52,
                  top: chartBottom + 5,
                  child: Text(
                    unit.distanceKm(v).toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: tickStyle,
                  ),
                ),
              Positioned(left: 0, top: 0, child: Text('SPEED', style: nameStyle)),
              Positioned(
                right: 0,
                bottom: 0,
                child: Text('DISTANCE', style: nameStyle),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Uniformly thins [spots] to at most [max] points, always keeping the first
  /// and last, so a long ride stays cheap to redraw without changing its shape.
  static List<FlSpot> _downsample(List<FlSpot> spots, int max) {
    if (spots.length <= max) return spots;
    final stride = spots.length / max;
    final out = <FlSpot>[];
    for (var i = 0; i < max; i++) {
      out.add(spots[(i * stride).floor()]);
    }
    out.add(spots.last);
    return out;
  }
}

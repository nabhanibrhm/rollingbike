import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/units.dart';
import '../data/models/track_point.dart';
import '../theme/app_theme.dart';

/// Speed-zone distribution donut: buckets the ride's time into speed ranges and
/// shows the share of time spent in each — a quick read on the trip's nature
/// (slow commute vs highway run).
///
/// Time is attributed by summing the interval between consecutive [points] into
/// the bucket of that interval's mean speed. Each interval is capped at
/// [_maxSegmentSeconds] so a pause or GPS blackout gap can't dump minutes of
/// phantom time into the slowest zone. Zone edges are unit-aware (round numbers
/// in km/h or mph); speeds convert to the display unit before bucketing, and the
/// donut centre + percentages reconcile against the summed bucket total.
class SpeedZoneChart extends StatelessWidget {
  const SpeedZoneChart({super.key, required this.points, required this.unit});

  final List<TrackPoint> points;
  final SpeedUnit unit;

  /// Cap on a single inter-fix interval (seconds) — longer gaps are pauses or
  /// blackouts, not steady riding, so they're clamped to not skew the mix.
  static const double _maxSegmentSeconds = 10.0;

  /// Zone colours, slowest → fastest (blue → green → amber → red). Fixed hues so
  /// the meaning stays stable across the light/dark themes.
  static const List<Color> _zoneColors = [
    Color(0xFF3B82F6), // blue
    Color(0xFF22C55E), // green
    Color(0xFFF59E0B), // amber
    Color(0xFFEF4444), // red
  ];

  /// Upper edges of the first three zones, in the display unit (the 4th is
  /// open-ended above the last edge).
  List<double> get _edges =>
      unit == SpeedUnit.mph ? const [20, 40, 60] : const [30, 60, 90];

  List<String> get _labels => unit == SpeedUnit.mph
      ? const ['0 – 20', '20 – 40', '40 – 60', '60+']
      : const ['0 – 30', '30 – 60', '60 – 90', '90+'];

  /// Seconds spent in each of the four zones.
  List<double> _computeSeconds() {
    final secs = <double>[0, 0, 0, 0];
    for (var i = 1; i < points.length; i++) {
      var dt =
          points[i].timestamp.difference(points[i - 1].timestamp).inMilliseconds /
              1000.0;
      if (dt <= 0) continue;
      if (dt > _maxSegmentSeconds) dt = _maxSegmentSeconds;
      final meanKmh = (points[i - 1].speedMps + points[i].speedMps) / 2 * 3.6;
      final v = unit.speed(meanKmh);
      final zone = v < _edges[0]
          ? 0
          : v < _edges[1]
              ? 1
              : v < _edges[2]
                  ? 2
                  : 3;
      secs[zone] += dt;
    }
    return secs;
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final secs = _computeSeconds();
    final total = secs.fold(0.0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();

    final sections = <PieChartSectionData>[
      for (var i = 0; i < 4; i++)
        if (secs[i] > 0)
          PieChartSectionData(
            value: secs[i],
            color: _zoneColors[i],
            radius: 30,
            title: '${(secs[i] / total * 100).toStringAsFixed(1)}%',
            showTitle: secs[i] / total >= 0.05,
            titleStyle: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
    ];

    return Container(
      width: double.infinity,
      color: cx.canvas,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPEED ZONE DISTRIBUTION',
            style: TextStyle(
              color: cx.textBright,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Share of time in each speed range',
            style: TextStyle(color: cx.textDim, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 172,
              height: 172,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 46,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TOTAL',
                        style: TextStyle(
                          color: cx.textDim,
                          fontSize: 10,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtDuration(total.round()),
                        style: TextStyle(
                          color: cx.textBright,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          // Legend table: zone · time · %.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Speed Zone (${unit.speedLabel})',
                  style: TextStyle(color: cx.textDim, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  'Time',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: cx.textDim, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '%',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: cx.textDim, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < 4; i++)
            _LegendRow(
              color: _zoneColors[i],
              label: _labels[i],
              seconds: secs[i].round(),
              pct: secs[i] / total * 100,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(height: 1, color: cx.border),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    color: cx.textBright,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  _fmtDuration(total.round()),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: cx.textBright,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '100%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: cx.textBright,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One legend line: a colour dot + zone label, its time, and its share.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.seconds,
    required this.pct,
  });

  final Color color;
  final String label;
  final int seconds;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(color: cx.textBright, fontSize: 13),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              _fmtDuration(seconds),
              textAlign: TextAlign.right,
              style: TextStyle(color: cx.textBright, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${pct.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(color: cx.textDim, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

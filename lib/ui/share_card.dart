import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/speed_palette.dart';
import '../core/units.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';

/// The four shareable card layouts the rider can pick between before exporting.
/// All render on a fully transparent canvas (no background panel or map tiles)
/// so the sticker drops cleanly onto a photo/video or saves as a transparent
/// PNG. Every layout carries the same data in a different composition.
enum ShareLayout {
  /// Route on the left, a 2-column stat grid (incl. moving time + pace) on the
  /// right, brand mark below.
  split('Split', 'Route beside a full stat grid'),

  /// Route centred on top, a single row of four key stats beneath, brand below.
  stacked('Stacked', 'Route above a row of stats'),

  /// A 2×2 stat grid on top, route beneath, brand mark below.
  statsTop('Stats first', 'Stats above the route'),

  /// Speed-coloured route (with a legend) on the left, a slim stat column on
  /// the right, brand below.
  speed('Speed map', 'Route coloured by speed');

  const ShareLayout(this.title, this.blurb);

  final String title;
  final String blurb;
}

/// A shareable ride card, rendered off-screen into a 9:16 PNG (see
/// [captureWidgetToPng]).
///
/// Styled after Strava's share sticker: a fully transparent canvas with the
/// route line and stats floating directly on it (no map tiles — RollingBike is
/// offline-first, so the route is a vector polyline — and no background panel,
/// so nothing blocks a photo/video placed behind it), in RollingBike's amber
/// brand palette. Every piece of text carries a dark drop shadow (in place of a
/// solid panel) so it stays legible over whatever ends up behind it.
///
/// It's deliberately independent of the app's light/dark theme: the shared image
/// always uses the dark amber brand look so it reads the same for everyone.
/// Speeds and distances still honour the rider's [unit] choice.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.ride,
    required this.points,
    required this.unit,
    this.layout = ShareLayout.split,
  });

  final Ride ride;
  final List<TrackPoint> points;
  final SpeedUnit unit;
  final ShareLayout layout;

  /// Bundled brand mark — clean amber speedometer on transparent. Precached
  /// before capture (the render only waits a couple of frames).
  static const brandLogo = AssetImage('assets/icon/logo_foreground.png');

  // Brand colours, fixed for the shared artwork.
  static const _amber = Color(0xFFFFB22C);
  static const _red = Color(0xFFEF4444);
  static const _ink = Color(0xFFF2F2F0);
  static const _dim = Color(0xFFD8D8D8);

  /// Stands in for a background panel: keeps text readable over an arbitrary
  /// photo/video the rider places behind this transparent sticker.
  static const _textShadow = [
    Shadow(color: Color(0xE6000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

  @override
  Widget build(BuildContext context) {
    final content = switch (layout) {
      ShareLayout.split => _buildSplit(),
      ShareLayout.stacked => _buildStacked(),
      ShareLayout.statsTop => _buildStatsTop(),
      ShareLayout.speed => _buildSpeed(),
    };

    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Inter',
        color: _ink,
        shadows: _textShadow,
      ),
      child: SizedBox(
        width: 360,
        height: 640,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: content,
          ),
        ),
      ),
    );
  }

  // --- Layouts --------------------------------------------------------------

  Widget _buildSplit() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _route(width: 104, height: 210),
              const SizedBox(width: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _stat('DISTANCE', _distance, unitLabel: _dLabel, width: 92),
                      const SizedBox(height: 14),
                      _stat('TOTAL TIME', _totalTime, width: 92),
                      const SizedBox(height: 14),
                      _stat('MOVING TIME', _movingTime, width: 92),
                    ],
                  ),
                  const SizedBox(width: 18),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _stat('AVG SPEED', _avg, unitLabel: _sLabel, width: 92),
                      const SizedBox(height: 14),
                      _stat('MAX SPEED', _max,
                          unitLabel: _sLabel, color: _red, width: 92),
                      const SizedBox(height: 14),
                      _stat('PACE', _pace, unitLabel: '/$_dLabel', width: 92),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _brand(column: false, showName: true),
      ],
    );
  }

  Widget _buildStacked() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _route(width: 210, height: 240),
        const SizedBox(height: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stat('DISTANCE', _distance, unitLabel: _dLabel, valueSize: 18),
              const SizedBox(width: 18),
              _stat('TOTAL TIME', _totalTime, valueSize: 18),
              const SizedBox(width: 18),
              _stat('AVG SPEED', _avg, unitLabel: _sLabel, valueSize: 18),
              const SizedBox(width: 18),
              _stat('MAX SPEED', _max,
                  unitLabel: _sLabel, color: _red, valueSize: 18),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _brand(column: true, showName: true),
      ],
    );
  }

  Widget _buildStatsTop() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stat('TOTAL TIME', _totalTime, width: 120, valueSize: 24),
                const SizedBox(width: 24),
                _stat('DISTANCE', _distance,
                    unitLabel: _dLabel, width: 120, valueSize: 24),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stat('AVG SPEED', _avg,
                    unitLabel: _sLabel, width: 120, valueSize: 24),
                const SizedBox(width: 24),
                _stat('MAX SPEED', _max,
                    unitLabel: _sLabel, color: _red, width: 120, valueSize: 24),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _route(width: 190, height: 220),
        const SizedBox(height: 14),
        _brand(column: true, showName: false),
      ],
    );
  }

  Widget _buildSpeed() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _speedLegend(),
                  const SizedBox(height: 6),
                  _route(width: 116, height: 240, colorBySpeed: true),
                ],
              ),
              const SizedBox(width: 24),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stat('DISTANCE', _distance,
                      unitLabel: _dLabel, valueSize: 24, width: 132),
                  const SizedBox(height: 14),
                  _stat('AVG SPEED', _avg,
                      unitLabel: _sLabel, valueSize: 24, width: 132),
                  const SizedBox(height: 14),
                  _stat('MAX SPEED', _max,
                      unitLabel: _sLabel,
                      color: _red,
                      valueSize: 24,
                      width: 132),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _brand(column: true, showName: true),
      ],
    );
  }

  // --- Shared pieces --------------------------------------------------------

  String get _distance =>
      unit.distanceMeters(ride.totalDistanceMeters).toStringAsFixed(2);
  String get _totalTime => _fmtDuration(ride.durationSeconds);
  String get _movingTime => _fmtDuration(ride.movingSeconds);
  String get _avg => unit.speed(ride.averageSpeedKmh).toStringAsFixed(0);
  String get _max => unit.speed(ride.maxSpeedKmh).toStringAsFixed(0);
  String get _pace =>
      _fmtPace(ride.movingSeconds, unit.distanceMeters(ride.totalDistanceMeters));
  String get _dLabel => unit.distanceLabel;
  String get _sLabel => unit.speedLabel.toUpperCase();

  Widget _route({
    required double width,
    required double height,
    bool colorBySpeed = false,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _RoutePainter(
          points,
          colorBySpeed: colorBySpeed,
          maxSpeedKmh: ride.maxSpeedKmh,
        ),
      ),
    );
  }

  Widget _stat(
    String label,
    String value, {
    String unitLabel = '',
    Color color = _amber,
    double valueSize = 20,
    double? width,
  }) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: _dim, fontSize: 11, letterSpacing: 0.3),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            text: value,
            style: TextStyle(
              fontFamily: 'Inter',
              color: color,
              fontSize: valueSize,
              fontWeight: FontWeight.w800,
              shadows: _textShadow,
            ),
            children: [
              if (unitLabel.isNotEmpty)
                TextSpan(
                  text: ' $unitLabel',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: _dim,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    shadows: _textShadow,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return width == null ? child : SizedBox(width: width, child: child);
  }

  Widget _speedLegend() {
    final maxDisp = unit.speed(ride.maxSpeedKmh).toStringAsFixed(0);
    final labelStyle = const TextStyle(
      color: _ink,
      fontSize: 8,
      fontWeight: FontWeight.w600,
      shadows: _textShadow,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPEED',
            style: TextStyle(
              color: _dim,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              shadows: _textShadow,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 96,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                colors: SpeedPalette.gradient,
                stops: SpeedPalette.gradientStops,
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0', style: labelStyle),
                Text('$maxDisp $_sLabel', style: labelStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand({required bool column, required bool showName}) {
    const logo = Image(
      image: brandLogo,
      width: 46,
      height: 46,
      filterQuality: FilterQuality.medium,
    );
    if (!showName) return logo;
    const name = Text(
      'ROLLINGBIKE',
      style: TextStyle(
        color: _ink,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        shadows: _textShadow,
      ),
    );
    return column
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: const [logo, SizedBox(height: 8), name],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: const [logo, SizedBox(width: 12), name],
          );
  }
}

/// Draws the recorded track as a vector polyline, normalised to fit the box
/// (equirectangular projection, aspect-preserved), with start/end dots. When
/// [colorBySpeed] is set, each segment is coloured by its mean ground speed via
/// [SpeedPalette] instead of the flat amber line.
class _RoutePainter extends CustomPainter {
  _RoutePainter(
    this.points, {
    this.colorBySpeed = false,
    this.maxSpeedKmh = 0,
  });

  final List<TrackPoint> points;
  final bool colorBySpeed;
  final double maxSpeedKmh;

  static const _amber = Color(0xFFFFB22C);
  static const _red = Color(0xFFEF4444);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      if (points.length == 1) {
        canvas.drawCircle(
            size.center(Offset.zero), 4, Paint()..color = _amber);
      }
      return;
    }

    // Project lat/lon to a local metric-ish plane (equirectangular).
    final midLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final kx = math.cos(midLat * math.pi / 180.0);
    final proj = [
      for (final p in points) Offset(p.longitude * kx, -p.latitude),
    ];

    var minX = proj.first.dx, maxX = proj.first.dx;
    var minY = proj.first.dy, maxY = proj.first.dy;
    for (final o in proj) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }

    const pad = 10.0;
    final spanX = (maxX - minX);
    final spanY = (maxY - minY);
    final availW = size.width - pad * 2;
    final availH = size.height - pad * 2;
    // Uniform scale to preserve the route's true shape; guard zero spans.
    final scale = math.min(
      spanX > 0 ? availW / spanX : double.infinity,
      spanY > 0 ? availH / spanY : double.infinity,
    );
    final safeScale = scale.isFinite ? scale : 1.0;

    // Centre the scaled path in the box.
    final drawnW = spanX * safeScale;
    final drawnH = spanY * safeScale;
    final offsetX = pad + (availW - drawnW) / 2;
    final offsetY = pad + (availH - drawnH) / 2;

    Offset map(Offset o) => Offset(
          offsetX + (o.dx - minX) * safeScale,
          offsetY + (o.dy - minY) * safeScale,
        );

    final mapped = [for (final o in proj) map(o)];

    if (colorBySpeed) {
      _paintSpeedColored(canvas, mapped);
    } else {
      _paintAmber(canvas, mapped);
    }

    // Start (amber) and end (red) dots.
    _dot(canvas, mapped.first, _amber);
    _dot(canvas, mapped.last, _red);
  }

  void _paintAmber(Canvas canvas, List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    // Soft glow under the line.
    canvas.drawPath(
      path,
      Paint()
        ..color = _amber.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintSpeedColored(Canvas canvas, List<Offset> pts) {
    final maxS = maxSpeedKmh <= 0 ? 1.0 : maxSpeedKmh;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < pts.length; i++) {
      final meanKmh =
          (points[i - 1].speedMps + points[i].speedMps) / 2 * 3.6;
      final t = (meanKmh / maxS).clamp(0.0, 1.0);
      canvas.drawLine(
        pts[i - 1],
        pts[i],
        base..color = SpeedPalette.at(t),
      );
    }
  }

  void _dot(Canvas canvas, Offset c, Color color) {
    canvas.drawCircle(c, 6, Paint()..color = color);
    canvas.drawCircle(
        c,
        6,
        Paint()
          ..color = const Color(0xFF0A0A0A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.colorBySpeed != colorBySpeed ||
      oldDelegate.maxSpeedKmh != maxSpeedKmh;
}

String _fmtDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Pace in minutes:seconds per displayed distance unit (km or mi), based on
/// moving time (so stops don't drag it down). '--:--' when there's not enough
/// distance to be meaningful.
String _fmtPace(int movingSeconds, double displayDistance) {
  if (displayDistance < 0.05 || movingSeconds <= 0) return '--:--';
  final secPerUnit = movingSeconds / displayDistance;
  if (!secPerUnit.isFinite) return '--:--';
  var mm = secPerUnit ~/ 60;
  var ss = (secPerUnit % 60).round();
  if (ss == 60) {
    ss = 0;
    mm += 1;
  }
  return '$mm:${ss.toString().padLeft(2, '0')}';
}

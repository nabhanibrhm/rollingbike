import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models/ride.dart';
import '../data/models/track_point.dart';

/// The shareable ride card, rendered off-screen into a 9:16 PNG (see
/// [captureWidgetToPng]) for Instagram Stories.
///
/// Styled after Strava's share image: a fully transparent canvas with the
/// route line and stats floating directly on it (no map tiles — RollingBike
/// is offline-first, so the route is drawn as a vector polyline instead; no
/// background panel either — like Strava's sticker, nothing here should block
/// a photo or video the rider places behind it in Instagram), in
/// RollingBike's own mint/coral brand palette rather than Strava's orange.
///
/// Every piece of text carries a dark drop shadow (in place of a solid panel)
/// so it stays legible over whatever ends up behind the sticker.
///
/// It is deliberately styled independently of the app's light/dark theme: the
/// shared image always uses the dark neon brand look so it reads the same for
/// everyone, whatever theme the sharer happens to be in.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.ride, required this.points});

  final Ride ride;
  final List<TrackPoint> points;

  // Brand colours, fixed for the shared artwork.
  static const _mint = Color(0xFF83FFE6);
  static const _coral = Color(0xFFFF5F5F);
  static const _ink = Color(0xFFFCFCFC);
  static const _dim = Color(0xFFD8D8D8);

  /// Stands in for a background panel: keeps text readable over an arbitrary
  /// photo/video the rider places behind this transparent sticker.
  static const _textShadow = [
    Shadow(color: Color(0xE6000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

  @override
  Widget build(BuildContext context) {
    final title = ride.name?.trim().isNotEmpty == true
        ? ride.name!.trim()
        : 'Untitled ride';
    final pace = _fmtPace(ride.movingSeconds, ride.totalDistanceMeters);

    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'JetBrainsMono',
        color: _ink,
        shadows: _textShadow,
      ),
      child: SizedBox(
        width: 360,
        height: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand header.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler,
                      color: _mint, size: 20, shadows: _textShadow),
                  const SizedBox(width: 8),
                  const Text(
                    'RollingBike',
                    style: TextStyle(
                      color: _mint,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(ride.startTime),
                    style: const TextStyle(color: _dim, fontSize: 11),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 24,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Hero route line (vector, no map tiles) — fills whatever space
            // is left above the stats.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: SizedBox.expand(
                  child: CustomPaint(painter: _RoutePainter(points)),
                ),
              ),
            ),
            _StatsPanel(ride: ride, pace: pace),
          ],
        ),
      ),
    );
  }
}

/// Bottom stat block. No background of its own — the stats float directly on
/// the transparent canvas, same as Strava's sticker, relying on
/// [ShareCard._textShadow] rather than a panel for legibility.
class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.ride, required this.pace});

  final Ride ride;
  final String pace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Stat(
                  label: 'DISTANCE',
                  value: (ride.totalDistanceMeters / 1000).toStringAsFixed(2),
                  unit: 'km'),
              _Stat(
                  label: 'TOTAL TIME',
                  value: _fmtDuration(ride.durationSeconds)),
              _Stat(
                  label: 'MOVING TIME',
                  value: _fmtDuration(ride.movingSeconds)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(
                  label: 'AVG SPEED',
                  value: ride.averageSpeedKmh.toStringAsFixed(0),
                  unit: 'km/h'),
              _Stat(
                  label: 'MAX SPEED',
                  value: ride.maxSpeedKmh.toStringAsFixed(0),
                  unit: 'km/h',
                  color: ShareCard._coral),
              _Stat(label: 'PACE', value: pace, unit: '/km'),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'RollingBike · offline telemetry',
            style: TextStyle(color: ShareCard._dim, fontSize: 9, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.unit = '',
    this.color = ShareCard._mint,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: ShareCard._dim, fontSize: 10)),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text: value,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                shadows: ShareCard._textShadow,
              ),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: ShareCard._dim,
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      shadows: ShareCard._textShadow,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the recorded track as a vector polyline, normalised to fit the box
/// (equirectangular projection, aspect-preserved), with start/end dots.
class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points);

  final List<TrackPoint> points;

  static const _mint = Color(0xFF83FFE6);
  static const _coral = Color(0xFFFF5F5F);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      // Nothing meaningful to draw — leave a subtle centred dot if we have one.
      if (points.length == 1) {
        canvas.drawCircle(size.center(Offset.zero), 4,
            Paint()..color = _mint);
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

    const pad = 18.0;
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

    final path = Path()..moveTo(map(proj.first).dx, map(proj.first).dy);
    for (final o in proj.skip(1)) {
      final m = map(o);
      path.lineTo(m.dx, m.dy);
    }

    // Soft glow under the line.
    canvas.drawPath(
      path,
      Paint()
        ..color = _mint.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _mint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Start (mint) and end (coral) dots.
    _dot(canvas, map(proj.first), _mint);
    _dot(canvas, map(proj.last), _coral);
  }

  void _dot(Canvas canvas, Offset c, Color color) {
    canvas.drawCircle(c, 6, Paint()..color = color);
    canvas.drawCircle(
        c,
        6,
        Paint()
          ..color = const Color(0xFF0A0F0E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points != points;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${_months[local.month - 1]} ${local.day}, ${local.year} · $hh:$mm';
}

String _fmtDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Pace in minutes:seconds per kilometer, based on moving time (so stops
/// don't drag it down). '--:--' when there's not enough distance to be
/// meaningful.
String _fmtPace(int movingSeconds, double distanceMeters) {
  final km = distanceMeters / 1000.0;
  if (km < 0.05 || movingSeconds <= 0) return '--:--';
  final secPerKm = movingSeconds / km;
  if (!secPerKm.isFinite) return '--:--';
  var mm = secPerKm ~/ 60;
  var ss = (secPerKm % 60).round();
  if (ss == 60) {
    ss = 0;
    mm += 1;
  }
  return '$mm:${ss.toString().padLeft(2, '0')}';
}

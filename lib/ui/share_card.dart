import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models/ride.dart';
import '../data/models/track_point.dart';

/// The shareable ride card, rendered off-screen into a 9:16 PNG (see
/// [captureWidgetToPng]) for Instagram Stories.
///
/// The canvas itself is transparent — only the centred card is opaque — so the
/// PNG carries an 8-bit alpha channel and sits as an interactive sticker over
/// Instagram's Story background gradient.
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
  static const _dim = Color(0xFFA1A1A1);
  static const _cardTop = Color(0xFF1C2A27);
  static const _cardBottom = Color(0xFF0E1413);

  @override
  Widget build(BuildContext context) {
    final title = ride.name?.trim().isNotEmpty == true
        ? ride.name!.trim()
        : 'Untitled ride';

    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'JetBrainsMono', color: _ink),
      child: Center(
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_cardTop, _cardBottom],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _mint.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: _mint.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand header.
              Row(
                children: [
                  const Icon(Icons.two_wheeler, color: _mint, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'RollingBike',
                    style: TextStyle(
                      color: _mint,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Route map (vector path — no tiles, works offline).
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 176,
                  width: double.infinity,
                  color: const Color(0xFF0A0F0E),
                  child: CustomPaint(
                    painter: _RoutePainter(points),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(ride.startTime),
                style: const TextStyle(color: _dim, fontSize: 12),
              ),
              const SizedBox(height: 18),
              // Distance hero.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    (ride.totalDistanceMeters / 1000).toStringAsFixed(2),
                    style: const TextStyle(
                      color: _mint,
                      fontSize: 52,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('km',
                        style: TextStyle(color: _dim, fontSize: 18)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _Stat(label: 'TIME', value: _fmtDuration(ride.durationSeconds)),
                  _Stat(
                      label: 'AVG',
                      value: ride.averageSpeedKmh.toStringAsFixed(0),
                      unit: 'km/h'),
                  _Stat(
                      label: 'MAX',
                      value: ride.maxSpeedKmh.toStringAsFixed(0),
                      unit: 'km/h',
                      color: _coral),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFF243430), height: 1),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'RollingBike · offline telemetry',
                  style: TextStyle(
                      color: _dim, fontSize: 10, letterSpacing: 2),
                ),
              ),
            ],
          ),
        ),
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

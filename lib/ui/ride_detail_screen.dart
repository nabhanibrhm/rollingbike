import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/units.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';
import '../providers/history_providers.dart';
import '../providers/settings_providers.dart';
import '../services/ride_share.dart';
import '../theme/app_theme.dart';
import 'speed_distance_chart.dart';
import 'tracking_map_screen.dart' show basemapUrl;

/// The two ways a rendered ride card can be sent off.
enum _ShareAction { instagram, download }

/// A row in the share sheet: an amber icon in a rounded square + a label.
class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cx.canvas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cx.accentInk, size: 18),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: cx.textBright,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Detail view for a saved ride: the recorded track replayed as a polyline on
/// the map, with the full summary stats below.
class RideDetailScreen extends ConsumerStatefulWidget {
  const RideDetailScreen({super.key, required this.ride});

  final Ride ride;

  static const LatLng _fallbackCenter = LatLng(-6.2088, 106.8456); // Jakarta

  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen> {
  bool _sharing = false;

  /// Lets the rider pick Instagram or a plain PNG download, renders the ride
  /// card, and dispatches it accordingly. Guarded so it only fires once the
  /// track has loaded and never re-enters while a render/share is in flight.
  Future<void> _share() async {
    if (_sharing) return;
    final points = ref.read(rideTrackProvider(widget.ride.id)).valueOrNull;
    if (points == null) return; // track still loading — button is disabled
    final action = await _showShareOptions();
    if (action == null || !mounted) return;
    final unit = ref.read(speedUnitProvider);

    setState(() => _sharing = true);
    try {
      if (action == _ShareAction.instagram) {
        await RideShare.shareToInstagram(
          context: context,
          ride: widget.ride,
          points: points,
          unit: unit,
        );
      } else {
        await RideShare.saveToGallery(
          context: context,
          ride: widget.ride,
          points: points,
          unit: unit,
        );
        if (mounted) _showMessage('Saved to your gallery.');
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        action == _ShareAction.instagram
            ? "Couldn't share this ride. Try again."
            : "Couldn't save the image. Try again.",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<_ShareAction?> _showShareOptions() {
    final cx = AppColors.of(context);
    return showDialog<_ShareAction>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: cx.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share ride',
                  style: TextStyle(
                      color: cx.textBright,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              _ShareOption(
                icon: Icons.camera_alt,
                label: 'Share to Instagram',
                onTap: () => Navigator.of(ctx).pop(_ShareAction.instagram),
              ),
              _ShareOption(
                icon: Icons.download,
                label: 'Download as PNG',
                onTap: () => Navigator.of(ctx).pop(_ShareAction.download),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: cx.textDim)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    final cx = AppColors.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: cx.surface,
          content: Text(message,
              style: TextStyle(color: isError ? cx.dangerInk : cx.textBright)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final trackAsync = ref.watch(rideTrackProvider(widget.ride.id));
    final title = widget.ride.name?.trim().isNotEmpty == true
        ? widget.ride.name!.trim()
        : 'Untitled ride';

    return Scaffold(
      backgroundColor: cx.canvas,
      appBar: AppBar(
        backgroundColor: cx.canvas,
        foregroundColor: cx.textBright,
        elevation: 0,
        centerTitle: true,
        shape: Border(bottom: BorderSide(color: cx.border)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (_sharing)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: cx.accentInk),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share ride',
              onPressed: trackAsync.hasValue ? _share : null,
            ),
        ],
      ),
      body: Column(
        children: [
          // Fixed map header (mockup), then the stats scroll beneath it.
          SizedBox(
            height: 320,
            child: trackAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: cx.accentInk),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Could not load track:\n$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cx.dangerInk),
                ),
              ),
              data: (points) => _RouteMap(points: points),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _SummaryPanel(
                    ride: widget.ride,
                    unit: ref.watch(speedUnitProvider),
                  ),
                  // Speed-vs-distance chart from the recorded track (needs at
                  // least two points to plot a line).
                  if ((trackAsync.valueOrNull?.length ?? 0) >= 2)
                    _RideChart(
                      points: trackAsync.value!,
                      avgSpeedKmh: widget.ride.averageSpeedKmh,
                      unit: ref.watch(speedUnitProvider),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The map with the recorded route + start/end markers. Falls back to a
/// message when the ride has no recorded fixes.
class _RouteMap extends StatelessWidget {
  const _RouteMap({required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final route = [for (final p in points) LatLng(p.latitude, p.longitude)];

    if (route.isEmpty) {
      return Stack(
        children: [
          const _BaseMap(center: RideDetailScreen._fallbackCenter),
          Container(
            color: cx.canvas.withValues(alpha: 0.5),
            alignment: Alignment.center,
            child: Text(
              'No track recorded for this ride',
              style: TextStyle(color: cx.textDim),
            ),
          ),
        ],
      );
    }

    return FlutterMap(
      options: MapOptions(
        backgroundColor: cx.canvas,
        initialCenter: route.first,
        initialZoom: 15,
        // Fit the whole recorded route in view. A single-point ride keeps the
        // initialCenter/zoom above (coordinates fit needs >= 2 to size).
        initialCameraFit: route.length >= 2
            ? CameraFit.coordinates(
                coordinates: route,
                padding: const EdgeInsets.all(48),
                maxZoom: 17,
              )
            : null,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: basemapUrl(cx.isDark),
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'id.co.opentrack.rollingbike',
          tileProvider: NetworkTileProvider(silenceExceptions: true),
        ),
        if (route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: route, strokeWidth: 5, color: cx.accentInk),
            ],
          ),
        MarkerLayer(
          markers: [
            _endpointMarker(route.first, cx.accent), // start
            if (route.length >= 2)
              _endpointMarker(route.last, cx.danger), // end
          ],
        ),
      ],
    );
  }

  Marker _endpointMarker(LatLng point, Color color) => Marker(
    point: point,
    width: 20,
    height: 20,
    child: Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
    ),
  );
}

/// Tile-only map used behind the "no track" message.
class _BaseMap extends StatelessWidget {
  const _BaseMap({required this.center});

  final LatLng center;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return FlutterMap(
      options: MapOptions(
        backgroundColor: cx.canvas,
        initialCenter: center,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: basemapUrl(cx.isDark),
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'id.co.opentrack.rollingbike',
          tileProvider: NetworkTileProvider(silenceExceptions: true),
        ),
      ],
    );
  }
}

/// Bottom stats panel — distance, elapsed vs moving time, avg/max speed.
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.ride, required this.unit});

  final Ride ride;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Container(
      width: double.infinity,
      color: cx.canvas,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDate(ride.startTime),
              style: TextStyle(color: cx.textDim, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  unit
                      .distanceMeters(ride.totalDistanceMeters)
                      .toStringAsFixed(2),
                  style: TextStyle(
                    color: cx.textBright,
                    fontSize: 44,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    unit.distanceLabel,
                    style: TextStyle(color: cx.textDim, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                _Stat(
                  label: 'TOTAL TIME',
                  value: _fmtDuration(ride.durationSeconds),
                ),
                _Stat(
                  label: 'MOVING TIME',
                  value: _fmtDuration(ride.movingSeconds),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _Stat(
                  label: 'AVG SPEED',
                  value: unit.speed(ride.averageSpeedKmh).toStringAsFixed(1),
                  unit: unit.speedLabel,
                ),
                _Stat(
                  label: 'MAX SPEED',
                  value: unit.speed(ride.maxSpeedKmh).toStringAsFixed(1),
                  unit: unit.speedLabel,
                  color: cx.danger,
                ),
              ],
            ),
          ],
        ),
    );
  }
}

/// Speed-vs-distance chart for a saved ride, built from its recorded track
/// points: cumulative Haversine distance on x, per-fix ground speed on y.
class _RideChart extends StatelessWidget {
  const _RideChart({
    required this.points,
    required this.avgSpeedKmh,
    required this.unit,
  });

  final List<TrackPoint> points;
  final double avgSpeedKmh;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final spots = <FlSpot>[];
    var distMeters = 0.0;
    for (var i = 0; i < points.length; i++) {
      if (i > 0) {
        distMeters += haversineMeters(
          points[i - 1].latitude,
          points[i - 1].longitude,
          points[i].latitude,
          points[i].longitude,
        );
      }
      spots.add(FlSpot(distMeters / 1000.0, points[i].speedMps * 3.6));
    }

    return Container(
      width: double.infinity,
      color: cx.canvas,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 260,
          child: SpeedDistanceChart(
            spots: spots,
            avgSpeedKmh: avgSpeedKmh,
            unit: unit,
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
    this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: cx.textDim, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color ?? cx.textBright,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(color: cx.textDim, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
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

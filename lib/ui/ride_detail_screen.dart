import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/ride.dart';
import '../data/models/track_point.dart';
import '../providers/history_providers.dart';
import '../theme/app_theme.dart';

/// Detail view for a saved ride: the recorded track replayed as a polyline on
/// the dark map, with the full summary stats below.
class RideDetailScreen extends ConsumerWidget {
  const RideDetailScreen({super.key, required this.ride});

  final Ride ride;

  static const LatLng _fallbackCenter = LatLng(-6.2088, 106.8456); // Jakarta

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackAsync = ref.watch(rideTrackProvider(ride.id));
    final title = ride.name?.trim().isNotEmpty == true
        ? ride.name!.trim()
        : 'Untitled ride';

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.textBright,
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Expanded(
            child: trackAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.cyan),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Could not load track:\n$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
              data: (points) => _RouteMap(points: points),
            ),
          ),
          _SummaryPanel(ride: ride),
        ],
      ),
    );
  }
}

/// The dark map with the recorded route + start/end markers. Falls back to a
/// message when the ride has no recorded fixes.
class _RouteMap extends StatelessWidget {
  const _RouteMap({required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final route = [for (final p in points) LatLng(p.latitude, p.longitude)];

    if (route.isEmpty) {
      return Stack(
        children: [
          const _BaseMap(center: RideDetailScreen._fallbackCenter),
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            alignment: Alignment.center,
            child: const Text(
              'No track recorded for this ride',
              style: TextStyle(color: AppColors.textDim),
            ),
          ),
        ],
      );
    }

    return FlutterMap(
      options: MapOptions(
        backgroundColor: AppColors.black,
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
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'id.co.smma.rollingbike',
          tileProvider: NetworkTileProvider(),
        ),
        if (route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: route, strokeWidth: 5, color: AppColors.cyan),
            ],
          ),
        MarkerLayer(
          markers: [
            _endpointMarker(route.first, AppColors.volt), // start
            if (route.length >= 2)
              _endpointMarker(route.last, AppColors.danger), // end
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
    return FlutterMap(
      options: MapOptions(
        backgroundColor: AppColors.black,
        initialCenter: center,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'id.co.smma.rollingbike',
          tileProvider: NetworkTileProvider(),
        ),
      ],
    );
  }
}

/// Bottom stats panel — distance, elapsed vs moving time, avg/max speed.
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.zinc,
        border: Border(top: BorderSide(color: AppColors.zincBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDate(ride.startTime),
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  (ride.totalDistanceMeters / 1000).toStringAsFixed(2),
                  style: const TextStyle(
                    color: AppColors.volt,
                    fontSize: 44,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'km',
                    style: TextStyle(color: AppColors.textDim, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                  label: 'AVG SPEED',
                  value: ride.averageSpeedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                ),
                _Stat(
                  label: 'MAX SPEED',
                  value: ride.maxSpeedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                  color: AppColors.volt,
                ),
              ],
            ),
          ],
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
    this.color = AppColors.cyan,
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
          Text(
            label,
            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
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

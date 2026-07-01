import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../providers/tracking_providers.dart';
import '../theme/app_theme.dart';

/// Full-screen dark map with a floating glassmorphic telemetry sheet — the
/// Gowez-style tracking screen.
class TrackingMapScreen extends ConsumerStatefulWidget {
  const TrackingMapScreen({super.key});

  @override
  ConsumerState<TrackingMapScreen> createState() => _TrackingMapScreenState();
}

class _TrackingMapScreenState extends ConsumerState<TrackingMapScreen> {
  final MapController _mapController = MapController();

  /// Fallback center until the first fix arrives (Jakarta).
  static const LatLng _fallbackCenter = LatLng(-6.2088, 106.8456);

  bool _mapReady = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingControllerProvider);

    // Follow the rider and surface permission errors.
    ref.listen<TrackingUiState>(trackingControllerProvider, (prev, next) {
      final t = next.telemetry;
      if (_mapReady && t?.lat != null && t?.lon != null) {
        _mapController.move(LatLng(t!.lat!, t.lon!), _mapController.camera.zoom);
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: AppColors.zinc,
              content: Text(next.error!,
                  style: const TextStyle(color: AppColors.danger)),
            ),
          );
      }
    });

    final current = _currentLatLng(state);

    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 16,
              backgroundColor: AppColors.black,
              onMapReady: () => _mapReady = true,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'id.co.smma.rollingbike',
                tileProvider: NetworkTileProvider(),
              ),
              if (state.route.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: state.route,
                      strokeWidth: 5,
                      color: AppColors.cyan,
                    ),
                  ],
                ),
              if (current != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: current,
                      width: 26,
                      height: 26,
                      child: const _RiderDot(),
                    ),
                  ],
                ),
            ],
          ),
          const _MapAttribution(),
          Align(
            alignment: Alignment.bottomCenter,
            child: _TelemetrySheet(
              state: state,
              onStart: () => ref.read(trackingControllerProvider.notifier).start(),
              onStop: () => ref.read(trackingControllerProvider.notifier).stop(),
            ),
          ),
        ],
      ),
    );
  }

  LatLng? _currentLatLng(TrackingUiState state) {
    final t = state.telemetry;
    if (t?.lat != null && t?.lon != null) return LatLng(t!.lat!, t.lon!);
    if (state.route.isNotEmpty) return state.route.last;
    return null;
  }
}

/// Glowing cyan position marker.
class _RiderDot extends StatelessWidget {
  const _RiderDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cyan,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.6),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

/// Required CartoDB / OpenStreetMap attribution, kept subtle in a corner.
class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: Colors.black.withValues(alpha: 0.4),
          child: const Text(
            '© OpenStreetMap · CARTO',
            style: TextStyle(color: AppColors.textDim, fontSize: 9),
          ),
        ),
      ),
    );
  }
}

/// Floating glassmorphic sheet showing live (or last-ride) telemetry + the
/// start/stop control.
class _TelemetrySheet extends StatelessWidget {
  const _TelemetrySheet({
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final TrackingUiState state;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final tracking = state.isTracking;
    // While tracking, show live telemetry; when stopped, show the last ride's
    // finalised summary if present.
    final t = tracking ? state.telemetry : (state.lastFinished ?? state.telemetry);
    final speedKmh = tracking ? (t?.speedKmh ?? 0) : 0.0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.zinc.withValues(alpha: 0.72),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: AppColors.cyan.withValues(alpha: 0.22)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.zincBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                // Hero speed.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      speedKmh.toStringAsFixed(0),
                      style: const TextStyle(
                        color: AppColors.volt,
                        fontSize: 72,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text('km/h',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 18)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _Metric(
                        label: 'DIST',
                        value:
                            ((t?.distanceMeters ?? 0) / 1000).toStringAsFixed(2),
                        unit: 'km'),
                    _Metric(
                        label: 'TIME',
                        value: _fmtDuration(t?.durationSeconds ?? 0),
                        unit: ''),
                    _Metric(
                        label: 'AVG',
                        value: (t?.avgSpeedKmh ?? 0).toStringAsFixed(1),
                        unit: 'km/h'),
                    _Metric(
                        label: 'MAX',
                        value: (t?.maxSpeedKmh ?? 0).toStringAsFixed(1),
                        unit: 'km/h',
                        color: AppColors.volt),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 68,
                  child: ElevatedButton(
                    onPressed: tracking ? onStop : onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          tracking ? AppColors.danger : AppColors.volt,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      tracking ? 'STOP RIDE' : 'START RIDE',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
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
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.w700)),
          if (unit.isNotEmpty)
            Text(unit,
                style: const TextStyle(color: AppColors.textDim, fontSize: 10)),
        ],
      ),
    );
  }
}

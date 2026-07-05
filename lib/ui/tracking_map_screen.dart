import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/tracking_providers.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'ride_summary_screen.dart';

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

  /// The rider's last known position while idle (before/without a ride), used
  /// to center the map on open and show a "you are here" marker.
  LatLng? _myLocation;
  bool _locating = false;

  /// Fetches the current position, centers the map on it, and drops the idle
  /// marker. Runs once the map is ready (app open) and on the locate button.
  Future<void> _locateMe({bool moveCamera = true}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final perm = await PermissionService.ensureForegroundLocation();
      if (!perm.granted) {
        if (mounted) _showError(perm.message);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = here);
      if (moveCamera && _mapReady) {
        _mapController.move(here, 16);
      }
    } catch (e) {
      if (mounted) _showError('Could not get your location. Try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.zinc,
          content: Text(message, style: const TextStyle(color: AppColors.danger)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingControllerProvider);

    // Follow the rider, present the post-ride summary, and surface errors.
    ref.listen<TrackingUiState>(trackingControllerProvider, (prev, next) {
      final t = next.telemetry;
      if (_mapReady && t?.lat != null && t?.lon != null) {
        _mapController.move(LatLng(t!.lat!, t.lon!), _mapController.camera.zoom);
      }
      // A ride just finished → open the summary screen once.
      if (next.lastFinished != null && prev?.lastFinished == null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                RideSummaryScreen(telemetry: next.lastFinished!),
          ),
        );
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
      drawer: const _AppDrawer(),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 16,
              backgroundColor: AppColors.black,
              onMapReady: () {
                _mapReady = true;
                // Center on the rider as soon as the map can accept moves.
                _locateMe();
              },
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
          const _MenuButton(),
          // Locate button sits just above the telemetry sheet (right-aligned)
          // so it's never hidden behind the sheet regardless of its height.
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 12),
                  child: _LocateButton(busy: _locating, onTap: _locateMe),
                ),
                _TelemetrySheet(
                  state: state,
                  onStart: () =>
                      ref.read(trackingControllerProvider.notifier).start(),
                  onStop: () =>
                      ref.read(trackingControllerProvider.notifier).stop(),
                  onPause: () =>
                      ref.read(trackingControllerProvider.notifier).pause(),
                  onResume: () =>
                      ref.read(trackingControllerProvider.notifier).resume(),
                ),
              ],
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
    return _myLocation; // idle: show where the rider is before a ride starts
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

/// Floating glass hamburger that opens the app drawer, mirroring the
/// attribution chip in the opposite corner.
class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      child: SafeArea(
        child: Builder(
          builder: (context) => ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Material(
                color: AppColors.zinc.withValues(alpha: 0.6),
                child: InkWell(
                  onTap: () => Scaffold.of(context).openDrawer(),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.22)),
                    ),
                    child: const Icon(Icons.menu, color: AppColors.textBright),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating "my location" button — re-fetches the current position and
/// re-centers the map. Shows a spinner while locating.
class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: AppColors.zinc.withValues(alpha: 0.72),
          child: InkWell(
            onTap: busy ? null : onTap,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: AppColors.cyan),
                    )
                  : const Icon(Icons.my_location, color: AppColors.cyan),
            ),
          ),
        ),
      ),
    );
  }
}

/// Side menu: ride history + exit.
class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.zinc,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text(
                'RollingBike',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            const Divider(color: AppColors.zincBorder, height: 1),
            ListTile(
              leading: const Icon(Icons.history, color: AppColors.textBright),
              title: const Text('History of trips',
                  style: TextStyle(color: AppColors.textBright)),
              onTap: () {
                Navigator.of(context).pop(); // close drawer
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.exit_to_app, color: AppColors.textBright),
              title: const Text('Exit',
                  style: TextStyle(color: AppColors.textBright)),
              onTap: () => SystemNavigator.pop(),
            ),
          ],
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
    required this.onPause,
    required this.onResume,
  });

  final TrackingUiState state;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final tracking = state.isTracking;
    final paused = state.isPaused;
    // While tracking, show live telemetry; when stopped, show the last ride's
    // finalised summary if present.
    final t = tracking ? state.telemetry : (state.lastFinished ?? state.telemetry);
    final speedKmh = (tracking && !paused) ? (t?.speedKmh ?? 0) : 0.0;

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
                if (paused) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.5)),
                    ),
                    child: const Text(
                      'PAUSED',
                      style: TextStyle(
                          color: AppColors.cyan,
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
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
                if (!tracking)
                  _SheetButton(
                    label: 'START RIDE',
                    color: AppColors.volt,
                    onPressed: onStart,
                  )
                else
                  Row(
                    children: [
                      // Pause ↔ Resume.
                      Expanded(
                        child: _SheetButton(
                          label: paused ? 'RESUME' : 'PAUSE',
                          color: paused ? AppColors.volt : AppColors.cyan,
                          onPressed: paused ? onResume : onPause,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SheetButton(
                          label: 'STOP',
                          color: AppColors.danger,
                          onPressed: onStop,
                        ),
                      ),
                    ],
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

/// Large pill button used in the telemetry sheet (start / pause / resume /
/// stop). Black label on a solid neon fill.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
    );
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

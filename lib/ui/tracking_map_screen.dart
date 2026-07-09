import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/settings_providers.dart';
import '../providers/tracking_providers.dart';
import '../services/location_source.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'ride_summary_screen.dart';

/// CartoDB basemap URL for the given brightness — dark tiles on the dark theme,
/// light tiles on the light theme.
String basemapUrl(bool isDark) => isDark
    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
    : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

/// Full-screen map with a floating glassmorphic telemetry sheet — the
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

  /// The live map is hidden by default to save battery — the map + its blur are
  /// the dominant power draw, and recording runs in the background service
  /// regardless of what's on screen. The rider taps "Map" to see it on demand.
  bool _showMap = false;

  /// The rider's last known position while idle (before/without a ride), used
  /// to center the map on open and show a "you are here" marker.
  LatLng? _myLocation;
  bool _locating = false;

  /// Reveals / hides the live map. When hidden, the FlutterMap widget is not
  /// built at all (no tile fetches, no per-frame blur, no camera work).
  void _toggleMap() {
    setState(() {
      _showMap = !_showMap;
      if (!_showMap) _mapReady = false; // controller detaches with the widget
    });
  }

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

  /// Drawer entry point: let the rider pick which GPS pipeline future rides
  /// record with (a temporary A/B test), persisting the choice for the
  /// background isolate to read at the next "Start ride" tap.
  Future<void> _openTrackingMethodPicker() async {
    final current = await SettingsService.instance.loadGpsSource();
    if (!mounted) return;
    final chosen = await _showGpsSourcePicker(current);
    if (chosen == null || !mounted) return;
    await SettingsService.instance.saveGpsSource(chosen);
  }

  Future<LocationSourceKind?> _showGpsSourcePicker(
      LocationSourceKind current) {
    final cx = AppColors.of(context);
    const descriptions = {
      LocationSourceKind.fused: 'Google fused provider · 5 m filter (original)',
      LocationSourceKind.raw: 'Raw GNSS · 1 s cadence · every fix',
      LocationSourceKind.fusedFast: 'Fused provider · 1 s cadence · every fix',
    };
    return showDialog<LocationSourceKind>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cx.surface,
        title: Text('Tracking method',
            style: TextStyle(color: cx.textBright, fontSize: 18)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in LocationSourceKind.values)
              ListTile(
                onTap: () => Navigator.of(ctx).pop(kind),
                leading: Icon(
                  kind == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: kind == current ? cx.accentInk : cx.textDim,
                ),
                title: Text(kind.label,
                    style: TextStyle(
                        color: cx.textBright, fontWeight: FontWeight.w600)),
                subtitle: Text(descriptions[kind]!,
                    style: TextStyle(color: cx.textDim, fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: cx.textDim)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    final cx = AppColors.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: cx.surface,
          content: Text(message, style: TextStyle(color: cx.dangerInk)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final state = ref.watch(trackingControllerProvider);

    // Follow the rider (only while the map is actually on screen), present the
    // post-ride summary, and surface errors.
    ref.listen<TrackingUiState>(trackingControllerProvider, (prev, next) {
      final t = next.telemetry;
      if (_showMap && _mapReady && t?.lat != null && t?.lon != null) {
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
              backgroundColor: cx.surface,
              content: Text(next.error!, style: TextStyle(color: cx.dangerInk)),
            ),
          );
      }
    });

    final current = _currentLatLng(state);

    return Scaffold(
      backgroundColor: cx.canvas,
      drawer: _AppDrawer(onTrackingMethod: _openTrackingMethodPicker),
      body: Stack(
        children: [
          // Base layer: the live map on demand, or a lightweight stats backdrop
          // that keeps the GPU idle and lets the screen sleep to save battery.
          if (_showMap)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: current ?? _fallbackCenter,
                initialZoom: 16,
                backgroundColor: cx.canvas,
                onMapReady: () {
                  _mapReady = true;
                  // Center on the rider as soon as the map can accept moves.
                  _locateMe();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: basemapUrl(cx.isDark),
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'id.co.smma.rollingbike',
                  // Offline-first: swallow fetch failures (no error spam / red
                  // tiles when there's no signal) and serve from the persistent
                  // disk cache configured in TileCacheService.
                  tileProvider: NetworkTileProvider(silenceExceptions: true),
                ),
                if (state.route.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: state.route,
                        strokeWidth: 5,
                        color: cx.accentInk,
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
            )
          else
            Positioned.fill(child: _StatsBackdrop(state: state)),
          if (_showMap) const _MapAttribution(),
          const _MenuButton(),
          // Map toggle (left) + locate (right, map only) sit just above the
          // telemetry sheet so they're never hidden behind it.
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MapToggleButton(showMap: _showMap, onTap: _toggleMap),
                      if (_showMap)
                        _LocateButton(busy: _locating, onTap: _locateMe)
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
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

/// Glowing accent position marker.
class _RiderDot extends StatelessWidget {
  const _RiderDot();

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: cx.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: [
          BoxShadow(
            color: cx.accent.withValues(alpha: 0.6),
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
    final cx = AppColors.of(context);
    return Positioned(
      top: 8,
      right: 8,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: cx.canvas.withValues(alpha: 0.5),
          child: Text(
            '© OpenStreetMap · CARTO',
            style: TextStyle(color: cx.textDim, fontSize: 9),
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
    final cx = AppColors.of(context);
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
                color: cx.surface.withValues(alpha: 0.6),
                child: InkWell(
                  onTap: () => Scaffold.of(context).openDrawer(),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: cx.accentInk.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.menu, color: cx.textBright),
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
    final cx = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: cx.surface.withValues(alpha: 0.72),
          child: InkWell(
            onTap: busy ? null : onTap,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: cx.accentInk.withValues(alpha: 0.35)),
              ),
              child: busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: cx.accentInk),
                    )
                  : Icon(Icons.my_location, color: cx.accentInk),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass pill that reveals / hides the live map. Mirrors the locate button's
/// styling; sits to the left of it above the telemetry sheet.
class _MapToggleButton extends StatelessWidget {
  const _MapToggleButton({required this.showMap, required this.onTap});

  final bool showMap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: cx.surface.withValues(alpha: 0.72),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: cx.accentInk.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(showMap ? Icons.map : Icons.map_outlined,
                      color: cx.accentInk, size: 20),
                  const SizedBox(width: 8),
                  Text(showMap ? 'Hide map' : 'Map',
                      style: TextStyle(
                          color: cx.accentInk, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight backdrop shown in place of the map (default) — no tiles, no
/// blur, so the GPU stays idle and the screen can sleep while recording
/// continues in the background service.
class _StatsBackdrop extends StatelessWidget {
  const _StatsBackdrop({required this.state});

  final TrackingUiState state;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final recording = state.phase == 'recording';
    return Container(
      color: cx.canvas,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.two_wheeler,
                size: 72, color: cx.accentInk.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'RollingBike',
              style: TextStyle(
                color: cx.accentInk,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 44),
              child: Text(
                recording
                    ? 'Recording in the background — the screen can sleep to save battery.'
                    : 'Map hidden to save battery. Tap Map to view your route.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cx.textDim, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Side menu: theme toggle, ride history, tracking method (GPS source A/B
/// test) + exit.
class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.onTrackingMethod});

  /// Opens the GPS-source picker dialog. Called after the drawer closes.
  final VoidCallback onTrackingMethod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cx = AppColors.of(context);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    return Drawer(
      backgroundColor: cx.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text(
                'RollingBike',
                style: TextStyle(
                  color: cx.accentInk,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            Divider(color: cx.border, height: 1),
            SwitchListTile(
              secondary: Icon(
                isDark ? Icons.dark_mode : Icons.light_mode,
                color: cx.textBright,
              ),
              title: Text('Dark mode',
                  style: TextStyle(color: cx.textBright)),
              value: isDark,
              activeThumbColor: cx.onAccent,
              activeTrackColor: cx.accent,
              onChanged: (_) =>
                  ref.read(themeModeProvider.notifier).toggle(),
            ),
            Divider(color: cx.border, height: 1),
            ListTile(
              leading: Icon(Icons.history, color: cx.textBright),
              title: Text('History of trips',
                  style: TextStyle(color: cx.textBright)),
              onTap: () {
                Navigator.of(context).pop(); // close drawer
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.gps_fixed, color: cx.textBright),
              title: Text('Tracking method',
                  style: TextStyle(color: cx.textBright)),
              onTap: () {
                Navigator.of(context).pop(); // close drawer
                onTrackingMethod();
              },
            ),
            ListTile(
              leading: Icon(Icons.exit_to_app, color: cx.textBright),
              title:
                  Text('Exit', style: TextStyle(color: cx.textBright)),
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
    final cx = AppColors.of(context);
    final tracking = state.isTracking;
    final paused = state.isPaused;
    // Lifecycle: START → acquiring (waiting for GPS) → countdown (3-2-1) →
    // recording. The clock/distance only run in recording.
    final phase = state.phase;
    final acquiring = phase == 'acquiring';
    final countingDown = phase == 'countdown';
    final recording = phase == 'recording';
    // While tracking, show live telemetry; when stopped, show the last ride's
    // finalised summary if present.
    final t = tracking ? state.telemetry : (state.lastFinished ?? state.telemetry);
    final speedKmh = (recording && !paused) ? (t?.speedKmh ?? 0) : 0.0;
    // Hero readout: the countdown number while counting down, dashes while
    // acquiring, otherwise the live speed.
    final heroValue = countingDown
        ? state.countdown.toString()
        : (acquiring ? '--' : speedKmh.toStringAsFixed(0));

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cx.surface.withValues(alpha: 0.72),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: cx.accentInk.withValues(alpha: 0.3)),
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
                    color: cx.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                // Hero: live speed, or the big countdown number while starting.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      heroValue,
                      style: TextStyle(
                        color: acquiring ? cx.textDim : cx.accentInk,
                        fontSize: countingDown ? 96 : 72,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!countingDown) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('km/h',
                            style:
                                TextStyle(color: cx.textDim, fontSize: 18)),
                      ),
                    ],
                  ],
                ),
                if (paused) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: cx.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: cx.accentInk.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      'PAUSED',
                      style: TextStyle(
                          color: cx.accentInk,
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ] else if (countingDown) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: cx.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: cx.accentInk.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      'GET READY',
                      style: TextStyle(
                          color: cx.accentInk,
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ] else if (acquiring) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cx.textDim),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: cx.textDim.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: cx.textDim.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'ACQUIRING GPS…',
                          style: TextStyle(
                              color: cx.textDim,
                              fontSize: 12,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
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
                        color: cx.danger),
                  ],
                ),
                const SizedBox(height: 22),
                if (!tracking)
                  _SheetButton(
                    label: 'START RIDE',
                    color: cx.accent,
                    onPressed: onStart,
                  )
                else if (acquiring || countingDown)
                  // No ride has started yet — the only action is to back out.
                  _SheetButton(
                    label: 'CANCEL',
                    color: cx.danger,
                    onPressed: onStop,
                  )
                else
                  Row(
                    children: [
                      // Pause ↔ Resume.
                      Expanded(
                        child: _SheetButton(
                          label: paused ? 'RESUME' : 'PAUSE',
                          color: cx.accent,
                          onPressed: paused ? onResume : onPause,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SheetButton(
                          label: 'STOP',
                          color: cx.danger,
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
/// stop). Dark label on a solid accent fill.
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
    final cx = AppColors.of(context);
    return SizedBox(
      height: 68,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: cx.onAccent,
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
        children: [
          Text(label,
              style: TextStyle(color: cx.textDim, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color ?? cx.accentInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          if (unit.isNotEmpty)
            Text(unit,
                style: TextStyle(color: cx.textDim, fontSize: 10)),
        ],
      ),
    );
  }
}

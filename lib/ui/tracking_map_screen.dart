import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/units.dart';
import '../providers/settings_providers.dart';
import '../providers/tracking_providers.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
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
                  userAgentPackageName: 'id.co.opentrack.rollingbike',
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
            Positioned.fill(
              child: _StatsBackdrop(state: state, onShowMap: _toggleMap),
            ),
          if (_showMap) const _MapAttribution(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hide-map (left) + recenter (right) float just above the sheet
                // only while the map is on screen. When it's hidden, the
                // backdrop carries its own centered "Show map" pill instead.
                if (_showMap)
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _MapToggleButton(showMap: _showMap, onTap: _toggleMap),
                        _LocateButton(busy: _locating, onTap: _locateMe),
                      ],
                    ),
                  ),
                _TelemetrySheet(
                  state: state,
                  unit: ref.watch(speedUnitProvider),
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
/// continues in the background service. Mirrors the prototype's map-hidden
/// state: branded wordmark, a hint, and a "Show map" pill.
class _StatsBackdrop extends StatelessWidget {
  const _StatsBackdrop({required this.state, required this.onShowMap});

  final TrackingUiState state;
  final VoidCallback onShowMap;

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
            Icon(Icons.speed, size: 56, color: cx.accentInk),
            const SizedBox(height: 18),
            Text(
              'RollingBike',
              style: TextStyle(
                color: cx.accentInk,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                recording
                    ? 'Recording in the background — the screen can sleep to save battery.'
                    : 'Map hidden to save battery. Tap below to view your route.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cx.textDim, fontSize: 14, height: 1.5),
              ),
            ),
            const SizedBox(height: 18),
            _ShowMapButton(onTap: onShowMap),
          ],
        ),
      ),
    );
  }
}

/// Outline pill inside the map-hidden backdrop that reveals the live map.
class _ShowMapButton extends StatelessWidget {
  const _ShowMapButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: cx.border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, color: cx.textBright, size: 17),
              const SizedBox(width: 8),
              Text('Show map',
                  style: TextStyle(
                      color: cx.textBright,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
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
    required this.unit,
    required this.onStart,
    required this.onStop,
    required this.onPause,
    required this.onResume,
  });

  final TrackingUiState state;
  final SpeedUnit unit;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPause;
  final VoidCallback onResume;

  /// How long the rider must hold STOP to end a ride (matches the prototype's
  /// "Hold STOP for 2.2s" affordance).
  static const double _stopHoldSeconds = 2.2;

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
    // Big speed number: the countdown while starting, otherwise the live speed
    // (converted to the rider's chosen unit). While acquiring, the number is
    // replaced entirely by an "Acquiring GPS" pill, so no number is shown.
    final heroNumber = countingDown
        ? state.countdown.toString()
        : unit.speed(speedKmh).toStringAsFixed(0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cx.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: cx.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cx.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Hero: the acquiring pill, or the big speed/countdown number.
            if (acquiring)
              _StatusPill(
                label: 'ACQUIRING GPS…',
                dotColor: cx.accent,
                textColor: cx.textBright,
                borderColor: cx.border,
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    heroNumber,
                    style: TextStyle(
                      color: countingDown ? cx.accentInk : cx.textBright,
                      fontSize: countingDown ? 84 : 60,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!countingDown) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(unit.speedLabel,
                          style: TextStyle(color: cx.textDim, fontSize: 18)),
                    ),
                  ],
                ],
              ),
              if (paused) ...[
                const SizedBox(height: 8),
                _OutlinePill(label: 'PAUSED', color: cx.accentInk),
              ] else if (countingDown) ...[
                const SizedBox(height: 8),
                _OutlinePill(label: 'GET READY', color: cx.accentInk),
              ],
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                _Metric(
                    label: 'DIST',
                    value: unit
                        .distanceMeters(t?.distanceMeters ?? 0)
                        .toStringAsFixed(2),
                    unit: unit.distanceLabel),
                _Metric(
                    label: 'TIME',
                    value: _fmtDuration(t?.durationSeconds ?? 0),
                    unit: 'min'),
                _Metric(
                    label: 'AVG',
                    value: unit.speed(t?.avgSpeedKmh ?? 0).toStringAsFixed(1),
                    unit: unit.speedLabel),
                _Metric(
                    label: 'MAX',
                    value: unit.speed(t?.maxSpeedKmh ?? 0).toStringAsFixed(1),
                    unit: unit.speedLabel,
                    color: cx.danger),
              ],
            ),
            const SizedBox(height: 20),
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
                outlined: true,
                onPressed: onStop,
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: paused ? 'RESUME' : 'PAUSE',
                      color: cx.accent,
                      onPressed: paused ? onResume : onPause,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HoldToStopButton(
                      onStop: onStop,
                      holdSeconds: _stopHoldSeconds,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Hold STOP for ${_stopHoldSeconds.toStringAsFixed(1)}s to end ride',
                style: TextStyle(color: cx.textDim, fontSize: 11),
              ),
            ],
          ],
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

/// Pill button used in the telemetry sheet (start / pause / resume). A solid
/// [color] fill with a dark label, or an [outlined] transparent variant (used
/// for CANCEL) with a bordered, bright label.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onPressed,
    this.color,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final style = const TextStyle(fontSize: 16, fontWeight: FontWeight.w800);
    if (outlined) {
      return SizedBox(
        height: 56,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: cx.textBright,
            side: BorderSide(color: cx.border),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label, style: style),
        ),
      );
    }
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: cx.onAccent,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(label, style: style),
      ),
    );
  }
}

/// Press-and-hold STOP button: a red fill with a translucent progress overlay
/// that sweeps left→right as the rider holds. Ends the ride once full; resets
/// if released early. Mirrors the prototype's hold-to-stop affordance.
class _HoldToStopButton extends StatefulWidget {
  const _HoldToStopButton({required this.onStop, required this.holdSeconds});

  final VoidCallback onStop;
  final double holdSeconds;

  @override
  State<_HoldToStopButton> createState() => _HoldToStopButtonState();
}

class _HoldToStopButtonState extends State<_HoldToStopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.holdSeconds * 1000).round()),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onStop();
        _c.reset();
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _release() {
    if (_c.status != AnimationStatus.completed) _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Listener(
      onPointerDown: (_) => _c.forward(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: SizedBox(
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: cx.danger),
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _c.value,
                    heightFactor: 1,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  'STOP',
                  style: TextStyle(
                    color: cx.onAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status pill with a leading dot (e.g. "● ACQUIRING GPS…") shown in place of
/// the speed number.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.dotColor,
    required this.textColor,
    required this.borderColor,
  });

  final String label;
  final Color dotColor;
  final Color textColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small outlined status pill (PAUSED / GET READY) shown under the hero number.
class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
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
              style: TextStyle(
                  color: cx.textDim, fontSize: 11, letterSpacing: 0.5)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: color ?? cx.textBright,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          if (unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(unit,
                  style: TextStyle(color: cx.textDim, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/speed_palette.dart';
import '../core/units.dart';
import '../data/models/ride.dart';
import '../data/models/track_point.dart';
import '../providers/history_providers.dart';
import '../providers/settings_providers.dart';
import '../services/ride_share.dart';
import '../theme/app_theme.dart';
import 'accel_brake_chart.dart';
import 'elevation_speed_chart.dart';
import 'place_route_label.dart';
import 'share_card.dart';
import 'speed_distance_chart.dart';
import 'speed_zone_chart.dart';
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
    final unit = ref.read(speedUnitProvider);

    // Step 1 — pick one of the four card layouts (live previews).
    final layout = await _pickLayout(points, unit);
    if (layout == null || !mounted) return;

    // Step 2 — pick the export action for the chosen layout.
    final action = await _showShareOptions();
    if (action == null || !mounted) return;

    setState(() => _sharing = true);
    try {
      if (action == _ShareAction.instagram) {
        await RideShare.shareToInstagram(
          context: context,
          ride: widget.ride,
          points: points,
          unit: unit,
          layout: layout,
        );
      } else {
        await RideShare.saveToGallery(
          context: context,
          ride: widget.ride,
          points: points,
          unit: unit,
          layout: layout,
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

  /// Bottom sheet of the four card layouts, each rendered as a live preview on
  /// a dark backdrop (the cards are transparent + styled for a dark look).
  /// Returns the picked [ShareLayout], or null if dismissed.
  Future<ShareLayout?> _pickLayout(List<TrackPoint> points, SpeedUnit unit) {
    final cx = AppColors.of(context);
    return showModalBottomSheet<ShareLayout>(
      context: context,
      backgroundColor: cx.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a layout',
                  style: TextStyle(
                      color: cx.textBright,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Pick a card style, then share or save it.',
                  style: TextStyle(color: cx.textDim, fontSize: 13)),
              const SizedBox(height: 16),
              Flexible(
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.52,
                  children: [
                    for (final layout in ShareLayout.values)
                      _LayoutTile(
                        ride: widget.ride,
                        points: points,
                        unit: unit,
                        layout: layout,
                        onTap: () => Navigator.of(ctx).pop(layout),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              data: (points) => _RouteMap(
                points: points,
                unit: ref.watch(speedUnitProvider),
              ),
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
                  // Charts from the recorded track (needs at least two points),
                  // shown as a horizontal swipe carousel.
                  if ((trackAsync.valueOrNull?.length ?? 0) >= 2)
                    _ChartCarousel(
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
  const _RouteMap({required this.points, required this.unit});

  final List<TrackPoint> points;
  final SpeedUnit unit;

  /// Number of quantized speed→color bands. Consecutive segments in the same
  /// band merge into one polyline (run-length), so a steady cruise draws a few
  /// polylines instead of one-per-fix while keeping the exact geometry.
  static const int _bands = 26;

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

    final speeds = [for (final p in points) p.speedMps * 3.6]; // km/h
    final maxSpeed = speeds.fold(0.0, (m, s) => s > m ? s : m);
    final segments = _speedSegments(route, speeds, maxSpeed);

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            backgroundColor: cx.canvas,
            initialCenter: route.first,
            initialZoom: 15,
            // Fit the whole recorded route in view. A single-point ride keeps
            // the initialCenter/zoom above (coordinates fit needs >= 2).
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
            if (segments.isNotEmpty) PolylineLayer(polylines: segments),
            MarkerLayer(
              markers: [
                _endpointMarker(route.first, cx.accent), // start
                if (route.length >= 2)
                  _endpointMarker(route.last, cx.danger), // end
              ],
            ),
          ],
        ),
        if (maxSpeed > 0)
          Positioned(
            left: 12,
            bottom: 12,
            child: _SpeedLegend(maxSpeedKmh: maxSpeed, unit: unit),
          ),
      ],
    );
  }

  /// Builds one polyline per run of consecutive segments sharing a speed band,
  /// colored via [SpeedPalette]. Each run reuses the previous run's boundary
  /// vertex so the colored line stays continuous (no gaps at band changes).
  List<Polyline> _speedSegments(
    List<LatLng> route,
    List<double> speeds,
    double maxSpeed,
  ) {
    if (route.length < 2) return const [];
    int bandOf(int seg) {
      // Segment `seg` joins route[seg-1]→route[seg]; color by its mean speed.
      final s = (speeds[seg - 1] + speeds[seg]) / 2;
      final t = maxSpeed <= 0 ? 0.0 : (s / maxSpeed).clamp(0.0, 1.0);
      return (t * (_bands - 1)).round();
    }

    final out = <Polyline>[];
    var runStart = 1; // first segment index
    var runBand = bandOf(1);
    void flush(int endSeg) {
      out.add(Polyline(
        points: route.sublist(runStart - 1, endSeg + 1),
        strokeWidth: 5,
        color: SpeedPalette.at(runBand / (_bands - 1)),
      ));
    }

    for (var seg = 2; seg < route.length; seg++) {
      final band = bandOf(seg);
      if (band != runBand) {
        flush(seg - 1);
        runStart = seg;
        runBand = band;
      }
    }
    flush(route.length - 1);
    return out;
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

/// Compact gradient scale explaining the speed-colored route: a Turbo bar from
/// 0 to the ride's max speed, in the rider's chosen unit.
class _SpeedLegend extends StatelessWidget {
  const _SpeedLegend({required this.maxSpeedKmh, required this.unit});

  final double maxSpeedKmh;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final labelStyle = TextStyle(
      color: cx.textBright,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: cx.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cx.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SPEED',
              style: TextStyle(
                color: cx.textDim,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              )),
          const SizedBox(height: 4),
          Container(
            width: 108,
            height: 7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: SpeedPalette.gradient,
                stops: SpeedPalette.gradientStops,
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 108,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0', style: labelStyle),
                Text(
                  '${unit.speed(maxSpeedKmh).toStringAsFixed(0)} '
                  '${unit.speedLabel}',
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
            if (PlaceRouteLabel.label(ride.startPlace, ride.endPlace) !=
                null) ...[
              const SizedBox(height: 6),
              PlaceRouteLabel(
                startPlace: ride.startPlace,
                endPlace: ride.endPlace,
                fontSize: 14,
              ),
            ],
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

/// Horizontal swipe carousel over the ride's charts: speed-vs-distance, speed
/// zones, acceleration/braking, and (when the track carries altitude) the
/// elevation-vs-speed profile. The pager resizes to the current page's actual
/// content height (each page is measured off its natural size) so the dots hug
/// the chart instead of floating below a fixed gap. The [PageView] only claims
/// horizontal drags and inner pages never scroll, so vertical scrolling passes
/// through to the surrounding scroll view. Page-indicator dots sit below.
class _ChartCarousel extends StatefulWidget {
  const _ChartCarousel({
    required this.points,
    required this.avgSpeedKmh,
    required this.unit,
  });

  final List<TrackPoint> points;
  final double avgSpeedKmh;
  final SpeedUnit unit;

  /// Height used until a page has been measured (first frame / far pages).
  static const double _fallbackHeight = 420;

  @override
  State<_ChartCarousel> createState() => _ChartCarouselState();
}

class _ChartCarouselState extends State<_ChartCarousel> {
  final _controller = PageController();
  int _page = 0;

  /// Measured natural content height per page index.
  final _heights = <int, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setHeight(int index, double height) {
    if (_heights[index] == height) return;
    setState(() => _heights[index] = height);
  }

  /// Mirrors [ElevationSpeedChart]'s own guard so the elevation page is only
  /// added when it would actually render (>= 2 altitude fixes, >= 2 m of swing).
  bool get _hasElevation {
    var count = 0;
    double? mn, mx;
    for (final p in widget.points) {
      final a = p.altitude;
      if (a == null) continue;
      count++;
      mn = mn == null ? a : (a < mn ? a : mn);
      mx = mx == null ? a : (a > mx ? a : mx);
    }
    return count >= 2 && mn != null && mx != null && (mx - mn) >= 2.0;
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final pages = <Widget>[
      _RideChart(
        points: widget.points,
        avgSpeedKmh: widget.avgSpeedKmh,
        unit: widget.unit,
      ),
      SpeedZoneChart(points: widget.points, unit: widget.unit),
      AccelBrakeChart(points: widget.points),
      if (_hasElevation)
        ElevationSpeedChart(points: widget.points, unit: widget.unit),
    ];

    // Guard against the current page falling out of range (e.g. elevation page
    // disappearing) after a rebuild.
    final page = _page.clamp(0, pages.length - 1);
    final height = _heights[page] ?? _ChartCarousel._fallbackHeight;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: height,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (var i = 0; i < pages.length; i++)
                // Never-scrolling viewport: lets the child take its natural
                // height (for measurement) without stealing vertical drags.
                SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: _MeasureSize(
                    onChange: (size) => _setHeight(i, size.height),
                    child: pages[i],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == page ? cx.accent : cx.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reports its child's laid-out size via [onChange] after each frame it changes.
/// Used to size the chart pager to the active page's real content height.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
      BuildContext context, _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _old;

  @override
  void performLayout() {
    super.performLayout();
    final size = child?.size ?? Size.zero;
    if (size != _old) {
      _old = size;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => onChange(size));
    }
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
            interactive: true,
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

/// One tappable card-layout preview in the "Choose a layout" sheet: the real
/// [ShareCard] scaled to fit, on a fixed dark backdrop (the card is transparent
/// and styled for a dark look), with the layout's name + blurb beneath.
class _LayoutTile extends StatelessWidget {
  const _LayoutTile({
    required this.ride,
    required this.points,
    required this.unit,
    required this.layout,
    required this.onTap,
  });

  final Ride ride;
  final List<TrackPoint> points;
  final SpeedUnit unit;
  final ShareLayout layout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cx.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 360,
                  height: 640,
                  child: ShareCard(
                    ride: ride,
                    points: points,
                    unit: unit,
                    layout: layout,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(layout.title,
              style: TextStyle(
                  color: cx.textBright,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          Text(layout.blurb,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cx.textDim, fontSize: 11)),
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

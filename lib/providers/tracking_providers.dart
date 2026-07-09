import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../data/database_service.dart';
import '../services/permission_service.dart';
import '../services/tracking_service.dart';

/// The app-wide background tracking service.
final trackingServiceProvider =
    Provider<TrackingService>((ref) => TrackingService.instance);

/// Immutable UI state for the tracking screen.
class TrackingUiState {
  const TrackingUiState({
    this.isTracking = false,
    this.isPaused = false,
    this.phase = 'idle',
    this.countdown = 0,
    this.telemetry,
    this.route = const [],
    this.lastFinished,
    this.error,
  });

  final bool isTracking;
  final bool isPaused;

  /// Ride lifecycle: 'idle', 'acquiring' (waiting for first fix), 'countdown'
  /// (3-2-1 before the clock starts), or 'recording'.
  final String phase;

  /// Remaining countdown seconds while [phase] == 'countdown' (0 otherwise).
  final int countdown;
  final LiveTelemetry? telemetry;
  final List<LatLng> route;
  final LiveTelemetry? lastFinished;
  final String? error;

  TrackingUiState copyWith({
    bool? isTracking,
    bool? isPaused,
    String? phase,
    int? countdown,
    LiveTelemetry? telemetry,
    List<LatLng>? route,
    LiveTelemetry? lastFinished,
    String? error,
    bool clearTelemetry = false,
    bool clearFinished = false,
    bool clearError = false,
  }) {
    return TrackingUiState(
      isTracking: isTracking ?? this.isTracking,
      isPaused: isPaused ?? this.isPaused,
      phase: phase ?? this.phase,
      countdown: countdown ?? this.countdown,
      telemetry: clearTelemetry ? null : (telemetry ?? this.telemetry),
      route: route ?? this.route,
      lastFinished: clearFinished ? null : (lastFinished ?? this.lastFinished),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Bridges the background [TrackingService] streams into Riverpod state and
/// accumulates the live route polyline.
class TrackingController extends StateNotifier<TrackingUiState> {
  TrackingController(this._service) : super(const TrackingUiState()) {
    _telemetrySub = _service.telemetry.listen(_onTelemetry);
    _stoppedSub = _service.onStopped.listen(_onStopped);
    _cancelledSub = _service.onCancelled.listen(_onCancelled);
  }

  final TrackingService _service;
  late final StreamSubscription<LiveTelemetry> _telemetrySub;
  late final StreamSubscription<LiveTelemetry> _stoppedSub;
  late final StreamSubscription<String?> _cancelledSub;

  void _onTelemetry(LiveTelemetry t) {
    var route = state.route;
    // Telemetry now ticks once a second, re-sending the last known coords; only
    // extend the polyline when the position actually changed (a real new fix).
    if (t.lat != null && t.lon != null) {
      final point = LatLng(t.lat!, t.lon!);
      final last = route.isNotEmpty ? route.last : null;
      if (last == null ||
          last.latitude != point.latitude ||
          last.longitude != point.longitude) {
        route = [...route, point];
      }
    }
    state = state.copyWith(
      isTracking: true,
      isPaused: t.paused,
      phase: t.phase,
      countdown: t.countdown,
      telemetry: t,
      route: route,
    );
  }

  void _onStopped(LiveTelemetry t) {
    state = state.copyWith(
        isTracking: false, phase: 'idle', countdown: 0, lastFinished: t);
  }

  /// Acquisition was aborted before a ride began (Cancel or acquire timeout) —
  /// return to idle, surfacing the reason (if any) so the UI can toast it.
  void _onCancelled(String? reason) {
    state = state.copyWith(
      isTracking: false,
      isPaused: false,
      phase: 'idle',
      countdown: 0,
      route: const [],
      clearTelemetry: true,
      error: reason,
    );
  }

  /// Requests permissions and, if granted, clears prior route/summary and
  /// starts recording. Surfaces a denial reason via [TrackingUiState.error].
  Future<void> start() async {
    final perm = await PermissionService.ensureTrackingPermissions();
    if (!perm.granted) {
      state = state.copyWith(error: perm.message);
      return;
    }
    state = state.copyWith(
      isTracking: true,
      isPaused: false,
      phase: 'acquiring',
      countdown: 0,
      route: const [],
      clearTelemetry: true,
      clearFinished: true,
      clearError: true,
    );
    await _service.startRide();
  }

  void stop() => _service.stopRide();

  /// Pauses the active ride (optimistically; telemetry confirms shortly after).
  void pause() {
    _service.pauseRide();
    state = state.copyWith(isPaused: true);
  }

  /// Resumes a paused ride.
  void resume() {
    _service.resumeRide();
    state = state.copyWith(isPaused: false);
  }

  /// Names the just-finished ride (already persisted) and returns to idle,
  /// clearing the finished summary and route so the next ride starts fresh.
  Future<void> saveFinishedRide(String name) async {
    final t = state.lastFinished;
    if (t != null && name.trim().isNotEmpty) {
      await DatabaseService.instance.setRideName(t.rideId, name.trim());
    }
    _resetToIdle();
  }

  /// Deletes the just-finished ride (and its track points) and returns to idle.
  Future<void> discardFinishedRide() async {
    final t = state.lastFinished;
    if (t != null) {
      await DatabaseService.instance.deleteRide(t.rideId);
    }
    _resetToIdle();
  }

  /// Dismisses the summary without naming or deleting — the ride stays in the
  /// DB unnamed (crash-safe default when the rider just backs out).
  void keepFinishedRide() => _resetToIdle();

  void _resetToIdle() {
    state = state.copyWith(
      isTracking: false,
      isPaused: false,
      phase: 'idle',
      countdown: 0,
      route: const [],
      clearTelemetry: true,
      clearFinished: true,
    );
  }

  @override
  void dispose() {
    _telemetrySub.cancel();
    _stoppedSub.cancel();
    _cancelledSub.cancel();
    super.dispose();
  }
}

final trackingControllerProvider =
    StateNotifierProvider<TrackingController, TrackingUiState>((ref) {
  return TrackingController(ref.watch(trackingServiceProvider));
});

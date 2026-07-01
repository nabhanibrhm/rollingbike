import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a permission request, with a human-readable reason on failure.
class PermissionResult {
  const PermissionResult(this.granted, this.message);
  final bool granted;
  final String message;
}

/// Centralises the runtime permission dance needed before a ride can start:
/// location services enabled → foreground location grant → (best-effort)
/// notifications + background location.
class PermissionService {
  const PermissionService._();

  /// Requests everything the tracking service needs. Returns [PermissionResult]
  /// with `granted == true` once foreground location is available (the minimum
  /// to record); notification + background grants are best-effort.
  static Future<PermissionResult> ensureTrackingPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const PermissionResult(
        false,
        'Location services are turned off. Enable GPS and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const PermissionResult(
        false,
        'Location permission denied. Grant it in system settings.',
      );
    }

    // Android 13+ (API 33+) needs an explicit grant to show the persistent
    // foreground-service notification. No-op on older versions.
    await Permission.notification.request();

    // Background location (API 29+) lets tracking continue when the screen is
    // locked. Implicit with fine-location on the API 28 test device, so this is
    // best-effort and never blocks the start.
    if (permission == LocationPermission.whileInUse) {
      await Permission.locationAlways.request();
    }

    return const PermissionResult(true, 'granted');
  }
}

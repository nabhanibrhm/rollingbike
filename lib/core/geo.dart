import 'dart:math' as math;

/// Mean Earth radius in meters (WGS84 spherical approximation).
const double _earthRadiusMeters = 6371000.0;

double _toRadians(double degrees) => degrees * math.pi / 180.0;

/// Great-circle distance between two lat/lon points, in meters (Haversine).
///
/// Accurate to well within GPS noise at the distances between consecutive ride
/// fixes, and cheap enough to run on every position update.
double haversineMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final sinLat = math.sin(dLat / 2);
  final sinLon = math.sin(dLon / 2);
  final a = sinLat * sinLat +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          sinLon *
          sinLon;
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * c;
}

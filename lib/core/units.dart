/// The unit the rider sees speeds and distances in. All telemetry is computed
/// and stored internally in metric (km / km·h⁻¹); this only affects *display*,
/// converting at the last moment in the widgets that show a value.
enum SpeedUnit {
  kmh,
  mph;

  /// Short stable tag persisted in settings.
  String get tag => this == SpeedUnit.mph ? 'mph' : 'kmh';

  static SpeedUnit fromTag(String? tag) =>
      tag == 'mph' ? SpeedUnit.mph : SpeedUnit.kmh;

  /// Label for a speed value (e.g. next to a number).
  String get speedLabel => this == SpeedUnit.mph ? 'mph' : 'km/h';

  /// Label for a distance value.
  String get distanceLabel => this == SpeedUnit.mph ? 'mi' : 'km';

  static const double _milesPerKm = 0.621371;

  /// Convert a metric speed (km/h) into this unit.
  double speed(double kmh) => this == SpeedUnit.mph ? kmh * _milesPerKm : kmh;

  /// Convert a metric distance in kilometres into this unit's major distance.
  double distanceKm(double km) => this == SpeedUnit.mph ? km * _milesPerKm : km;

  /// Convert a metric distance in metres into this unit's major distance.
  double distanceMeters(double meters) => distanceKm(meters / 1000.0);
}

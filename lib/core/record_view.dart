/// What the Record screen shows behind the telemetry sheet.
///
/// The live map and its per-frame blur are the dominant on-screen power draw,
/// so the rider can trade it for a lightweight live speed/distance chart, or
/// hide both entirely (a static branded backdrop) to let the GPU idle and the
/// screen sleep while recording continues in the background service.
///
/// The Record screen's toggle cycles [map] → [chart] → [none] → [map]; the
/// choice is persisted (see `SettingsService.saveRecordView`).
enum RecordView {
  map,
  chart,
  none;

  /// Short stable tag persisted in settings.
  String get tag => switch (this) {
        RecordView.map => 'map',
        RecordView.chart => 'chart',
        RecordView.none => 'none',
      };

  static RecordView fromTag(String? tag) => switch (tag) {
        'map' => RecordView.map,
        'chart' => RecordView.chart,
        _ => RecordView.none,
      };

  /// The next view in the cycle map → chart → none → map.
  RecordView get next => switch (this) {
        RecordView.map => RecordView.chart,
        RecordView.chart => RecordView.none,
        RecordView.none => RecordView.map,
      };
}

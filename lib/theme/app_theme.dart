import 'package:flutter/material.dart';

/// RollingBike palette — a single four-colour identity (near-white, mint, coral,
/// charcoal) drives both themes. The near-white/charcoal poles swap between
/// light and dark, while mint (accent) and coral (danger) stay put as the shared
/// accents.
///
/// The bright mint reads well only as a *fill* — as text on a light canvas it
/// vanishes — so each mode also carries a legible "ink" variant for text, icons,
/// and lines. Widgets read the active set via [AppColors.of].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.border,
    required this.textBright,
    required this.textDim,
    required this.accent,
    required this.accentInk,
    required this.danger,
    required this.dangerInk,
    required this.onAccent,
  });

  final Brightness brightness;

  /// App background.
  final Color canvas;

  /// Raised surfaces: cards, sheets, dialogs.
  final Color surface;

  /// Hairline borders / dividers.
  final Color border;

  /// Primary text.
  final Color textBright;

  /// Secondary text: labels, captions, units.
  final Color textDim;

  /// Mint — brand accent used as a *fill* (buttons, markers, badges).
  final Color accent;

  /// Legible mint for text/icons/lines on [canvas]/[surface].
  final Color accentInk;

  /// Coral — used as a *fill* (STOP, destructive actions).
  final Color danger;

  /// Legible coral for destructive text/lines.
  final Color dangerInk;

  /// Text/icon colour placed on top of [accent]/[danger] fills.
  final Color onAccent;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF2C2C2C),
    surface: Color(0xFF3A3A3A),
    border: Color(0xFF4D4D4D),
    textBright: Color(0xFFFCFCFC),
    textDim: Color(0xFFA1A1A1),
    accent: Color(0xFF83FFE6),
    accentInk: Color(0xFF83FFE6),
    danger: Color(0xFFFF5F5F),
    dangerInk: Color(0xFFFF8080),
    onAccent: Color(0xFF1A1A1A),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFFCFCFC),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE6E6E6),
    textBright: Color(0xFF2C2C2C),
    textDim: Color(0xFF6E6E6E),
    accent: Color(0xFF83FFE6),
    accentInk: Color(0xFF0B7D6A), // deep teal — legible mint on a light canvas
    danger: Color(0xFFFF5F5F),
    dangerInk: Color(0xFFD93A3A),
    onAccent: Color(0xFF1A1A1A),
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? surface,
    Color? border,
    Color? textBright,
    Color? textDim,
    Color? accent,
    Color? accentInk,
    Color? danger,
    Color? dangerInk,
    Color? onAccent,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textBright: textBright ?? this.textBright,
      textDim: textDim ?? this.textDim,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      danger: danger ?? this.danger,
      dangerInk: dangerInk ?? this.dangerInk,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textBright: Color.lerp(textBright, other.textBright, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerInk: Color.lerp(dangerInk, other.dangerInk, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

/// Palette accessor for widgets: `final cx = AppColors.of(context);`.
///
/// Falls back to the dark palette if the extension is somehow absent (e.g. a
/// widget built outside the app theme).
class AppColors {
  AppColors._();

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? AppPalette.dark;
}

ThemeData buildLightTheme() => _themeFrom(AppPalette.light);
ThemeData buildDarkTheme() => _themeFrom(AppPalette.dark);

/// App-wide theme built from a palette. Monospace type scale (JetBrains Mono,
/// bundled as an asset — see pubspec) so telemetry renders offline.
ThemeData _themeFrom(AppPalette p) {
  final base = ThemeData(useMaterial3: true, brightness: p.brightness);
  final scheme =
      (p.isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    brightness: p.brightness,
    primary: p.accentInk,
    onPrimary: p.onAccent,
    secondary: p.accent,
    surface: p.surface,
    onSurface: p.textBright,
    error: p.danger,
    onError: p.onAccent,
  );

  return base.copyWith(
    scaffoldBackgroundColor: p.canvas,
    colorScheme: scheme,
    extensions: [p],
    textTheme: base.textTheme.apply(
      fontFamily: 'JetBrainsMono',
      bodyColor: p.textBright,
      displayColor: p.textBright,
    ),
  );
}

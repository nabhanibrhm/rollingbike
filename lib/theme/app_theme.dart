import 'package:flutter/material.dart';

/// ThrottlePath palette — a single four-colour identity (near-white, amber, red,
/// near-black) drives both themes, matching the design prototype. The
/// near-white/near-black poles swap between light and dark, while amber (accent)
/// and red (danger) stay put as the shared accents.
///
/// Amber reads well as both a *fill* and as text on the near-black canvas, so on
/// dark the "ink" variant equals the fill. On a light canvas amber vanishes as
/// text, so light carries a deepened amber "ink" variant for text, icons, and
/// lines. Widgets read the active set via [AppColors.of].
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
    canvas: Color(0xFF121212), // app background (prototype frame)
    surface: Color(0xFF1E1E1E), // cards / sheets
    border: Color(0xFF262626),
    textBright: Color(0xFFF2F2F0),
    textDim: Color(0xFF9A9A9A),
    accent: Color(0xFFFFB22C),
    accentInk: Color(0xFFFFB22C), // amber reads fine as text on near-black
    danger: Color(0xFFEF4444),
    dangerInk: Color(0xFFEF4444),
    onAccent: Color(0xFF1A1200), // near-black ink on amber fills
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFFAFAF7),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFECECEC),
    textBright: Color(0xFF1A1A1A),
    textDim: Color(0xFF6E6E6E),
    accent: Color(0xFFFFB22C),
    accentInk: Color(0xFFB06E00), // deep amber — legible on a light canvas
    danger: Color(0xFFEF4444),
    dangerInk: Color(0xFFC92A2A),
    onAccent: Color(0xFF1A1200),
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

/// App-wide theme built from a palette. Inter type scale (bundled as an asset —
/// see pubspec) matching the design prototype, rendered offline from launch.
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
      fontFamily: 'Inter',
      bodyColor: p.textBright,
      displayColor: p.textBright,
    ),
  );
}

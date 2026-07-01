import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Black Neon" palette. Pure-black canvas, zinc cards, electric accents.
class AppColors {
  AppColors._();

  static const black = Color(0xFF000000);
  static const zinc = Color(0xFF18181B); // card / sheet surface
  static const zincBorder = Color(0xFF27272A);
  static const cyan = Color(0xFF0DF0E3); // Electric Cyan — primary accent
  static const volt = Color(0xFF39FF14); // Volt Green — go / speed
  static const danger = Color(0xFFFF3B3B); // stop
  static const textDim = Color(0xFF71717A);
  static const textBright = Color(0xFFE4E4E7);
}

/// App-wide dark theme with a monospace type scale (JetBrains Mono via
/// google_fonts — fetched on first launch; bundling is the pubspec-noted
/// offline-hardening follow-up).
ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.black,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.cyan,
      secondary: AppColors.volt,
      surface: AppColors.zinc,
      error: AppColors.danger,
    ),
    textTheme: GoogleFonts.jetBrainsMonoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textBright,
      displayColor: AppColors.textBright,
    ),
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/ride.dart';
import '../data/models/track_point.dart';
import '../ui/share_card.dart';
import 'widget_to_image.dart';

/// Where a shared image ended up going.
enum ShareOutcome {
  /// Opened directly in Instagram Stories.
  instagramStory,

  /// Instagram not installed — routed to the system share sheet instead.
  systemChooser,
}

/// Captures a ride as a branded PNG and hands it to Instagram Stories (with a
/// system-sharesheet fallback). All heavy work — PNG encode + file write —
/// happens off the UI thread; the platform intent is dispatched via a
/// [MethodChannel] to the Android host (see MainActivity.kt).
class InstagramShare {
  InstagramShare._();

  static const _channel = MethodChannel('id.co.smma.rollingbike/share');

  /// The 9:16 sticker canvas the card is centred within, and its output density.
  static const _canvas = Size(360, 640);
  static const _pixelRatio = 3.0; // → 1080 × 1920 PNG

  /// Instagram Story background gradient painted behind the transparent sticker.
  static const _topBackgroundColor = '#123A34';
  static const _bottomBackgroundColor = '#0A0A0A';

  /// Renders [ride] (+ its [points]) and shares it. Returns where it went.
  ///
  /// Throws if capture or the platform call fails; callers should surface a
  /// message and clear any loading state.
  static Future<ShareOutcome> shareRide({
    required BuildContext context,
    required Ride ride,
    required List<TrackPoint> points,
  }) async {
    // 1. Render the card to a transparent PNG (off-screen, fixed size).
    final pngBytes = await captureWidgetToPng(
      context,
      child: ShareCard(ride: ride, points: points),
      logicalSize: _canvas,
      pixelRatio: _pixelRatio,
    );

    // 2. Write to the app's private cache (not the public gallery), under a
    //    dedicated folder that FileProvider is scoped to.
    final cacheDir = await getTemporaryDirectory();
    final shareDir = Directory('${cacheDir.path}/share_images');
    if (!await shareDir.exists()) {
      await shareDir.create(recursive: true);
    }
    final file = File('${shareDir.path}/ride_${ride.id}.png');
    await file.writeAsBytes(pngBytes, flush: true);

    // 3. Hand off to the Android host, which builds the content:// URI via
    //    FileProvider and fires the Instagram (or fallback) intent.
    final result = await _channel.invokeMethod<String>('shareToInstagram', {
      'filePath': file.path,
      'topColor': _topBackgroundColor,
      'bottomColor': _bottomBackgroundColor,
    });

    return result == 'story'
        ? ShareOutcome.instagramStory
        : ShareOutcome.systemChooser;
  }
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders [child] off-screen at a fixed [logicalSize] and returns a lossless
/// PNG (ARGB_8888 — transparency preserved) at [pixelRatio] density.
///
/// The widget is inserted into the app's [Overlay] far off-screen so it lays out
/// and paints (into its own [RepaintBoundary] layer) without ever being visible,
/// then captured. Because the size is fixed here, the output is identical
/// regardless of the device's screen resolution or aspect ratio.
Future<Uint8List> captureWidgetToPng(
  BuildContext context, {
  required Widget child,
  required Size logicalSize,
  double pixelRatio = 3.0,
}) async {
  final boundaryKey = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Park it well off-screen: it still lays out & paints, but is unseen.
      left: -logicalSize.width - 1000,
      top: 0,
      child: RepaintBoundary(
        key: boundaryKey,
        child: SizedBox.fromSize(size: logicalSize, child: child),
      ),
    ),
  );

  overlay.insert(entry);
  try {
    // Let it build, lay out, and paint. Two frames is comfortably safe; the
    // card uses a bundled font and a CustomPainter (no async image loads).
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Share card render object was not attached.');
    }

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Failed to encode the share PNG.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

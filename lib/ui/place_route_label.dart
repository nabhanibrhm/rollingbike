import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact "Origin → Destination" line built from a ride's reverse-geocoded
/// [startPlace] / [endPlace]. Renders an empty box when neither is known (old
/// rides, or rides saved offline), so callers can drop it in unconditionally.
///
/// Degrades gracefully: shows a lone place when only one end resolved, and a
/// `place (loop)` round-trip label when start and end are the same locality.
class PlaceRouteLabel extends StatelessWidget {
  const PlaceRouteLabel({
    super.key,
    required this.startPlace,
    required this.endPlace,
    this.fontSize = 13,
  });

  final String? startPlace;
  final String? endPlace;
  final double fontSize;

  /// Builds the display string, or null when there's nothing to show.
  static String? label(String? startPlace, String? endPlace) {
    final start = startPlace?.trim();
    final end = endPlace?.trim();
    final hasStart = start != null && start.isNotEmpty;
    final hasEnd = end != null && end.isNotEmpty;
    if (hasStart && hasEnd) {
      return start == end ? '$start (loop)' : '$start → $end';
    }
    if (hasStart) return start;
    if (hasEnd) return end;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = label(startPlace, endPlace);
    if (text == null) return const SizedBox.shrink();
    final cx = AppColors.of(context);
    return Row(
      children: [
        Icon(Icons.place_outlined, size: fontSize + 2, color: cx.accentInk),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cx.textDim,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

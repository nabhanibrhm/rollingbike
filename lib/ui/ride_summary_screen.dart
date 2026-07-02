import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tracking_providers.dart';
import '../services/tracking_service.dart';
import '../theme/app_theme.dart';

/// Full-screen post-ride summary. Shows the finalised stats (distance, elapsed
/// vs moving time, avg/max speed) and lets the rider name-and-save the ride or
/// discard it. Backing out (hardware/gesture) keeps the ride unnamed.
///
/// The ride is *already* in the DB by the time this shows (the engine persists
/// as it records), so Save just names it and Discard deletes it.
class RideSummaryScreen extends ConsumerStatefulWidget {
  const RideSummaryScreen({super.key, required this.telemetry});

  final LiveTelemetry telemetry;

  @override
  ConsumerState<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends ConsumerState<RideSummaryScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref
        .read(trackingControllerProvider.notifier)
        .saveFinishedRide(_nameController.text);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    if (_busy) return;
    final confirmed = await _confirmDiscard();
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    await ref.read(trackingControllerProvider.notifier).discardFinishedRide();
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.zinc,
        title: const Text('Discard ride?',
            style: TextStyle(color: AppColors.textBright)),
        content: const Text(
          'This permanently deletes the ride and its recorded track.',
          style: TextStyle(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.telemetry;
    return PopScope(
      // Backing out keeps the (already-saved) ride, unnamed.
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(trackingControllerProvider.notifier).keepFinishedRide();
      },
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'RIDE COMPLETE',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 14,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                // Distance hero.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      (t.distanceMeters / 1000).toStringAsFixed(2),
                      style: const TextStyle(
                        color: AppColors.volt,
                        fontSize: 64,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('km',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 20)),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    _SummaryStat(
                        label: 'TOTAL TIME',
                        value: _fmtDuration(t.durationSeconds)),
                    _SummaryStat(
                        label: 'MOVING TIME',
                        value: _fmtDuration(t.movingSeconds)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _SummaryStat(
                        label: 'AVG SPEED',
                        value: t.avgSpeedKmh.toStringAsFixed(1),
                        unit: 'km/h'),
                    _SummaryStat(
                        label: 'MAX SPEED',
                        value: t.maxSpeedKmh.toStringAsFixed(1),
                        unit: 'km/h',
                        color: AppColors.volt),
                  ],
                ),
                const Spacer(),
                TextField(
                  controller: _nameController,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppColors.textBright),
                  decoration: InputDecoration(
                    hintText: 'Name this ride (e.g. Morning commute)',
                    hintStyle: const TextStyle(color: AppColors.textDim),
                    filled: true,
                    fillColor: AppColors.zinc,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.zincBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cyan),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.volt,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('SAVE RIDE',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _discard,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('DISCARD',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formats seconds as `m:ss` (or `h:mm:ss` past an hour).
String _fmtDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    this.unit = '',
    this.color = AppColors.cyan,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 26, fontWeight: FontWeight.w700)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit,
                    style:
                        const TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_service.dart';
import '../data/models/ride.dart';
import '../providers/history_providers.dart';
import '../theme/app_theme.dart';
import 'ride_detail_screen.dart';

/// Scrollable list of saved rides, newest first. Each row is a compact ride
/// summary (name, date, distance, time, avg/max). Tap a row to open the
/// map+summary detail; swipe a row to delete.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridesAsync = ref.watch(rideHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.textBright,
        elevation: 0,
        title: const Text(
          'RIDE HISTORY',
          style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700),
        ),
      ),
      body: ridesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.cyan),
        ),
        error: (e, _) => Center(
          child: Text(
            'Could not load rides:\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
        data: (rides) {
          if (rides.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: rides.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _RideCard(
              ride: rides[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RideDetailScreen(ride: rides[i]),
                ),
              ),
              onDelete: () async {
                await DatabaseService.instance.deleteRide(rides[i].id);
                ref.invalidate(rideHistoryProvider);
              },
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.two_wheeler, color: AppColors.textDim, size: 56),
          SizedBox(height: 16),
          Text(
            'No rides yet',
            style: TextStyle(color: AppColors.textBright, fontSize: 18),
          ),
          SizedBox(height: 6),
          Text(
            'Your saved rides will show up here.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({
    required this.ride,
    required this.onTap,
    required this.onDelete,
  });

  final Ride ride;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(ride.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      child: Material(
        color: AppColors.zinc,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.zincBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        ride.name?.trim().isNotEmpty == true
                            ? ride.name!.trim()
                            : 'Untitled ride',
                        style: const TextStyle(
                          color: AppColors.textBright,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(ride.totalDistanceMeters / 1000).toStringAsFixed(2)} km',
                      style: const TextStyle(
                        color: AppColors.volt,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(ride.startTime),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MiniStat(
                      label: 'TIME',
                      value: _fmtDuration(ride.durationSeconds),
                    ),
                    _MiniStat(
                      label: 'MOVING',
                      value: _fmtDuration(ride.movingSeconds),
                    ),
                    _MiniStat(
                      label: 'AVG',
                      value: ride.averageSpeedKmh.toStringAsFixed(0),
                      unit: 'km/h',
                    ),
                    _MiniStat(
                      label: 'MAX',
                      value: ride.maxSpeedKmh.toStringAsFixed(0),
                      unit: 'km/h',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.zinc,
        title: const Text(
          'Delete ride?',
          style: TextStyle(color: AppColors.textBright),
        ),
        content: const Text(
          'This permanently removes the ride and its track.',
          style: TextStyle(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textDim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.unit = ''});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textDim, fontSize: 10),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. `Jul 2, 2026 · 22:36`. Avoids pulling in the intl package.
String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${_months[local.month - 1]} ${local.day}, ${local.year} · $hh:$mm';
}

String _fmtDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

// One-off diagnostic: open a pulled Isar DB and analyse a ride's track points
// for anomalies. Run: dart run tool/dump_ride.dart <dbDir> [rideName]
import 'dart:math' as math;

import 'package:isar_community/isar.dart';
import 'package:throttlepath/data/models/ride.dart';
import 'package:throttlepath/data/models/track_point.dart';

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

Future<void> main(List<String> args) async {
  final dbDir = args.isNotEmpty ? args[0] : '.';
  final wantName = args.length > 1 ? args[1] : 'Afternoon ride test';

  await Isar.initializeIsarCore(download: true);
  final isar = await Isar.open(
    [RideSchema, TrackPointSchema],
    directory: dbDir,
    name: 'default',
    inspector: false,
  );

  final rides = await isar.rides.where().findAll();
  print('=== RIDES IN DB (${rides.length}) ===');
  for (final r in rides) {
    print('  id=${r.id}  "${r.name}"  [${r.gpsSource ?? '?'}]  '
        '${r.startTime.toIso8601String()}  '
        'dist=${(r.totalDistanceMeters / 1000).toStringAsFixed(2)}km  '
        'dur=${r.durationSeconds}s moving=${r.movingSeconds}s '
        'avg=${r.averageSpeedKmh.toStringAsFixed(1)} max=${r.maxSpeedKmh.toStringAsFixed(1)}');
  }

  final ride = rides.firstWhere(
    (r) => (r.name ?? '').toLowerCase() == wantName.toLowerCase(),
    orElse: () => rides.first,
  );
  print('\n=== ANALYSING ride id=${ride.id} "${ride.name}" ===');

  final pts = await isar.trackPoints
      .filter()
      .rideIdEqualTo(ride.id)
      .sortByTimestamp()
      .findAll();
  print('track points: ${pts.length}');
  if (pts.isEmpty) {
    await isar.close();
    return;
  }

  final t0 = pts.first.timestamp;
  final tN = pts.last.timestamp;
  final spanS = tN.difference(t0).inMilliseconds / 1000.0;
  print('first: ${t0.toIso8601String()}');
  print('last : ${tN.toIso8601String()}');
  print('span : ${spanS.toStringAsFixed(1)}s  '
      '(ride.durationSeconds=${ride.durationSeconds})');

  // Recompute distance + gather per-step diagnostics.
  double recomputedDist = 0;
  double maxSegSpeedKmh = 0;
  double maxReportedKmh = 0;
  double maxGapS = 0;
  int gapsOver5s = 0;
  int dupTimestamps = 0;
  int zeroCoord = 0;
  final jumps = <String>[]; // implausible teleports
  final bigGaps = <String>[];
  int reportedMaxIdx = 0;

  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final repKmh = p.speedMps * 3.6;
    if (repKmh > maxReportedKmh) {
      maxReportedKmh = repKmh;
      reportedMaxIdx = i;
    }
    if (p.latitude.abs() < 0.0001 && p.longitude.abs() < 0.0001) zeroCoord++;

    if (i == 0) continue;
    final prev = pts[i - 1];
    final dtMs = p.timestamp.difference(prev.timestamp).inMilliseconds;
    final dtS = dtMs / 1000.0;
    if (dtS <= 0) {
      dupTimestamps++;
      continue;
    }
    if (dtS > maxGapS) maxGapS = dtS;
    final d = _haversineMeters(
        prev.latitude, prev.longitude, p.latitude, p.longitude);
    if (dtS > 5) {
      gapsOver5s++;
      final impliedKmh = (d / dtS) * 3.6;
      bigGaps.add('  gap ${dtS.toStringAsFixed(1).padLeft(6)}s at #$i '
          '(${prev.timestamp.toIso8601String().substring(11, 19)} -> '
          '${p.timestamp.toIso8601String().substring(11, 19)})  '
          'bridged ${d.toStringAsFixed(0).padLeft(5)}m  '
          '=> ${impliedKmh.toStringAsFixed(0)} km/h implied');
    }
    recomputedDist += d;
    final segKmh = (d / dtS) * 3.6;
    if (segKmh > maxSegSpeedKmh) maxSegSpeedKmh = segKmh;
    // Teleport: implied speed between fixes absurdly high for a motorbike.
    if (segKmh > 120) {
      jumps.add('  #$i +${d.toStringAsFixed(0)}m in ${dtS.toStringAsFixed(1)}s '
          '=> ${segKmh.toStringAsFixed(0)} km/h  '
          '(${prev.latitude.toStringAsFixed(5)},${prev.longitude.toStringAsFixed(5)}) '
          '-> (${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)})');
    }
  }

  print('\n--- DISTANCE ---');
  print('stored     : ${(ride.totalDistanceMeters / 1000).toStringAsFixed(3)} km');
  print('recomputed : ${(recomputedDist / 1000).toStringAsFixed(3)} km (raw haversine of points)');

  print('\n--- SPEED ---');
  print('stored max          : ${ride.maxSpeedKmh.toStringAsFixed(1)} km/h');
  print('max reported (fix)  : ${maxReportedKmh.toStringAsFixed(1)} km/h at #$reportedMaxIdx '
      '(${pts[reportedMaxIdx].timestamp.toIso8601String().substring(11, 19)})');
  print('max segment (calc)  : ${maxSegSpeedKmh.toStringAsFixed(1)} km/h');

  print('\n--- SAMPLING / GAPS ---');
  print('avg interval : ${(spanS / (pts.length - 1)).toStringAsFixed(2)}s');
  print('max gap      : ${maxGapS.toStringAsFixed(1)}s');
  print('gaps > 5s    : $gapsOver5s');
  print('dup/back timestamps: $dupTimestamps');
  print('near-zero coords   : $zeroCoord');

  if (bigGaps.isNotEmpty) {
    print('\n--- GAPS > 5s ---');
    bigGaps.take(30).forEach(print);
  }
  if (jumps.isNotEmpty) {
    print('\n--- POSITION JUMPS > 120 km/h implied (${jumps.length}) ---');
    jumps.take(30).forEach(print);
  } else {
    print('\nno position teleports > 120 km/h.');
  }

  // Speed histogram (reported).
  print('\n--- REPORTED SPEED HISTOGRAM (km/h) ---');
  final buckets = <int, int>{};
  for (final p in pts) {
    final b = ((p.speedMps * 3.6) ~/ 10) * 10;
    buckets[b] = (buckets[b] ?? 0) + 1;
  }
  final keys = buckets.keys.toList()..sort();
  for (final k in keys) {
    print('  ${k.toString().padLeft(3)}-${(k + 9).toString().padLeft(3)}: '
        '${'#' * (buckets[k]! ~/ 2).clamp(0, 60)} ${buckets[k]}');
  }

  await isar.close();
}

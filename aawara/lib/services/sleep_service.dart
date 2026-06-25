import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../workout/database/workout_database.dart';
import '../workout/models/sleep_session.dart';
import '../workout/utils/sleep_metrics.dart';

/// Reads sleep (sessions + stages) and associated vitals from Health Connect,
/// computes a score, and caches a [SleepSession] per night. Mirrors the
/// configure/permission flow used by StepTrackingService.
class SleepService {
  SleepService._();

  static final Health _health = Health();
  static bool _configured = false;

  static const _stageTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  ];
  static const _vitalTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
  ];
  static List<HealthDataType> get _allTypes => [..._stageTypes, ..._vitalTypes];
  static List<HealthDataAccess> get _readAll =>
      List.filled(_allTypes.length, HealthDataAccess.READ);

  // Bump the suffix to force a one-time 30-day re-backfill (e.g. after the score
  // formula/calibration changes) so cached nights are recomputed.
  static const _backfillFlag = 'sleep_backfilled_v8';

  static Future<Health> _configuredHealth() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    return _health;
  }

  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final health = await _configuredHealth();
      return await health.hasPermissions(_allTypes, permissions: _readAll) ??
          false;
    } catch (e) {
      debugPrint('Sleep permission check failed: $e');
      return false;
    }
  }

  /// Requests Health Connect read access for sleep + vitals.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final health = await _configuredHealth();
      final already =
          await health.hasPermissions(_allTypes, permissions: _readAll) ??
              false;
      if (already) return true;
      return await health.requestAuthorization(_allTypes, permissions: _readAll);
    } catch (e) {
      debugPrint('Sleep permission request failed: $e');
      return false;
    }
  }

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static SleepStage? _stageFor(HealthDataType t) => switch (t) {
        HealthDataType.SLEEP_DEEP => SleepStage.deep,
        HealthDataType.SLEEP_LIGHT => SleepStage.light,
        HealthDataType.SLEEP_REM => SleepStage.rem,
        // Generic "asleep, stage unknown" periods fill the gaps between graded
        // stages; count them as light so actual-sleep matches Samsung's total.
        HealthDataType.SLEEP_ASLEEP => SleepStage.light,
        HealthDataType.SLEEP_AWAKE => SleepStage.awake,
        HealthDataType.SLEEP_AWAKE_IN_BED => SleepStage.awake,
        _ => null,
      };

  static double? _num(HealthDataPoint p) {
    final v = p.value;
    return v is NumericHealthValue ? v.numericValue.toDouble() : null;
  }

  /// Fetches and caches the sleep session whose wake-up is on [wakeDate].
  /// Returns the cached session (or null if Health Connect had no sleep).
  static Future<SleepSession?> syncNight(DateTime wakeDate) async {
    if (!Platform.isAndroid) return null;
    final day = DateTime(wakeDate.year, wakeDate.month, wakeDate.day);
    // Noon-the-day-before → 6pm target day brackets a normal night while
    // excluding the previous night and most afternoon naps.
    final windowStart = day.subtract(const Duration(hours: 12));
    final windowEnd = day.add(const Duration(hours: 18));

    try {
      final health = await _configuredHealth();
      var points = await health.getHealthDataFromTypes(
        types: _allTypes,
        startTime: windowStart,
        endTime: windowEnd,
      );
      points = health.removeDuplicates(points);

      // Pick the main session: longest SLEEP_SESSION ending on the target day.
      final sessions = points
          .where((p) => p.type == HealthDataType.SLEEP_SESSION)
          .where((p) => _sameDay(p.dateTo, day))
          .toList()
        ..sort((a, b) => b.dateTo
            .difference(b.dateFrom)
            .compareTo(a.dateTo.difference(a.dateFrom)));

      DateTime? start;
      DateTime? end;
      if (sessions.isNotEmpty) {
        start = sessions.first.dateFrom;
        end = sessions.first.dateTo;
      }

      // Stage segments within the session (or the whole window if no session).
      final segments = <SleepStageSegment>[];
      for (final p in points) {
        final stage = _stageFor(p.type);
        if (stage == null) continue;
        if (start != null && (p.dateTo.isBefore(start) || p.dateFrom.isAfter(end!))) {
          continue;
        }
        if (start == null && !_sameDay(p.dateTo, day)) continue;
        segments.add(SleepStageSegment(stage, p.dateFrom, p.dateTo));
      }

      final totals = aggregateStages(segments);

      // Fall back to SLEEP_ASLEEP / SLEEP_SESSION duration when no granular stages.
      int asleep = totals.asleepMinutes;
      if (asleep == 0) {
        final asleepPts = points
            .where((p) => p.type == HealthDataType.SLEEP_ASLEEP)
            .where((p) => _sameDay(p.dateTo, day));
        for (final p in asleepPts) {
          asleep += p.dateTo.difference(p.dateFrom).inMinutes;
          start ??= p.dateFrom;
          end ??= p.dateTo;
        }
      }

      if (start == null || end == null) {
        if (asleep == 0) return null; // genuinely nothing recorded
        // No bounds but we have a duration — approximate.
        end = day.add(const Duration(hours: 6));
        start = end.subtract(Duration(minutes: asleep + totals.awakeMinutes));
      }

      final total = end.difference(start).inMinutes;
      // Reconcile to the full in-bed session. HC's awake detection is reliable,
      // but its graded stage segments leave gaps (it doesn't classify every
      // minute). Samsung counts those in-session gaps as sleep, so:
      //   asleep = in-bed − awake,  light = asleep − deep − rem.
      final deep = totals.deepMinutes;
      final rem = totals.remMinutes;
      if (total > 0) {
        asleep = (total - totals.awakeMinutes).clamp(deep + rem, total);
      }
      final awake = total > 0 ? total - asleep : totals.awakeMinutes;
      final light = (asleep - deep - rem).clamp(0, asleep);
      final vitals = _vitalsIn(points, start, end);

      // Sleep latency = the awake gap before the first actual sleep stage.
      // Health Connect frequently doesn't record the pre-sleep awake period, so
      // a 0/near-0 gap means "unknown", NOT "fell asleep instantly" — treat it as
      // neutral (optimal) rather than penalizing it.
      final firstSleep = totals.timeline
          .where((s) => s.stage != SleepStage.awake)
          .fold<DateTime?>(null, (e, s) => e == null || s.start.isBefore(e) ? s.start : e);
      final leadingAwake =
          firstSleep != null ? firstSleep.difference(start).inMinutes : 0;
      final latency =
          leadingAwake >= 3 ? leadingAwake.clamp(0, 120).toDouble() : 12.0;
      final spo2Dip = vitals.spo2DipFraction * asleep;
      final avgHr = vitals.hrAvg?.round() ?? 60;

      final score = computeSleepScore(
        actualSleepMinutes: asleep.toDouble(),
        deepSleepMinutes: deep.toDouble(),
        remSleepMinutes: rem.toDouble(),
        awakeMinutes: awake.toDouble(),
        latencyMinutes: latency,
        bedtime: start,
        avgHrBpm: avgHr,
        spo2DipMinutes: spo2Dip,
      );

      // Diagnostic: the derived inputs behind each night's score, so app vs
      // Samsung discrepancies can be traced to a specific input.
      debugPrint('[sleep] ${_dateStr(day)} score=$score | '
          'actual=$asleep deep=$deep rem=$rem light=$light awake=$awake '
          'latency=$latency inBed=$total '
          'bedtimeOffset=${start.hour * 60 + start.minute - 21 * 60} '
          'hr=$avgHr spo2Dip=${spo2Dip.toStringAsFixed(1)}');

      final stagesJson = jsonEncode([
        for (final s in totals.timeline)
          {
            'stage': s.stage.name,
            'start': s.start.toIso8601String(),
            'end': s.end.toIso8601String(),
          }
      ]);

      final session = SleepSession(
        date: _dateStr(day),
        startIso: start.toIso8601String(),
        endIso: end.toIso8601String(),
        totalMinutes: total <= 0 ? asleep : total,
        asleepMinutes: asleep,
        awakeMinutes: awake,
        lightMinutes: light,
        deepMinutes: deep,
        remMinutes: totals.remMinutes,
        score: score,
        hrAvg: vitals.hrAvg,
        hrMin: vitals.hrMin,
        spo2Avg: vitals.spo2Avg,
        spo2Min: vitals.spo2Min,
        respAvg: vitals.respAvg,
        source: 'health_connect',
        stagesJson: totals.timeline.isEmpty ? null : stagesJson,
      );

      await WorkoutDatabase.instance.upsertSleepSession(session);
      await WorkoutDatabase.instance
          .setWellnessSleepHours(session.date, asleep / 60.0);
      return session;
    } catch (e, st) {
      debugPrint('Sleep syncNight failed: $e');
      debugPrintStack(stackTrace: st);
      return null;
    }
  }

  /// Backfills the last [days] nights. Runs the full backfill only once
  /// (guarded by a prefs flag); subsequent calls just sync recent nights.
  static Future<void> syncHistory({int days = 30}) async {
    if (!Platform.isAndroid) return;
    if (!await requestPermission()) return;
    final prefs = await SharedPreferences.getInstance();
    final firstRun = !(prefs.getBool(_backfillFlag) ?? false);
    final count = firstRun ? days : 3;
    for (int i = 0; i < count; i++) {
      await syncNight(DateTime.now().subtract(Duration(days: i)));
    }
    if (firstRun) await prefs.setBool(_backfillFlag, true);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static _Vitals _vitalsIn(
      List<HealthDataPoint> points, DateTime start, DateTime end) {
    final hr = <double>[];
    final spo2 = <double>[];
    final resp = <double>[];
    for (final p in points) {
      if (p.dateFrom.isBefore(start) || p.dateTo.isAfter(end)) continue;
      final v = _num(p);
      if (v == null) continue;
      switch (p.type) {
        case HealthDataType.HEART_RATE:
          hr.add(v);
        case HealthDataType.BLOOD_OXYGEN:
          spo2.add(v);
        case HealthDataType.RESPIRATORY_RATE:
          resp.add(v);
        default:
          break;
      }
    }
    double? avg(List<double> xs) =>
        xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
    double? lo(List<double> xs) =>
        xs.isEmpty ? null : xs.reduce((a, b) => a < b ? a : b);
    // Fraction of SpO₂ samples below 90% — multiplied by sleep minutes to
    // estimate dip duration (HC samples are instantaneous, so this approximates).
    final dipFraction =
        spo2.isEmpty ? 0.0 : spo2.where((v) => v < 90).length / spo2.length;
    return _Vitals(
      hrAvg: avg(hr),
      hrMin: lo(hr),
      spo2Avg: avg(spo2),
      spo2Min: lo(spo2),
      respAvg: avg(resp),
      spo2DipFraction: dipFraction,
    );
  }
}

class _Vitals {
  final double? hrAvg, hrMin, spo2Avg, spo2Min, respAvg;
  final double spo2DipFraction;
  const _Vitals({
    this.hrAvg,
    this.hrMin,
    this.spo2Avg,
    this.spo2Min,
    this.respAvg,
    this.spo2DipFraction = 0.0,
  });
}

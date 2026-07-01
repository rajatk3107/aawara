import 'package:flutter/foundation.dart';

import '../workout/database/workout_database.dart';
import 'samsung_health_service.dart';

/// Result of a manual sync, for surfacing status to the user.
enum SyncOutcome { notSamsung, notPermitted, ok }

class SyncResult {
  final SyncOutcome outcome;
  final int exercises;
  final int sleep;
  final int linked;
  const SyncResult(this.outcome,
      {this.exercises = 0, this.sleep = 0, this.linked = 0});
}

/// Orchestrates pulling Samsung Health (watch) data into the local DB and
/// linking watch workouts to logged gym sessions. No-ops off Samsung devices.
class SamsungHealthSync {
  SamsungHealthSync._();

  static const _backfillDays = 30; // one-time initial history
  static const _lookbackDays = 2; // re-scan window to catch late/revised data
  static bool _running = false;

  /// Called on app open — syncs silently only when access is ALREADY granted
  /// (never prompts on launch; the Settings button handles granting).
  static Future<void> syncOnLaunch() async {
    if (_running) return;
    _running = true;
    try {
      final svc = SamsungHealthService.instance;
      if (!await svc.isAvailable()) return;
      final granted = await svc.grantedTypes();
      if (granted.isEmpty) return; // not yet permitted — leave to Settings button
      await _sync();
    } catch (e) {
      debugPrint('[samsung] sync failed: $e');
    } finally {
      _running = false;
    }
  }

  static Future<({int exercises, int sleep, int linked})> _sync() async {
    final db = WorkoutDatabase.instance;
    final svc = SamsungHealthService.instance;
    final now = DateTime.now();

    // Incremental: after the first backfill, only fetch data since the last
    // sync (minus a small lookback so late-written / revised data isn't missed).
    // Upserts are keyed by uid, so the overlap never duplicates.
    final lastSync = DateTime.tryParse(await db.getSyncState('last_sync') ?? '');
    final from = lastSync != null
        ? lastSync.subtract(const Duration(days: _lookbackDays))
        : now.subtract(const Duration(days: _backfillDays));

    final exercises = await svc.readExercises(from, now);
    for (final e in exercises) {
      await db.upsertSamsungExercise(e);
    }
    final sleep = await svc.readSleep(from, now);
    for (final s in sleep) {
      await db.upsertSamsungSleep(s);
    }

    // Backfill each session's dense HEART_RATE series over its own window. The
    // in-session exercise log is unreliable for some workout types (e.g. weight
    // machines came back empty), so the HR series is the source of truth for the
    // chart + zones. Bounded: each session is pulled once (hr_series_checked).
    var hrFilled = 0;
    for (final s in await db.sessionsNeedingHrSeries()) {
      final series = await svc.readVitalSeries('HEART_RATE', s.start, s.end);
      await db.applyHrSeries(s.uid, [for (final e in series) (t: e.start, hr: e.v)]);
      if (series.isNotEmpty) hrFilled++;
    }

    final linked = await db.linkSamsungToWorkouts();
    await db.setSyncState('last_sync', now.toIso8601String());
    debugPrint(
        '[samsung] synced ${exercises.length} workouts, ${sleep.length} nights, linked $linked, hr-series $hrFilled');
    return (exercises: exercises.length, sleep: sleep.length, linked: linked);
  }

  /// Manual trigger (Settings button) — requests permission then syncs, with a
  /// clear outcome for the UI.
  static Future<SyncResult> syncNow() async {
    final svc = SamsungHealthService.instance;
    if (!await svc.isAvailable()) {
      return const SyncResult(SyncOutcome.notSamsung);
    }
    var granted = await svc.grantedTypes();
    if (granted.isEmpty) granted = await svc.requestPermissions();
    if (granted.isEmpty) {
      return const SyncResult(SyncOutcome.notPermitted);
    }
    final r = await _sync();
    return SyncResult(SyncOutcome.ok,
        exercises: r.exercises, sleep: r.sleep, linked: r.linked);
  }
}

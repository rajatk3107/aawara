import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../workout/database/workout_database.dart';
import 'pending_supplement_taken.dart';
import 'supplement_events.dart';
import 'supplement_payload.dart';

/// Action button identifiers for interactive supplement reminders.
const String kSupplementMarkTakenAction = 'mark_taken';
const String kSupplementSnoozeAction = 'snooze';

String _todayDate() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Plugin-free queue file shared between the main isolate and the plugin's
/// background-action engine. `Directory.systemTemp` resolves to the app's cache
/// dir and is identical across both isolates because they run in the same
/// process — so no plugin (path_provider) is needed.
File _pendingTakenFile() =>
    File('${Directory.systemTemp.path}/pending_supplement_taken.txt');

/// Background isolate handler for notification actions tapped while the app is
/// backgrounded or killed. Runs in the plugin's separate FlutterEngine, which
/// has NO native plugins registered — so it must not touch sqflite. It records
/// "taken" to a plain file (dart:io only); the main isolate drains it into the
/// database on next launch/resume via [NotificationService.drainPendingTaken].
@pragma('vm:entry-point')
void supplementNotificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId != kSupplementMarkTakenAction) return;
  final payload = decodeSupplementPayload(response.payload);
  if (payload == null) return;
  try {
    _pendingTakenFile().writeAsStringSync(
      '${formatPendingTakenLine(payload.id, _todayDate())}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'workout_reminders';
  static const _channelName = 'Workout Reminders';

  // Interactive supplement reminders (Taken / Snooze actions).
  static const _supplementChannelId = 'supplement_reminders';
  static const _supplementChannelName = 'Supplement Reminders';

  // Rest-timer alert (one-shot, fired when a between-sets rest finishes).
  static const _restChannelId = 'rest_timer';
  static const _restChannelName = 'Rest Timer';
  static const _restNotifId = 9100;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse:
          supplementNotificationBackgroundHandler,
    );
    _initialized = true;

    // Diagnostic: with USE_EXACT_ALARM declared this should be true on Android
    // 13+. If false, scheduled reminders fall back to inexact and Samsung drops
    // them when the app is closed.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final canExact = await androidImpl.canScheduleExactNotifications();
      debugPrint('[notif] exact alarms allowed: $canExact');
    }
  }

  /// Foreground handler — runs while the app is alive. Mirrors the background
  /// handler for "mark taken" but also refreshes any open Supplements screen,
  /// and routes "snooze" to the in-app picker.
  static void _onForegroundResponse(NotificationResponse response) {
    final payload = decodeSupplementPayload(response.payload);
    if (payload == null) return;
    switch (response.actionId) {
      case kSupplementMarkTakenAction:
        WorkoutDatabase.instance.markSupplementTaken(payload.id, _todayDate());
        notifySupplementsChanged();
        instance.cancelById(1000 + payload.id);
        break;
      case kSupplementSnoozeAction:
        requestSnooze(payload);
        break;
    }
  }

  /// If the app was launched by tapping "Snooze" from a terminated state, the
  /// action arrives via launch details rather than the response callback. Route
  /// it to the in-app picker. Call once after [initialize].
  Future<void> handlePendingLaunchAction() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return;
    final resp = details.notificationResponse;
    if (resp?.actionId == kSupplementSnoozeAction) {
      final payload = decodeSupplementPayload(resp!.payload);
      if (payload != null) requestSnooze(payload);
    }
  }

  /// Applies any "taken" actions captured by the background handler while the
  /// app was backgrounded/killed. Call on launch and on resume. Idempotent —
  /// `supplement_logs` is keyed by (supplement_id, date). Bumps the refresh
  /// signal if anything was applied so an open Supplements screen updates.
  Future<void> drainPendingTaken() async {
    try {
      final file = _pendingTakenFile();
      if (!await file.exists()) return;
      final contents = await file.readAsString();
      await file.delete();
      final pending = parsePendingTaken(contents);
      if (pending.isEmpty) return;
      for (final p in pending) {
        await WorkoutDatabase.instance.markSupplementTaken(p.id, p.date);
      }
      notifySupplementsChanged();
    } catch (_) {}
  }

  /// Requests the POST_NOTIFICATIONS permission on Android 13+.
  /// Returns true if granted (or not needed).
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    // iOS: request at first schedule
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  }

  /// Schedules (or replaces) a weekly repeating notification for [weekday] (1=Mon … 7=Sun).
  Future<void> scheduleWorkoutReminder(
      int weekday, TimeOfDay time, String workoutName) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Weekly workout reminders from Aawara',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );

    final scheduled = _nextWeekdayOccurrence(weekday, time);
    await _plugin.zonedSchedule(
      weekday, // notification ID = weekday number (1–7), unique per day
      'Time to train 💪',
      '$workoutName is on your plan for today',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> cancelReminder(int weekday) async {
    await _plugin.cancel(weekday);
  }

  // Supplement reminders use notification IDs 1000 + supplementId to avoid
  // colliding with weekly workout reminders (IDs 1–7).
  static int supplementNotifId(int supplementId) => 1000 + supplementId;

  NotificationDetails _supplementDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _supplementChannelId,
        _supplementChannelName,
        channelDescription: 'Supplement reminders from Aawara',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        actions: [
          AndroidNotificationAction(
            kSupplementMarkTakenAction,
            '✓ Taken',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            kSupplementSnoozeAction,
            '💤 Snooze',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      ),
      iOS: DarwinNotificationDetails(categoryIdentifier: 'supplement'),
    );
  }

  String _supplementBody(String? dose) =>
      (dose != null && dose.isNotEmpty) ? '$dose · time to take it' : 'Time to take it';

  /// Schedules (or replaces) a daily repeating reminder for a supplement, with
  /// "Taken" and "Snooze" action buttons. Prefers an exact alarm so it still
  /// fires when the app is killed (inexact alarms are dropped/deferred by
  /// aggressive OEMs); falls back to inexact if exact-alarm access isn't granted.
  Future<void> scheduleSupplementReminder({
    required int supplementId,
    required String name,
    String? dose,
    required TimeOfDay time,
  }) async {
    await initialize();
    final scheduled = _nextDailyOccurrence(time);
    final payload =
        encodeSupplementPayload(id: supplementId, name: name, dose: dose);
    try {
      await _plugin.zonedSchedule(
        supplementNotifId(supplementId),
        '💊 $name',
        _supplementBody(dose),
        scheduled,
        _supplementDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        supplementNotifId(supplementId),
        '💊 $name',
        _supplementBody(dose),
        scheduled,
        _supplementDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    }
  }

  /// Reschedules a one-shot supplement reminder [minutes] from now (snooze).
  /// Cancels the original first, then fires a fresh copy with the same actions.
  Future<void> scheduleSnooze({
    required int supplementId,
    required String name,
    String? dose,
    required int minutes,
  }) async {
    await initialize();
    await _plugin.cancel(supplementNotifId(supplementId));
    final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    final payload =
        encodeSupplementPayload(id: supplementId, name: name, dose: dose);
    try {
      await _plugin.zonedSchedule(
        supplementNotifId(supplementId),
        '💊 $name',
        _supplementBody(dose),
        when,
        _supplementDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        supplementNotifId(supplementId),
        '💊 $name',
        _supplementBody(dose),
        when,
        _supplementDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }

  Future<void> cancelById(int id) async {
    await _plugin.cancel(id);
  }

  /// Schedules a one-shot notification to fire [seconds] from now, alerting the
  /// user that their between-sets rest is over. Scheduled at the OS level so it
  /// fires even if the app is backgrounded or the screen is off. Re-scheduling
  /// replaces any previously pending rest alert.
  Future<void> scheduleRestEnd({
    required int seconds,
    String? exerciseName,
  }) async {
    if (seconds <= 0) return;
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _restChannelId,
        _restChannelName,
        channelDescription: 'Alerts you when your rest timer finishes',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(),
    );
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    const title = 'Rest complete 💪';
    final body = (exerciseName != null && exerciseName.isNotEmpty)
        ? 'Time for your next set — $exerciseName'
        : 'Time for your next set!';
    // Prefer an exact alarm so the alert lands on time; fall back to inexact if
    // the OS hasn't granted exact-alarm access (Android 13+) so we never crash.
    try {
      await _plugin.zonedSchedule(
        _restNotifId, title, body, when, details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        _restNotifId, title, body, when, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelRestEnd() async {
    await _plugin.cancel(_restNotifId);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  tz.TZDateTime _nextDailyOccurrence(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// Returns the next [tz.TZDateTime] that falls on [weekday] at [time].
  tz.TZDateTime _nextWeekdayOccurrence(int weekday, TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    // Advance until we hit the right weekday and it's in the future
    while (candidate.weekday != weekday || candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}

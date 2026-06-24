import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../workout/database/workout_database.dart';
import 'supplement_events.dart';
import 'supplement_payload.dart';

/// Action button identifiers for interactive supplement reminders.
const String kSupplementMarkTakenAction = 'mark_taken';
const String kSupplementSnoozeAction = 'snooze';

String _todayDate() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Background isolate handler for notification actions tapped while the app is
/// backgrounded or killed. Must be a top-level/static function annotated for
/// AOT entry. Only "mark taken" needs to do work here; "snooze" launches the
/// app and is handled in the foreground.
@pragma('vm:entry-point')
void supplementNotificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId != kSupplementMarkTakenAction) return;
  final payload = decodeSupplementPayload(response.payload);
  if (payload == null) return;
  // ensureInitialized() registers plugins (incl. sqflite) for this isolate.
  WidgetsFlutterBinding.ensureInitialized();
  // Idempotent: supplement_logs is keyed by (supplement_id, date).
  WorkoutDatabase.instance.markSupplementTaken(payload.id, _todayDate());
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
  /// "Taken" and "Snooze" action buttons.
  Future<void> scheduleSupplementReminder({
    required int supplementId,
    required String name,
    String? dose,
    required TimeOfDay time,
  }) async {
    await initialize();
    final scheduled = _nextDailyOccurrence(time);
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
      payload: encodeSupplementPayload(id: supplementId, name: name, dose: dose),
    );
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

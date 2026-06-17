import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'workout_reminders';
  static const _channelName = 'Workout Reminders';

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
    );
    _initialized = true;
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

  /// Schedules a daily repeating notification at [time]. [id] should be unique
  /// per reminder (e.g., 1000 + supplement_id to avoid collision with weekly
  /// workout reminders which use IDs 1–7).
  Future<void> scheduleDailyReminder({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Daily reminders from Aawara',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    final scheduled = _nextDailyOccurrence(time);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
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

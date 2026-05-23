// ANDROID:
//   - Uses hardware pedometer via flutter_background_service
//   - Runs as a persistent foreground service
//   - Shows a permanent notification while counting
//   - Survives app kill; resets baseline at midnight
//   - Requires ACTIVITY_RECOGNITION permission
//   - May need battery optimization exemption on some ROMs
//
// iOS:
//   - Reads from Apple Health (HealthKit)
//   - Apple's motion coprocessor counts steps natively 24/7
//   - App just reads the data — zero battery impact
//   - Refreshes on foreground resume + BGAppRefreshTask
//   - Requires HealthKit entitlement + user permission
//   - No persistent notification needed or possible
//
// SHARED:
//   - Same step_goal_screen.dart for goal selection
//   - Same step_counter_card.dart for UI display
//   - Same SQLite step_logs table for history
//   - Same progress chart in Progress screen
//   - Same Settings UI structure (with platform-specific rows)

import 'dart:async';
import 'dart:io';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../workout/database/workout_database.dart';

class StepUpdate {
  final int steps;
  final int goal;
  const StepUpdate({required this.steps, required this.goal});
}

@pragma('vm:entry-point')
class StepTrackingService {
  static final _stepController =
      StreamController<StepUpdate>.broadcast();

  static Stream<StepUpdate> get stepStream => _stepController.stream;

  static Future<void> initialize() async {
    if (Platform.isAndroid && await isEnabled()) {
      // Configure the service early — this creates the 'aawara_steps'
      // notification channel before the WatchdogReceiver auto-starts the
      // background service. Without the channel the service crashes immediately
      // with CannotPostForegroundServiceNotificationException.
      await _configureAndroidService();
      _listenToAndroidUpdates();
    }
    // Actually start the service (and push initial steps) only after the first
    // frame — Activity is on-screen by then so Android 12+ won't throw
    // ForegroundServiceStartNotAllowedException.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid) await _startAndroidServiceIfNeeded();
      await refreshStream();
    });
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('step_tracking_enabled') ?? false;
  }

  // Called when user enables tracking from Settings
  // Returns true if successfully enabled
  static Future<bool> enable() async {
    if (Platform.isAndroid) {
      return _enableAndroid();
    } else if (Platform.isIOS) {
      return _enableIOS();
    }
    return false;
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('step_tracking_enabled', false);
    if (Platform.isAndroid) {
      FlutterBackgroundService().invoke('stopService');
    }
  }

  static Future<int> getTodaySteps() async {
    final manualAdd = await getManualStepsAdded();
    if (Platform.isIOS) {
      return await _getIosSteps() + manualAdd;
    }
    // Android — read latest value from DB (background service writes it)
    final today = _todayDate();
    final row = await WorkoutDatabase.instance.getStepLog(today);
    final automatic = row != null ? (row['steps'] as num).toInt() : 0;
    return automatic + manualAdd;
  }

  // Returns the manually added step offset for today.
  static Future<int> getManualStepsAdded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('step_manual_add_${_todayDate()}') ?? 0;
  }

  // Adds steps the user walked without their phone. Cumulative within a day.
  static Future<void> addManualSteps(int steps) async {
    if (steps <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'step_manual_add_${_todayDate()}';
    final existing = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, existing + steps);
    await refreshStream();
  }

  // Called on every app resume to ensure the Android service is running
  // (it may not have started successfully on cold-start on Android 12+).
  static Future<void> ensureAndroidServiceRunning() async {
    if (!Platform.isAndroid) return;
    await _startAndroidServiceIfNeeded();
  }

  // Push latest step count to UI stream — called on app open and resume.
  // On iOS this also writes to the DB so the progress chart stays current.
  // On Android, also reads Health Connect (Samsung Watch steps) and takes the max.
  static Future<void> refreshStream() async {
    if (!await isEnabled()) return;
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('step_goal') ?? 8000;
    var steps = await getTodaySteps();
    if (Platform.isIOS && steps > 0) {
      await WorkoutDatabase.instance.upsertStepLog(_todayDate(), steps, goal);
    }
    if (Platform.isAndroid) {
      // Silently merge Health Connect steps (includes Samsung Watch data)
      final hcSteps = await _getHealthConnectStepsForDay(DateTime.now());
      if (hcSteps > steps) {
        steps = hcSteps;
        await WorkoutDatabase.instance.upsertStepLog(_todayDate(), steps, goal);
      }
    }
    _stepController.add(StepUpdate(steps: steps, goal: goal));
  }

  // Reads today's steps from Health Connect (includes Samsung Watch).
  // Returns 0 if Health Connect is unavailable or permission not granted.
  static Future<int> _getHealthConnectStepsForDay(DateTime date) async {
    try {
      final health = Health();
      final start = DateTime(date.year, date.month, date.day);
      final end = date.year == DateTime.now().year &&
              date.month == DateTime.now().month &&
              date.day == DateTime.now().day
          ? DateTime.now()
          : DateTime(date.year, date.month, date.day, 23, 59, 59);
      final steps = await health.getTotalStepsInInterval(start, end);
      return steps ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // Syncs the past [days] days from Health Connect into the step_logs table.
  // Only increases step counts — never reduces an existing value.
  // Call this after granting Health Connect permission.
  static Future<({int updated, int skipped})> syncHealthConnectHistory({
    int days = 30,
  }) async {
    if (!Platform.isAndroid) return (updated: 0, skipped: 0);
    try {
      final health = Health();
      final authorized = await health.requestAuthorization(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
      if (!authorized) return (updated: 0, skipped: 0);

      final prefs = await SharedPreferences.getInstance();
      final goal = prefs.getInt('step_goal') ?? 8000;
      int updated = 0;
      int skipped = 0;

      for (int i = 0; i < days; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final hcSteps = await _getHealthConnectStepsForDay(date);
        if (hcSteps <= 0) {
          skipped++;
          continue;
        }
        final existing = await WorkoutDatabase.instance.getStepLog(dateStr);
        final existingSteps =
            existing != null ? (existing['steps'] as num).toInt() : 0;
        if (hcSteps > existingSteps) {
          await WorkoutDatabase.instance.upsertStepLog(dateStr, hcSteps, goal);
          updated++;
        } else {
          skipped++;
        }
      }
      return (updated: updated, skipped: skipped);
    } catch (_) {
      return (updated: 0, skipped: 0);
    }
  }

  // Returns true if Health Connect permission is already granted.
  static Future<bool> hasHealthConnectPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final health = Health();
      return await health.hasPermissions(
            [HealthDataType.STEPS],
            permissions: [HealthDataAccess.READ],
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ── Android ──────────────────────────────────────────────────────────────

  // Wire up the UI stream listener — includes manual offset on top of pedometer count.
  static void _listenToAndroidUpdates() {
    FlutterBackgroundService().on('stepUpdate').listen((data) async {
      if (data == null) return;
      final automatic = (data['steps'] as num?)?.toInt() ?? 0;
      final goal = (data['goal'] as num?)?.toInt() ?? 8000;
      final manualAdd = await getManualStepsAdded();
      _stepController.add(StepUpdate(
        steps: automatic + manualAdd,
        goal: goal,
      ));
    });
  }

  // Safe only after first frame: start the service if it isn't already running.
  static Future<void> _startAndroidServiceIfNeeded() async {
    if (!await isEnabled()) return;
    try {
      final svc = FlutterBackgroundService();
      final running = await svc.isRunning();
      if (!running) {
        await _configureAndroidService();
        await svc.startService();
      }
    } catch (_) {
      // ForegroundServiceStartNotAllowedException or similar — ignore,
      // the service will be started on the next foreground resume.
    }
  }

  static Future<bool> _enableAndroid() async {
    // 1. Request ACTIVITY_RECOGNITION permission
    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) return false;

    // 2. Configure (creates channel), wire listener, and start service
    await _configureAndroidService();
    _listenToAndroidUpdates();
    await FlutterBackgroundService().startService();

    // 3. Mark enabled
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('step_tracking_enabled', true);

    // 4. Show battery tip once
    await _maybeShowBatteryTip();

    return true;
  }

  static Future<void> _configureAndroidService() async {
    final svc = FlutterBackgroundService();
    await svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onAndroidServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'aawara_steps',
        initialNotificationTitle: 'Aawara · Step Counter',
        initialNotificationContent: 'Counting your steps…',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onAndroidServiceStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _onAndroidServiceStart(ServiceInstance service) async {
    final prefs = await SharedPreferences.getInstance();
    int? midnightBaseline;

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    // Listen to hardware pedometer
    Pedometer.stepCountStream.listen((StepCount event) async {
      final totalSinceBoot = event.steps;
      final today = _todayDate();
      final goal = prefs.getInt('step_goal') ?? 8000;

      // Resolve midnight baseline
      final storedBaseline = prefs.getInt('step_baseline_$today');
      if (storedBaseline == null) {
        midnightBaseline = totalSinceBoot;
        await prefs.setInt('step_baseline_$today', midnightBaseline!);
      } else if (totalSinceBoot < storedBaseline) {
        // Device rebooted — counter reset
        midnightBaseline = 0;
        await prefs.setInt('step_baseline_$today', 0);
      } else {
        midnightBaseline = storedBaseline;
      }

      final todaySteps = totalSinceBoot - midnightBaseline!;

      // Persist to SQLite
      await WorkoutDatabase.instance.upsertStepLog(today, todaySteps, goal);

      // Update foreground notification
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Aawara · $todaySteps steps today',
          content: todaySteps >= goal
              ? 'Daily goal reached!'
              : '${goal - todaySteps} steps to your goal',
        );
      }

      // Fire goal notification once per day
      final notifiedKey = 'step_goal_notified_$today';
      final notifyEnabled = prefs.getBool('step_notify_goal') ?? true;
      if (todaySteps >= goal &&
          notifyEnabled &&
          !(prefs.getBool(notifiedKey) ?? false)) {
        await prefs.setBool(notifiedKey, true);
        _fireGoalNotification(todaySteps, goal);
      }

      // Push to UI
      service.invoke('stepUpdate', {'steps': todaySteps, 'goal': goal});
    });

    // Midnight cleanup
    Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      if (now.hour == 0 && now.minute == 0) {
        prefs.remove('step_baseline_${_yesterdayDate()}');
        midnightBaseline = null;
      }
    });

    service.on('stopService').listen((_) => service.stopSelf());
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async =>
      true;

  static Future<void> _maybeShowBatteryTip() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('battery_tip_shown') ?? false) return;
    await prefs.setBool('battery_tip_shown', true);
    // The tip dialog is shown by the settings screen; we just set the flag
  }

  // ── iOS ───────────────────────────────────────────────────────────────────

  static Future<bool> _enableIOS() async {
    final health = Health();
    try {
      final authorized = await health.requestAuthorization(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
      if (!authorized) return false;
    } catch (_) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('step_tracking_enabled', true);
    return true;
  }

  static Future<int> _getIosSteps() async {
    try {
      final health = Health();
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await health.getTotalStepsInInterval(midnight, now);
      return steps ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Shared ────────────────────────────────────────────────────────────────

  static void _fireGoalNotification(int steps, int goal) {
    final plugin = FlutterLocalNotificationsPlugin();
    plugin.show(
      999,
      'Step goal reached!',
      'You hit $steps steps today — goal of $goal crushed!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aawara_steps_goal',
          'Step Goal Alerts',
          channelDescription:
              'Notifies when daily step goal is reached',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFFFD700),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
    );
  }

  static String _todayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _yesterdayDate() {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
  }
}

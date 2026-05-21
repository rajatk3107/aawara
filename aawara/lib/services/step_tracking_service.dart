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

class StepTrackingService {
  static final _stepController =
      StreamController<StepUpdate>.broadcast();

  static Stream<StepUpdate> get stepStream => _stepController.stream;

  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      await _initAndroid();
    }
    // iOS: no background init needed — reads HealthKit on demand
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
    if (Platform.isIOS) {
      return _getIosSteps();
    }
    // Android — read latest value from DB (background service writes it)
    final today = _todayDate();
    final row = await WorkoutDatabase.instance.getStepLog(today);
    return row != null ? (row['steps'] as num).toInt() : 0;
  }

  // Push latest step count to UI stream (called on app resume)
  static Future<void> refreshStream() async {
    if (!await isEnabled()) return;
    final steps = await getTodaySteps();
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('step_goal') ?? 8000;
    _stepController.add(StepUpdate(steps: steps, goal: goal));
  }

  // ── Android ──────────────────────────────────────────────────────────────

  static Future<void> _initAndroid() async {
    if (!await isEnabled()) return;
    final svc = FlutterBackgroundService();
    final running = await svc.isRunning();
    if (!running) {
      await _configureAndroidService();
      await svc.startService();
    }
    // Relay background service events to the UI stream
    svc.on('stepUpdate').listen((data) {
      if (data == null) return;
      _stepController.add(StepUpdate(
        steps: (data['steps'] as num?)?.toInt() ?? 0,
        goal: (data['goal'] as num?)?.toInt() ?? 8000,
      ));
    });
  }

  static Future<bool> _enableAndroid() async {
    // 1. Request ACTIVITY_RECOGNITION permission
    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) return false;

    // 2. Configure and start background service
    await _configureAndroidService();
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
        autoStart: true,
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

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
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:health/health.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  static final Health _health = Health();
  static bool _healthConfigured = false;
  static bool _nativeRegistrationLogged = false;
  static const _healthConnectTypes = [HealthDataType.STEPS];
  static const _healthConnectPermissions = [HealthDataAccess.READ];
  static const MethodChannel _healthConnectDiagnosticsChannel =
      MethodChannel('aawara/health_connect_diagnostics');

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
    final manualAdjustment = await getManualStepsAdded();
    if (Platform.isIOS) {
      final automatic = await _getIosSteps();
      return (automatic + manualAdjustment).clamp(0, 1 << 31).toInt();
    }
    // Android — read latest value from DB (background service writes it)
    final today = _todayDate();
    final row = await WorkoutDatabase.instance.getStepLog(today);
    final automatic = row != null ? (row['steps'] as num).toInt() : 0;
    return (automatic + manualAdjustment).clamp(0, 1 << 31).toInt();
  }

  // Returns the manual correction applied to today's automatic step count.
  static Future<int> getManualStepsAdded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('step_manual_add_${_todayDate()}') ?? 0;
  }

  // Sets today's displayed total. Internally this is stored as the correction
  // needed on top of the automatic count so future sensor updates keep moving.
  static Future<void> setManualStepCount(int finalSteps) async {
    if (finalSteps < 0) return;
    final prefs = await SharedPreferences.getInstance();
    final automatic = await _getAutomaticTodaySteps();
    final key = 'step_manual_add_${_todayDate()}';
    await prefs.setInt(key, finalSteps - automatic);
    if (Platform.isAndroid) {
      FlutterBackgroundService().invoke('manualStepUpdate', {
        'steps': finalSteps,
        'goal': prefs.getInt('step_goal') ?? 8000,
      });
      // Android: background service handles the stream update via stepUpdate event.
      // Calling refreshStream() here too would cause a duplicate emission.
    } else {
      await refreshStream();
    }
  }

  // Backwards-compatible wrapper for any older call sites.
  static Future<void> addManualSteps(int steps) async {
    if (steps <= 0) return;
    final current = await getTodaySteps();
    await setManualStepCount(current + steps);
  }

  static Future<int> _getAutomaticTodaySteps() async {
    if (Platform.isIOS) return _getIosSteps();
    final row = await WorkoutDatabase.instance.getStepLog(_todayDate());
    return row != null ? (row['steps'] as num).toInt() : 0;
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
    final manualAdjustment = await getManualStepsAdded();
    var automatic = await _getAutomaticTodaySteps();
    var steps = (automatic + manualAdjustment).clamp(0, 1 << 31).toInt();
    if (Platform.isIOS && automatic > 0) {
      await WorkoutDatabase.instance.upsertStepLog(_todayDate(), automatic, goal);
    }
    if (Platform.isAndroid) {
      // Silently merge Health Connect steps (includes Samsung Watch data)
      final hcSteps = await _getHealthConnectStepsForDay(DateTime.now());
      if (hcSteps > automatic) {
        automatic = hcSteps;
        await WorkoutDatabase.instance.upsertStepLog(
          _todayDate(),
          automatic,
          goal,
        );
        steps = (automatic + manualAdjustment).clamp(0, 1 << 31).toInt();
      }
    }
    _stepController.add(StepUpdate(steps: steps, goal: goal));
  }

  // Reads today's steps from Health Connect (includes Samsung Watch).
  // Returns 0 if Health Connect is unavailable or permission not granted.
  static Future<int> _getHealthConnectStepsForDay(
    DateTime date, {
    bool verbose = false,
  }) async {
    if (!Platform.isAndroid) return 0;
    final start = DateTime(date.year, date.month, date.day);
    // Always end the window at next-midnight — never at `now`. Samsung Health
    // writes a single step record that spans the WHOLE calendar day
    // (00:00:00 → 23:59:59.999) holding the day's running total. If we query
    // with end=now, Health Connect's aggregate() proportionally slices that
    // all-day record by the elapsed fraction of the day and returns an
    // undercount (e.g. 7335 steps → 6540 at 89% through the day). Ending at
    // next-midnight makes the window fully contain the record, so aggregate
    // returns the true total. No future steps exist, so this never overcounts.
    final end = DateTime(date.year, date.month, date.day + 1);

    try {
      final health = await _configuredHealth();
      final canRead = await _logHealthConnectDiagnostics(
        health,
        start: start,
        end: end,
        verbose: verbose,
      );
      if (!canRead) return 0;

      final records = await health.getHealthDataFromTypes(
        types: _healthConnectTypes,
        startTime: start,
        endTime: end,
      );
      if (verbose) {
        _logHealthConnect('Raw step records returned: ${records.length}');
        for (final point in records) {
          _logHealthDataPoint(point);
        }
      }

      final rawTotal = records.fold<int>(
        0,
        (sum, point) => sum + _pointSteps(point),
      );

      final steps = await health.getTotalStepsInInterval(start, end);
      if (verbose) {
        _logHealthConnect('Raw step total: $rawTotal');
        _logHealthConnect('Aggregated step count: ${steps ?? 'null'}');
      }
      return steps ?? rawTotal;
    } catch (error, stackTrace) {
      _logHealthConnect('Health Connect step read failed: $error');
      debugPrintStack(stackTrace: stackTrace);
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
      final health = await _configuredHealth();
      final authorized = await _ensureHealthConnectPermission(health);
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
    } catch (error, stackTrace) {
      _logHealthConnect('Health Connect history sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return (updated: 0, skipped: 0);
    }
  }

  // Returns true if Health Connect permission is already granted.
  static Future<bool> hasHealthConnectPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final health = await _configuredHealth();
      return await health.hasPermissions(
            _healthConnectTypes,
            permissions: _healthConnectPermissions,
          ) ??
          false;
    } catch (error, stackTrace) {
      _logHealthConnect('Health Connect permission check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<Health> _configuredHealth() async {
    if (!_healthConfigured) {
      await _health.configure();
      _healthConfigured = true;
      _logHealthConnect(
        'Health plugin configured; deviceId=${_health.deviceId}',
      );
    }
    await _logNativeHealthConnectRegistration();
    return _health;
  }

  static Future<bool> _ensureHealthConnectPermission(Health health) async {
    var granted = await health.hasPermissions(
          _healthConnectTypes,
          permissions: _healthConnectPermissions,
        ) ??
        false;
    _logHealthConnect('Permission granted before request: $granted');

    if (!granted) {
      _logHealthConnect(
        'Requesting permissions: types=$_healthConnectTypes, '
        'permissions=$_healthConnectPermissions',
      );
      _logHealthConnect('Launching Health Connect permission request intent');
      granted = await health.requestAuthorization(
        _healthConnectTypes,
        permissions: _healthConnectPermissions,
      );
      _logHealthConnect('Permission request result: $granted');
    }

    // Also request background read so the foreground service can keep the
    // count synced with the watch while the app UI is closed.
    await _ensureBackgroundReadPermission(health);
    return granted;
  }

  // Requests Health Connect's "read in background" permission if the device
  // supports it and it hasn't been granted yet. Non-fatal if declined — the
  // count still syncs whenever the app is open.
  static Future<void> _ensureBackgroundReadPermission(Health health) async {
    try {
      if (!await health.isHealthDataInBackgroundAvailable()) return;
      if (await health.isHealthDataInBackgroundAuthorized()) return;
      final ok = await health.requestHealthDataInBackgroundAuthorization();
      _logHealthConnect('Background read authorization result: $ok');
    } catch (error, stackTrace) {
      _logHealthConnect('Background read authorization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<bool> _logHealthConnectDiagnostics(
    Health health, {
    required DateTime start,
    required DateTime end,
    bool verbose = false,
  }) async {
    final available = await health.isHealthConnectAvailable();
    final granted = await health.hasPermissions(
          _healthConnectTypes,
          permissions: _healthConnectPermissions,
        ) ??
        false;
    if (verbose) {
      final sdkStatus = await health.getHealthConnectSdkStatus();
      _logHealthConnect('SDK status: $sdkStatus');
      _logHealthConnect('Available: $available');
      _logHealthConnect(
        'Requested permissions: types=$_healthConnectTypes, '
        'permissions=$_healthConnectPermissions',
      );
      _logHealthConnect('Permission granted: $granted');
      _logHealthConnect('Platform: ${health.platformType}');
      _logHealthConnect('Start local: $start, utc: ${start.toUtc()}');
      _logHealthConnect('End local: $end, utc: ${end.toUtc()}');
      _logHealthConnect(
        'Epoch ms: ${start.millisecondsSinceEpoch} -> '
        '${end.millisecondsSinceEpoch}',
      );
    }
    return available && granted;
  }

  static void _logHealthDataPoint(HealthDataPoint point) {
    _logHealthConnect(
      'HealthDataPoint '
      'type=${point.type}, value=${point.value}, '
      'from=${point.dateFrom} (${point.dateFrom.toUtc()}), '
      'to=${point.dateTo} (${point.dateTo.toUtc()}), '
      'sourceName=${point.sourceName}, sourceId=${point.sourceId}, '
      'deviceId=${point.sourceDeviceId}, deviceModel=${point.deviceModel}, '
      'recordingMethod=${point.recordingMethod}, '
      'platform=${point.sourcePlatform}, metadata=${point.metadata}',
    );
  }

  static int _pointSteps(HealthDataPoint point) {
    final value = point.value;
    if (value is NumericHealthValue) {
      return value.numericValue.round();
    }
    final match = RegExp(r'[-+]?\d+(\.\d+)?').firstMatch(value.toString());
    return match == null ? 0 : (double.tryParse(match.group(0)!) ?? 0).round();
  }

  static void _logHealthConnect(String message) {
    debugPrint('[HealthConnectSteps] $message');
  }

  static Future<void> _logNativeHealthConnectRegistration() async {
    if (!Platform.isAndroid || _nativeRegistrationLogged) return;
    _nativeRegistrationLogged = true;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _logHealthConnect(
        'Flutter package info: package=${packageInfo.packageName}, '
        'appName=${packageInfo.appName}, '
        'version=${packageInfo.version}+${packageInfo.buildNumber}',
      );

      final diagnostics = await _healthConnectDiagnosticsChannel
          .invokeMapMethod<String, dynamic>('inspect');
      _logHealthConnect('Native registration diagnostics: $diagnostics');
    } catch (error, stackTrace) {
      _logHealthConnect(
        'Native Health Connect registration diagnostics failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ── Android ──────────────────────────────────────────────────────────────

  // Wire up the UI stream listener. Android service updates already include
  // the manual correction used by the foreground notification.
  static void _listenToAndroidUpdates() {
    FlutterBackgroundService().on('stepUpdate').listen((data) async {
      if (data == null) return;
      final steps = (data['steps'] as num?)?.toInt() ?? 0;
      final goal = (data['goal'] as num?)?.toInt() ?? 8000;
      _stepController.add(StepUpdate(
        steps: steps,
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
    } catch (error, stackTrace) {
      _logHealthConnect('Android step service start failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      // The service will be started on the next foreground resume.
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

    // 4. Request Health Connect read (incl. background) so the watch total
    //    keeps the count in sync even when the app is closed. Non-fatal.
    try {
      await _ensureHealthConnectPermission(await _configuredHealth());
    } catch (error, stackTrace) {
      _logHealthConnect('Health Connect enable-time auth failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    // 5. Show battery tip once
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
    // Register plugins for this background isolate so the `health` plugin
    // (Health Connect reads) works here, not just on the UI isolate.
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    int? midnightBaseline;
    int latestPedometerSteps = 0; // today's count from the phone pedometer
    int latestHcSteps = 0; // today's total from Health Connect (the watch)
    int latestAutomaticSteps = 0; // merged max(pedometer, HC) — used everywhere
    final androidService =
        service is AndroidServiceInstance ? service : null;

    // Seed a floor from the last persisted value so the displayed count never
    // visibly drops to 0 while the service restarts and re-reads its sources.
    final seed = await WorkoutDatabase.instance.getStepLog(_todayDate());
    if (seed != null) {
      latestHcSteps = (seed['steps'] as num).toInt();
      latestAutomaticSteps = latestHcSteps;
    }

    Future<void> updateForegroundNotification(int steps, int goal) async {
      if (androidService != null) {
        androidService.setForegroundNotificationInfo(
          title: 'Aawara · $steps steps today',
          content: steps >= goal
              ? 'Daily goal reached!'
              : '${goal - steps} steps to your goal',
        );
      }
    }

    if (androidService != null) {
      androidService.setAsForegroundService();
    }

    // Single place that merges the two sources and pushes the result out.
    // Health Connect (the watch) is authoritative; the phone pedometer only
    // adds live increments and can NEVER pull the count below the HC value.
    // Both the DB and the foreground notification reflect this merged total.
    Future<void> pushUpdate() async {
      final today = _todayDate();
      final goal = prefs.getInt('step_goal') ?? 8000;
      // Reload so manual corrections written by the UI isolate are visible.
      await prefs.reload();
      final manualAdjustment = prefs.getInt('step_manual_add_$today') ?? 0;

      final automatic = latestPedometerSteps > latestHcSteps
          ? latestPedometerSteps
          : latestHcSteps;
      latestAutomaticSteps = automatic;
      final adjustedSteps =
          (automatic + manualAdjustment).clamp(0, 1 << 31).toInt();

      await WorkoutDatabase.instance.upsertStepLog(today, automatic, goal);
      await updateForegroundNotification(adjustedSteps, goal);

      // Fire goal notification once per day
      final notifiedKey = 'step_goal_notified_$today';
      final notifyEnabled = prefs.getBool('step_notify_goal') ?? true;
      if (adjustedSteps >= goal &&
          notifyEnabled &&
          !(prefs.getBool(notifiedKey) ?? false)) {
        await prefs.setBool(notifiedKey, true);
        _fireGoalNotification(adjustedSteps, goal);
      }

      service.invoke('stepUpdate', {'steps': adjustedSteps, 'goal': goal});
    }

    // Pull the watch's step total from Health Connect. Runs on a timer so steps
    // walked with the phone stationary (counted only by the watch) still show.
    // latestHcSteps only ever increases within a day, so a transient empty read
    // (e.g. background read momentarily blocked) can't drop the count.
    Future<void> pollHealthConnect() async {
      try {
        final hc = await _getHealthConnectStepsForDay(DateTime.now());
        if (hc > latestHcSteps) {
          latestHcSteps = hc;
          _logHealthConnect('Background HC sync: $hc steps');
          await pushUpdate();
        }
      } catch (error, stackTrace) {
        _logHealthConnect('Background Health Connect poll failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    service.on('manualStepUpdate').listen((data) async {
      final goal = (data?['goal'] as num?)?.toInt() ??
          prefs.getInt('step_goal') ??
          8000;
      final providedSteps = (data?['steps'] as num?)?.toInt();
      final manualAdjustment =
          prefs.getInt('step_manual_add_${_todayDate()}') ?? 0;
      final adjustedSteps = providedSteps ??
          (latestAutomaticSteps + manualAdjustment).clamp(0, 1 << 31).toInt();
      await updateForegroundNotification(adjustedSteps, goal);
      service.invoke('stepUpdate', {'steps': adjustedSteps, 'goal': goal});
    });

    // Listen to the hardware pedometer for live increments between HC syncs.
    Pedometer.stepCountStream.listen((StepCount event) async {
      final totalSinceBoot = event.steps;
      final today = _todayDate();

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

      latestPedometerSteps = totalSinceBoot - midnightBaseline!;
      await pushUpdate();
    });

    // Correct against Health Connect now, then every 30s.
    await pollHealthConnect();
    final hcTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => pollHealthConnect(),
    );

    // Midnight cleanup
    Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      if (now.hour == 0 && now.minute == 0) {
        prefs.remove('step_baseline_${_yesterdayDate()}');
        midnightBaseline = null;
        latestPedometerSteps = 0;
        latestHcSteps = 0;
        latestAutomaticSteps = 0;
      }
    });

    service.on('stopService').listen((_) {
      hcTimer.cancel();
      service.stopSelf();
    });
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
    final health = await _configuredHealth();
    try {
      final authorized = await health.requestAuthorization(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
      if (!authorized) return false;
    } catch (error, stackTrace) {
      _logHealthConnect('iOS health authorization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('step_tracking_enabled', true);
    return true;
  }

  static Future<int> _getIosSteps() async {
    try {
      final health = await _configuredHealth();
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await health.getTotalStepsInInterval(midnight, now);
      return steps ?? 0;
    } catch (error, stackTrace) {
      _logHealthConnect('iOS step read failed: $error');
      debugPrintStack(stackTrace: stackTrace);
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_log.dart';
import '../widgets/exercise_tile.dart';
import '../widgets/muscle_group_filter.dart';
import '../../utils/safe_navigation.dart';
import '../../services/notification_service.dart';
import 'workout_complete_screen.dart';
import 'quick_start_screen.dart';

class WorkoutLoggingScreen extends StatefulWidget {
  final WorkoutLog workoutLog;
  const WorkoutLoggingScreen({super.key, required this.workoutLog});

  @override
  State<WorkoutLoggingScreen> createState() => _WorkoutLoggingScreenState();
}

class _WorkoutLoggingScreenState extends State<WorkoutLoggingScreen>
    with WidgetsBindingObserver {
  final _db = WorkoutDatabase.instance;
  late WorkoutLog _log;

  final Map<String, Exercise> _exercises = {};
  final Map<String, String?> _hints = {}; // exLogId → "weight × reps" hint
  final Map<String, ({double weight, String reason})?> _suggestions = {}; // exLogId → progression target
  bool _loading = true;

  int _elapsedSeconds = 0;
  Timer? _durationTimer;
  bool _paused = false;

  // Wall-clock start time, adjusted whenever manual pause/resume happens
  DateTime? _workoutStartTime;
  // Snapshot of elapsed at the moment the user manually paused
  int _elapsedAtPause = 0;

  // Accordion: which exercise is currently expanded
  String? _expandedId;

  // Plateau alerts — exerciseId set for O(1) lookup
  final Set<String> _plateauedIds = {};

  // Per-exercise note controllers (keyed by exerciseLog.id)
  final Map<String, TextEditingController> _noteControllers = {};

  // Exercises that have already shown the overload nudge this session
  final Set<String> _nudgedExercises = {};

  // Set IDs that achieved a PR this session (drives ⭐ badge)
  final Map<String, bool> _setPRs = {};

  // Rest timer
  Timer? _restTimer;
  int _restRemaining = 0;
  int _restTotal = 90;
  int _restDefault = 90; // loaded from prefs, user-configurable
  bool _restExpanded = false;
  bool _restDone = false;
  bool _restNotifAsked = false; // request notification permission once per screen
  final Map<String, int> _exerciseRestOverrides = {};

  @override
  void initState() {
    super.initState();
    _log = widget.workoutLog;
    WidgetsBinding.instance.addObserver(this);

    if (_log.completed) {
      // View mode — show stored duration, no running timer
      _elapsedSeconds = _log.durationSeconds ?? 0;
    } else {
      if (_log.exercises.isNotEmpty) {
        _expandedId = _log.exercises.first.id;
      }
      _initTimer();
      _loadRestDefault();
    }
    _loadDetails();
  }

  // Load persisted timer state so the timer survives screen pops/pushes.
  Future<void> _initTimer() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedMs = prefs.getInt('wl_start_${_log.id}');
    final savedPausedElapsed = prefs.getInt('wl_paused_elapsed_${_log.id}');
    if (savedMs != null) {
      _workoutStartTime = DateTime.fromMillisecondsSinceEpoch(savedMs);
      if (savedPausedElapsed != null) {
        setState(() {
          _paused = true;
          _elapsedAtPause = savedPausedElapsed;
          _elapsedSeconds = savedPausedElapsed;
        });
      } else {
        _startDurationTimer();
      }
    } else {
      _workoutStartTime = DateTime.now();
      prefs.setInt('wl_start_${_log.id}', _workoutStartTime!.millisecondsSinceEpoch);
      _startDurationTimer();
    }
  }

  // Fire-and-forget: persist current timer anchor so we can resume after a pop.
  void _saveTimerState() {
    if (_log.completed || _workoutStartTime == null) return;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('wl_start_${_log.id}', _workoutStartTime!.millisecondsSinceEpoch);
      if (_paused) {
        prefs.setInt('wl_paused_elapsed_${_log.id}', _elapsedAtPause);
      } else {
        prefs.remove('wl_paused_elapsed_${_log.id}');
      }
    });
  }

  void _clearTimerState() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('wl_start_${_log.id}');
      prefs.remove('wl_paused_elapsed_${_log.id}');
    });
  }

  Future<void> _loadRestDefault() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _restDefault = prefs.getInt('rest_default_seconds') ?? 90);
  }

  Future<void> _saveRestDefault(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rest_default_seconds', seconds);
    setState(() => _restDefault = seconds);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _restTimer?.cancel();
    // Cancel a still-pending rest alert if the user leaves mid-rest.
    if (_restRemaining > 0) NotificationService.instance.cancelRestEnd();
    _saveTimerState();
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_log.completed || _workoutStartTime == null) return;
    if (state == AppLifecycleState.resumed && !_paused) {
      _startDurationTimer();
    } else if (state == AppLifecycleState.paused) {
      _durationTimer?.cancel();
      _saveTimerState();
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds =
            DateTime.now().difference(_workoutStartTime!).inSeconds;
      });
    });
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final exLog in _log.exercises) {
        final ex = await _db.getExerciseById(exLog.exerciseId);
        if (ex != null) _exercises[exLog.id] = ex;

        _noteControllers.putIfAbsent(
          exLog.id,
          () => TextEditingController(text: exLog.notes ?? ''),
        );

        // Build hint from last session
        final prev = await _db.getLastSetsForExercise(exLog.exerciseId);
        if (prev.isNotEmpty) {
          final s = prev.first;
          if (ex != null && !ex.isCardio && s.weight != null && s.reps != null) {
            _hints[exLog.id] = '${_fmtW(s.weight!)} × ${s.reps}';
          }
        }
        // Build progression suggestion from last completed session (excluding today's)
        if (ex != null && !ex.isCardio) {
          final last = await _db.getLastCompletedSetsForExercise(
              exLog.exerciseId, _log.date);
          if (last != null) {
            _suggestions[exLog.id] = _computeSuggestion(last.sets);
          }
        }

        final override = prefs.getInt('rest_timer_${exLog.exerciseId}');
        if (override != null) _exerciseRestOverrides[exLog.exerciseId] = override;
      }
    } finally {
      // Always clear the loading flag so a failed query can't leave the screen
      // stuck on a blank/loading state until the app is restarted.
      if (mounted) setState(() => _loading = false);
    }

    // Load plateau data in background — failure is silent
    _db.getPlateauedExercises().then((alerts) {
      if (!mounted) return;
      setState(() {
        _plateauedIds
          ..clear()
          ..addAll(alerts.map((a) => a.exerciseId));
      });
    }).catchError((_) {});
  }

  String get _durationStr {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtW(double w) =>
      w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

  // Suggests a target weight based on last session's performance.
  // Double-progression rule: when min reps on top set ≥ 10 → bump 2.5 kg;
  // otherwise maintain weight and aim to add reps. Returns null if no
  // usable weight/reps data.
  ({double weight, String reason})? _computeSuggestion(List<SetLog> lastSets) {
    final wReps = lastSets
        .where((s) => s.weight != null && s.reps != null && s.weight! > 0)
        .toList();
    if (wReps.isEmpty) return null;
    double maxW = 0;
    for (final s in wReps) {
      if (s.weight! > maxW) maxW = s.weight!;
    }
    final topSets = wReps.where((s) => s.weight == maxW).toList();
    int minReps = topSets.first.reps!;
    for (final s in topSets) {
      if (s.reps! < minReps) minReps = s.reps!;
    }
    if (minReps >= 10) {
      return (weight: maxW + 2.5, reason: 'crushed last time');
    } else if (minReps >= 6) {
      return (weight: maxW, reason: 'add a rep');
    } else {
      return (weight: maxW, reason: 'lock in form');
    }
  }

  String? _hintLine(String exLogId) {
    final h = _hints[exLogId];
    if (h == null) return null;
    final parts = h.split(' × ');
    if (parts.length != 2) return 'Last: $h';
    final w = double.tryParse(parts[0]);
    final r = int.tryParse(parts[1]);
    final orm = (w != null && r != null && r > 0)
        ? '   1RM ~ ${(w * (1 + r / 30)).toStringAsFixed(0)} kg'
        : '';
    return 'Last: $h$orm';
  }

  // ─── Rest Timer ───────────────────────────────────────────────────────────────

  void _startRest(int seconds, {String? exerciseId, String? exerciseName}) {
    _restTimer?.cancel();
    setState(() {
      _restRemaining = seconds;
      _restTotal = seconds;
      _restDone = false;
      _restExpanded = false;
    });
    // OS-level alert so the user is notified when rest ends even if the app is
    // backgrounded or the screen is off (the in-app Timer can't fire then).
    if (!_restNotifAsked) {
      _restNotifAsked = true;
      NotificationService.instance.requestPermission();
    }
    NotificationService.instance
        .scheduleRestEnd(seconds: seconds, exerciseName: exerciseName);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final next = _restRemaining - 1;
      setState(() {
        _restRemaining = next < 0 ? 0 : next;
        if (next <= 0) _restDone = true;
      });
      if (next <= 0) {
        t.cancel();
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 200), HapticFeedback.heavyImpact);
        Future.delayed(const Duration(milliseconds: 400), HapticFeedback.heavyImpact);
        Future.delayed(const Duration(seconds: 1), () {
          // Natural end: keep the fired notification in the tray.
          if (mounted) _cancelRest(clearNotification: false);
        });
      }
    });
  }

  // [clearNotification] is false only on natural completion (the alert has
  // already fired); true when the user skips/cancels rest early.
  void _cancelRest({bool clearNotification = true}) {
    _restTimer?.cancel();
    if (clearNotification) NotificationService.instance.cancelRestEnd();
    setState(() {
      _restRemaining = 0;
      _restDone = false;
      _restExpanded = false;
    });
  }

  int _getRestSeconds(String exerciseId) =>
      _exerciseRestOverrides[exerciseId] ?? _restDefault;

  String _fmtRestTime(int seconds) {
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    return '${seconds}s';
  }

  Future<void> _saveExerciseRest(String exerciseId, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rest_timer_$exerciseId', seconds);
    if (mounted) setState(() => _exerciseRestOverrides[exerciseId] = seconds);
  }

  Future<void> _clearExerciseRest(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rest_timer_$exerciseId');
    if (mounted) setState(() => _exerciseRestOverrides.remove(exerciseId));
  }

  void _showExerciseRestPicker(ExerciseLog exLog) {
    const options = [60, 90, 120, 180, 240];
    final exerciseId = exLog.exerciseId;
    final current = _exerciseRestOverrides[exerciseId];
    final exName = _exercises[exLog.id]?.name ?? 'Exercise';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rest Timer · $exName',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Custom rest for this exercise across all sessions.',
              style: TextStyle(color: Color(0xFF555577), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...options.map((s) {
                  final label = _fmtRestTime(s);
                  final selected = s == current;
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      await _saveExerciseRest(exerciseId, s);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                            : const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF1E1E35),
                        ),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              color: selected
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFFCCCCDD),
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14)),
                    ),
                  );
                }),
                if (current != null)
                  GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      await _clearExerciseRest(exerciseId);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                const Color(0xFFE74C3C).withValues(alpha: 0.4)),
                      ),
                      child: const Text('Use default',
                          style: TextStyle(
                              color: Color(0xFFE74C3C), fontSize: 14)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRestDurationPicker() {
    const options = [30, 45, 60, 90, 120, 180, 240];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Default Rest Time',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Long-press the rest bar to change anytime.',
                style: TextStyle(color: Color(0xFF555577), fontSize: 12)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: options.map((s) {
                final label =
                    s >= 60 ? '${s ~/ 60}m${s % 60 > 0 ? ' ${s % 60}s' : ''}' : '${s}s';
                final selected = s == _restDefault;
                return GestureDetector(
                  onTap: () {
                    _saveRestDefault(s);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3498DB).withValues(alpha: 0.15)
                          : const Color(0xFF0D0D1A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF3498DB)
                            : const Color(0xFF1E1E35),
                      ),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            color: selected
                                ? const Color(0xFF3498DB)
                                : const Color(0xFFCCCCDD),
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Set actions ──────────────────────────────────────────────────────────────

  Future<void> _toggleCheck(ExerciseLog exLog, SetLog setLog) async {
    final next = !setLog.isCompleted;
    final updated = setLog.copyWith(isCompleted: next);
    await _db.updateSetLog(updated);
    setState(() {
      final idx = exLog.sets.indexWhere((s) => s.id == setLog.id);
      if (idx >= 0) exLog.sets[idx] = updated;
    });
    if (next && !_log.completed) {
      _startRest(_getRestSeconds(exLog.exerciseId),
          exerciseId: exLog.exerciseId,
          exerciseName: _exercises[exLog.id]?.name);
      _checkPR(exLog, updated);
      _checkOverloadNudge(exLog);
    }
  }

  Future<void> _checkOverloadNudge(ExerciseLog exLog) async {
    final exerciseId = exLog.exerciseId;
    if (_nudgedExercises.contains(exerciseId)) return;

    // Best volume in the current session for this exercise
    final completedSets = exLog.sets
        .where((s) => s.isCompleted && s.weight != null && s.reps != null);
    if (completedSets.isEmpty) return;

    final bestSet = completedSets
        .reduce((a, b) => a.volume >= b.volume ? a : b);
    final currentBest = bestSet.volume;
    if (currentBest <= 0) return;

    // Get the last 2 completed sessions for this exercise
    final sessions = await _db.getLastNSessionsForExercise(exerciseId, 2);
    if (sessions.length < 2) return;

    double sessionBest(List<SetLog> sets) => sets
        .where((s) => s.weight != null && s.reps != null)
        .fold(0.0, (best, s) => s.volume > best ? s.volume : best);

    final prev1 = sessionBest(sessions[0]);
    final prev2 = sessionBest(sessions[1]);

    if (currentBest != prev1 || currentBest != prev2) return;

    _nudgedExercises.add(exerciseId);

    final w = bestSet.weight!.toStringAsFixed(1);
    final r = bestSet.reps!;
    final suggested = (bestSet.weight! + 2.5).toStringAsFixed(1);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "You've hit ${w}kg × $r three times in a row. "
          "Try ${suggested}kg next set? 💪",
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Got it',
          textColor: const Color(0xFFFFD700),
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _checkPR(ExerciseLog exLog, SetLog setLog) async {
    final w = setLog.weight;
    final r = setLog.reps;
    if (w == null || r == null || r == 0) return;

    final orm = w * (1 + r / 30.0); // Epley formula
    final storedBest = await _db.getBest1RM(exLog.exerciseId);
    if (storedBest != null && orm <= storedBest) return;

    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _db.updateBest1RM(exLog.exerciseId, orm, date);

    if (!mounted) return;
    setState(() => _setPRs[setLog.id] = true);
    HapticFeedback.heavyImpact();

    final exName = _exercises[exLog.id]?.name ?? '';
    _showPRCelebration(exName, orm);
  }

  void _showPRCelebration(String exerciseName, double orm) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (_) => _PRCelebrationDialog(
        exerciseName: exerciseName,
        orm: orm,
      ),
    );
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  Future<void> _addSet(ExerciseLog exLog) async {
    const uuid = Uuid();
    final ex = _exercises[exLog.id];
    final isCardio = ex?.isCardio ?? false;

    double? w;
    int? r;
    int? durSec;
    double? speed;
    double? incline;
    double? resistance;
    double? distKm;

    if (exLog.sets.isNotEmpty) {
      final last = exLog.sets.last;
      w = last.weight;
      r = last.reps;
      durSec = last.durationSeconds;
      speed = last.speed;
      incline = last.incline;
      resistance = last.resistance;
      distKm = last.distanceKm;
    } else if (!isCardio) {
      final hint = _hints[exLog.id];
      if (hint != null) {
        final parts = hint.split(' × ');
        if (parts.length == 2) {
          w = double.tryParse(parts[0]);
          r = int.tryParse(parts[1]);
        }
      }
    }

    final newSet = SetLog(
      id: uuid.v4(),
      exerciseLogId: exLog.id,
      setNumber: exLog.sets.length + 1,
      weight: isCardio ? null : w,
      reps: isCardio ? null : r,
      durationSeconds: isCardio ? (durSec ?? 60 * 20) : null,
      speed: speed,
      incline: incline,
      resistance: resistance,
      distanceKm: distKm,
    );
    final saved = await _db.createSetLog(newSet);
    setState(() => exLog.sets.add(saved));
  }

  Future<void> _updateSet(ExerciseLog exLog, SetLog updated) async {
    await _db.updateSetLog(updated);
    setState(() {
      final idx = exLog.sets.indexWhere((s) => s.id == updated.id);
      if (idx >= 0) exLog.sets[idx] = updated;
    });
  }

  Future<void> _deleteSet(ExerciseLog exLog, SetLog setLog) async {
    await _db.deleteSetLog(setLog.id);
    setState(() {
      exLog.sets.removeWhere((s) => s.id == setLog.id);
      for (int i = 0; i < exLog.sets.length; i++) {
        exLog.sets[i] = exLog.sets[i].copyWith(setNumber: i + 1);
      }
    });
  }

  // ─── Exercise actions ─────────────────────────────────────────────────────────

  Future<void> _removeExercise(ExerciseLog exLog) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Exercise',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove "${_exercises[exLog.id]?.name ?? 'this exercise'}" from the workout?',
          style: const TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteExerciseLog(exLog.id);
      _noteControllers.remove(exLog.id)?.dispose();
      setState(() {
        _log.exercises.removeWhere((e) => e.id == exLog.id);
        if (_expandedId == exLog.id) {
          _expandedId = _log.exercises.isNotEmpty ? _log.exercises.first.id : null;
        }
      });
    }
  }

  Future<void> _addExerciseToLog() async {
    final picked = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(builder: (_) => const _InlineExercisePicker()),
    );
    if (picked == null || !mounted) return;
    const uuid = Uuid();
    final exLog = ExerciseLog(
      id: uuid.v4(),
      workoutLogId: _log.id,
      exerciseId: picked.id,
      orderIndex: _log.exercises.length,
    );
    await _db.createExerciseLog(exLog);
    _exercises[exLog.id] = picked;
    _noteControllers[exLog.id] = TextEditingController();
    final prev = await _db.getLastSetsForExercise(picked.id);
    if (prev.isNotEmpty && !picked.isCardio) {
      final s = prev.first;
      if (s.weight != null && s.reps != null) {
        _hints[exLog.id] = '${_fmtW(s.weight!)} × ${s.reps}';
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getInt('rest_timer_${picked.id}');
    if (override != null) _exerciseRestOverrides[picked.id] = override;
    setState(() {
      _log.exercises.add(exLog);
      _expandedId = exLog.id;
    });
  }

  void _onReorder(int oldIdx, int newIdx) {
    setState(() {
      if (newIdx > oldIdx) newIdx--;
      final item = _log.exercises.removeAt(oldIdx);
      _log.exercises.insert(newIdx, item);
      // Update orderIndex in memory (DB update happens on save/complete)
      for (int i = 0; i < _log.exercises.length; i++) {
        _log.exercises[i] = ExerciseLog(
          id: _log.exercises[i].id,
          workoutLogId: _log.exercises[i].workoutLogId,
          exerciseId: _log.exercises[i].exerciseId,
          orderIndex: i,
          sets: _log.exercises[i].sets,
        );
      }
    });
  }

  // ─── Workout completion ───────────────────────────────────────────────────────

  Future<void> _completeWorkout() async {
    final allEmpty = _log.exercises.every((e) => e.sets.isEmpty);
    if (allEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Log at least one set before completing.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFE74C3C),
      ));
      return;
    }

    // Two-step confirmation — finishing stops the timer, so guard against taps.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Finish Workout?',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'This ends your session and stops the timer at $_durationStr. '
          'You can re-open it later to keep going.',
          style: const TextStyle(color: Color(0xFFAAAABB), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Going',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child:
                const Text('Finish', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _durationTimer?.cancel();
    _clearTimerState();
    final updated = _log.copyWith(completed: true, durationSeconds: _elapsedSeconds);
    await _db.updateWorkoutLog(updated);
    setState(() => _log = updated);
    if (!mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutCompleteScreen(
          log: _log,
          exercises: _exercises,
          elapsedSeconds: _elapsedSeconds,
        ),
      ),
    );
    if (result == 'add_session' && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuickStartScreen(targetDate: _log.date),
        ),
      );
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _undoComplete() async {
    final updated = _log.copyWith(completed: false);
    await _db.updateWorkoutLog(updated);
    final resumeFrom = updated.durationSeconds ?? 0;
    setState(() {
      _log = updated;
      _elapsedSeconds = resumeFrom;
      _paused = false;
      // Re-anchor the wall-clock start so the timer continues from where it was
      // left off instead of restarting at 0.
      _workoutStartTime =
          DateTime.now().subtract(Duration(seconds: resumeFrom));
    });
    // Re-persist the start time so re-opening the screen resumes correctly.
    _saveTimerState();
    _startDurationTimer();
  }

  // ─── Manual value input ───────────────────────────────────────────────────────

  Future<void> _editValue(
    String title,
    double current,
    bool isInt,
    ValueChanged<double> onSave,
  ) async {
    final ctrl = TextEditingController(
      text: isInt ? current.toInt().toString() : _fmtW(current),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintStyle: TextStyle(color: Color(0xFF444466)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => popAfterFocusSettles(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              popAfterFocusSettles(ctx, v);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Set', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) onSave(result);
  }

  Future<void> _editDuration(ExerciseLog exLog, SetLog setLog) async {
    final cur = setLog.durationSeconds ?? 0;
    final mm = cur ~/ 60;
    final ss = cur % 60;
    final mmCtrl = TextEditingController(text: mm.toString());
    final ssCtrl = TextEditingController(text: ss.toString().padLeft(2, '0'));
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Duration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: mmCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'MM'),
              ),
            ),
            const Text(':', style: TextStyle(color: Colors.white54, fontSize: 24)),
            SizedBox(
              width: 60,
              child: TextField(
                controller: ssCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'SS'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => popAfterFocusSettles(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              final m = int.tryParse(mmCtrl.text) ?? 0;
              final s = int.tryParse(ssCtrl.text) ?? 0;
              popAfterFocusSettles(ctx, m * 60 + s);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Set', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    mmCtrl.dispose();
    ssCtrl.dispose();
    if (result != null) {
      _updateSet(exLog, setLog.copyWith(durationSeconds: result));
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D1A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
      );
    }

    final totalSets = _log.exercises.fold(0, (s, e) => s + e.sets.length);
    final checkedCount = _log.exercises.fold(0, (s, e) => s + e.sets.where((st) => st.isCompleted).length);
    final totalVol = _log.exercises.fold(0.0, (s, e) => s + e.totalVolume);
    final exWithSets = _log.exercises.where((e) => e.sets.isNotEmpty).length;
    final progress = totalSets > 0 ? (checkedCount / totalSets).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      // Resize so the keyboard pushes the content up instead of covering it —
      // otherwise the exercise note field stays hidden behind the keyboard.
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          _buildHeader(),
          _buildProgress(checkedCount, totalSets, exWithSets, totalVol, progress),
          Expanded(
            child: _log.exercises.isEmpty
                ? _buildEmptyState()
                : Column(
                    children: [
                      Expanded(
                        child: ReorderableListView(
                          onReorder: _log.completed ? (_, __) {} : _onReorder,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          proxyDecorator: (child, idx, anim) => Material(
                            color: Colors.transparent,
                            child: child,
                          ),
                          children: _log.exercises.asMap().entries.map((e) {
                            return _buildExerciseCard(e.value, e.key);
                          }).toList(),
                        ),
                      ),
                      if (!_log.completed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: TextButton.icon(
                            onPressed: _addExerciseToLog,
                            icon: const Icon(Icons.add, color: Color(0xFF555577), size: 16),
                            label: const Text('Add Exercise',
                                style: TextStyle(color: Color(0xFF555577), fontSize: 13)),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_restRemaining > 0 || _restDone) _buildRestTimer(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final isRunning = !_paused && !_log.completed;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white60, size: 22),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _log.workoutName.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _durationStr,
                        style: TextStyle(
                          color: _paused
                              ? const Color(0xFFE67E22)
                              : Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      if (!_log.completed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isRunning
                                ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                                : const Color(0xFFE67E22).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isRunning ? 'RUNNING' : 'PAUSED',
                            style: TextStyle(
                              color: isRunning
                                  ? const Color(0xFF2ECC71)
                                  : const Color(0xFFE67E22),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!_log.completed)
              GestureDetector(
                onTap: _togglePause,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _paused
                        ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                        : const Color(0xFFE67E22).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _paused
                          ? const Color(0xFF2ECC71).withValues(alpha: 0.4)
                          : const Color(0xFFE67E22).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        color: _paused
                            ? const Color(0xFF2ECC71)
                            : const Color(0xFFE67E22),
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _paused ? 'Resume' : 'Pause',
                        style: TextStyle(
                          color: _paused
                              ? const Color(0xFF2ECC71)
                              : const Color(0xFFE67E22),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  void _togglePause() {
    setState(() {
      if (_paused) {
        // Resuming: shift start time forward by the paused duration
        final pausedDuration = DateTime.now()
                .difference(_workoutStartTime!)
                .inSeconds -
            _elapsedAtPause;
        _workoutStartTime =
            _workoutStartTime!.add(Duration(seconds: pausedDuration));
        _paused = false;
        _startDurationTimer();
      } else {
        // Pausing: snapshot current elapsed
        _elapsedAtPause = _elapsedSeconds;
        _paused = true;
        _durationTimer?.cancel();
      }
    });
    _saveTimerState();
  }

  // ─── Progress bar ─────────────────────────────────────────────────────────────

  Widget _buildProgress(int checked, int total, int exDone, double vol, double progress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '$checked of $total sets · $exDone/${_log.exercises.length} exercises',
                style: const TextStyle(color: Color(0xFF888899), fontSize: 12),
              ),
              const Spacer(),
              Text(
                vol > 0 ? '${vol.toStringAsFixed(0)} kg total' : '0 kg total',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFF1A1A2E),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
            minHeight: 2,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ─── Exercise card (accordion) ────────────────────────────────────────────────

  Widget _buildExerciseCard(ExerciseLog exLog, int idx) {
    final isExpanded = _expandedId == exLog.id;
    final ex = _exercises[exLog.id];
    final allDone = exLog.sets.isNotEmpty && exLog.sets.every((s) => s.isCompleted);
    final isCardio = ex?.isCardio ?? false;

    return Container(
      key: ValueKey(exLog.id),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? const Color(0xFFFFD700).withValues(alpha: 0.22)
              : const Color(0xFF1E1E35),
        ),
      ),
      child: Column(
        children: [
          // ── Collapsed header row ──
          GestureDetector(
            onTap: _log.completed
                ? null
                : () => setState(() {
                      _expandedId = isExpanded ? null : exLog.id;
                    }),
            onLongPress:
                _log.completed ? null : () => _showExerciseRestPicker(exLog),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              child: Row(
                children: [
                  // Drag handle (only during active workout)
                  if (!_log.completed)
                    ReorderableDragStartListener(
                      index: idx,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: isExpanded
                              ? const Color(0xFF888899)
                              : const Color(0xFF333355),
                          size: 20,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 6),
                  // Number / done badge
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: allDone
                          ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                          : isExpanded
                              ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                              : const Color(0xFF1A1A2E),
                      shape: BoxShape.circle,
                    ),
                    child: allDone
                        ? const Icon(Icons.check, color: Color(0xFF2ECC71), size: 14)
                        : Text(
                            '${idx + 1}',
                            style: TextStyle(
                              color: isExpanded
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFF888899),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                ex?.name ?? 'Unknown Exercise',
                                style: TextStyle(
                                  color: isExpanded ? Colors.white : const Color(0xFFCCCCDD),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_plateauedIds.contains(exLog.exerciseId)) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF9F27).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: const Color(0xFFEF9F27).withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  '⚠ Plateau',
                                  style: TextStyle(
                                    color: Color(0xFFEF9F27),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${ex?.muscleGroup ?? ''} · ${exLog.sets.length} set${exLog.sets.length == 1 ? '' : 's'}${isCardio ? ' · Cardio' : ''}',
                          style: const TextStyle(color: Color(0xFF555577), fontSize: 11),
                        ),
                        if (_exerciseRestOverrides
                            .containsKey(exLog.exerciseId))
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined,
                                    color: Color(0xFF887744), size: 9),
                                const SizedBox(width: 2),
                                Text(
                                  _fmtRestTime(_exerciseRestOverrides[
                                      exLog.exerciseId]!),
                                  style: const TextStyle(
                                      color: Color(0xFF887744),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        if (!isExpanded && (exLog.notes?.isNotEmpty ?? false))
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.notes_rounded,
                                    color: Color(0xFF5577AA), size: 9),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    exLog.notes!,
                                    style: const TextStyle(
                                        color: Color(0xFF5577AA),
                                        fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Options menu
                  if (!_log.completed)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white24, size: 18),
                      color: const Color(0xFF1A1A2E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (v) {
                        if (v == 'remove') _removeExercise(exLog);
                        if (v == 'add') _addExerciseToLog();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'add',
                          child: Row(children: [
                            Icon(Icons.add, color: Color(0xFFFFD700), size: 16),
                            SizedBox(width: 8),
                            Text('Add Exercise', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Row(children: [
                            Icon(Icons.delete_outline, color: Color(0xFFE74C3C), size: 16),
                            SizedBox(width: 8),
                            Text('Remove', style: TextStyle(color: Color(0xFFE74C3C), fontSize: 13)),
                          ]),
                        ),
                      ],
                    ),
                  // Expand chevron
                  if (!_log.completed)
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF444466),
                      size: 20,
                    )
                  else
                    const SizedBox(width: 4),
                ],
              ),
            ),
          ),

          // ── Expanded content ──
          if (isExpanded || _log.completed) ...[
            const Divider(color: Color(0xFF1E1E35), height: 1),

            // Last session hint
            if (_hintLine(exLog.id) != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _hintLine(exLog.id)!,
                  style: const TextStyle(color: Color(0xFF888899), fontSize: 12),
                ),
              ),
            // Progressive-overload suggestion
            if (!_log.completed && _suggestions[exLog.id] != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up_rounded,
                          color: Color(0xFFFFD700), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                color: Color(0xFFCCCCDD), fontSize: 12),
                            children: [
                              const TextSpan(text: 'Try '),
                              TextSpan(
                                text: '${_fmtW(_suggestions[exLog.id]!.weight)} kg',
                                style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                  text: ' · ${_suggestions[exLog.id]!.reason}'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Column headers
            if (exLog.sets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                child: isCardio
                    ? _buildCardioHeaders(ex!.cardioType)
                    : const Row(
                        children: [
                          SizedBox(width: 32, child: Text('SET', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF444466), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
                          Expanded(child: Text('WEIGHT (KG)', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF444466), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
                          Expanded(child: Text('REPS', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF444466), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
                          SizedBox(width: 40, child: Icon(Icons.check, color: Color(0xFF444466), size: 12)),
                        ],
                      ),
              ),

            // Set rows
            ...exLog.sets.map((s) => isCardio
                ? _buildCardioSetRow(exLog, s, ex!.cardioType)
                : _buildStrengthSetRow(exLog, s)),

            // Add Set button
            if (!_log.completed)
              _buildAddSetBtn(exLog),

            // Exercise note
            _buildExerciseNote(exLog),

            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildExerciseNote(ExerciseLog exLog) {
    final ctrl = _noteControllers[exLog.id];
    if (ctrl == null) return const SizedBox.shrink();
    final isReadOnly = _log.completed;

    if (isReadOnly) {
      if (exLog.notes == null || exLog.notes!.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notes_rounded, color: Color(0xFF5577AA), size: 13),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                exLog.notes!,
                style: const TextStyle(color: Color(0xFF8899BB), fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        onEditingComplete: () => _saveNote(exLog, ctrl.text),
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          _saveNote(exLog, ctrl.text);
        },
        decoration: InputDecoration(
          hintText: 'Add a note for this exercise…',
          hintStyle: const TextStyle(color: Color(0xFF333355), fontSize: 12),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: Icon(Icons.notes_rounded, color: Color(0xFF444466), size: 14),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          filled: true,
          fillColor: const Color(0xFF0D0D1A),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: Color(0xFF5577AA), width: 1),
          ),
        ),
      ),
    );
  }

  Future<void> _saveNote(ExerciseLog exLog, String text) async {
    final note = text.trim().isEmpty ? null : text.trim();
    if (note == exLog.notes) return;
    await _db.updateExerciseLogNote(exLog.id, note);
    final idx = _log.exercises.indexWhere((e) => e.id == exLog.id);
    if (idx != -1 && mounted) {
      setState(() {
        _log = _log.copyWith(
          exercises: List.from(_log.exercises)
            ..[idx] = exLog.copyWith(notes: note),
        );
      });
    }
  }

  // ─── Strength set row ─────────────────────────────────────────────────────────

  Widget _buildStrengthSetRow(ExerciseLog exLog, SetLog setLog) {
    final isReadOnly = _log.completed;
    return AnimatedContainer(
      key: ValueKey('set_${setLog.id}'),
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: setLog.isCompleted
            ? const Color(0xFFFFD700).withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: setLog.isCompleted
            ? Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.18))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Text(
                  '${setLog.setNumber}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: setLog.isCompleted
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF888899),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -4,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: _setPRs[setLog.id] == true
                        ? const Icon(Icons.star_rounded,
                            key: ValueKey('pr'),
                            color: Color(0xFFFFD700),
                            size: 11)
                        : const SizedBox.shrink(key: ValueKey('no')),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isReadOnly
                ? _ReadOnlyValue('${setLog.weight != null ? _fmtW(setLog.weight!) : '—'} kg')
                : _Stepper(
                    value: setLog.weight ?? 0,
                    step: 2.5,
                    onChanged: (v) =>
                        _updateSet(exLog, setLog.copyWith(weight: v.clamp(0, 999))),
                    onTapValue: () => _editValue(
                      'Weight (kg)',
                      setLog.weight ?? 0,
                      false,
                      (v) => _updateSet(exLog, setLog.copyWith(weight: v.clamp(0, 999))),
                    ),
                  ),
          ),
          Expanded(
            child: isReadOnly
                ? _ReadOnlyValue('${setLog.reps ?? '—'} reps')
                : _Stepper(
                    value: (setLog.reps ?? 0).toDouble(),
                    step: 1,
                    isInt: true,
                    onChanged: (v) =>
                        _updateSet(exLog, setLog.copyWith(reps: v.clamp(0, 999).toInt())),
                    onTapValue: () => _editValue(
                      'Reps',
                      (setLog.reps ?? 0).toDouble(),
                      true,
                      (v) => _updateSet(exLog, setLog.copyWith(reps: v.clamp(0, 999).toInt())),
                    ),
                  ),
          ),
          GestureDetector(
            onTap: isReadOnly ? null : () => _toggleCheck(exLog, setLog),
            child: SizedBox(
              width: 36,
              child: Icon(
                setLog.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: setLog.isCompleted
                    ? const Color(0xFFFFD700)
                    : const Color(0xFF333355),
                size: 22,
              ),
            ),
          ),
          if (!isReadOnly)
            GestureDetector(
              onTap: () => _deleteSet(exLog, setLog),
              child: const SizedBox(
                width: 32,
                child: Icon(Icons.delete_outline,
                    color: Color(0xFF555566), size: 18),
              ),
            )
          else
            const SizedBox(width: 32),
        ],
      ),
    );
  }

  // ─── Cardio set row ───────────────────────────────────────────────────────────

  Widget _buildCardioHeaders(CardioType ct) {
    String f1, f2;
    switch (ct) {
      case CardioType.treadmill:
        f1 = 'SPEED km/h';
        f2 = 'INCLINE %';
        break;
      case CardioType.crossTrainer:
      case CardioType.cycling:
        f1 = 'RESISTANCE';
        f2 = 'DISTANCE km';
        break;
      case CardioType.rowing:
        f1 = 'DIST m';
        f2 = '';
        break;
      case CardioType.stairClimber:
        f1 = 'SPEED spm';
        f2 = '';
        break;
      default:
        f1 = 'DISTANCE km';
        f2 = '';
    }
    return Row(
      children: [
        const SizedBox(width: 32, child: Text('SET', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF444466), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
        const Expanded(child: Text('DURATION', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF444466), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
        Expanded(child: Text(f1, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF444466), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
        if (f2.isNotEmpty)
          Expanded(child: Text(f2, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF444466), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
        const SizedBox(width: 40, child: Icon(Icons.check, color: Color(0xFF444466), size: 12)),
      ],
    );
  }

  Widget _buildCardioSetRow(ExerciseLog exLog, SetLog setLog, CardioType ct) {
    final isReadOnly = _log.completed;
    final durSec = setLog.durationSeconds ?? 0;
    final durStr = '${durSec ~/ 60}:${(durSec % 60).toString().padLeft(2, '0')}';

    String f1Val, f2Val;
    switch (ct) {
      case CardioType.treadmill:
        f1Val = '${setLog.speed?.toStringAsFixed(1) ?? '—'}';
        f2Val = '${setLog.incline?.toStringAsFixed(1) ?? '—'}';
        break;
      case CardioType.crossTrainer:
      case CardioType.cycling:
        f1Val = '${setLog.resistance?.toStringAsFixed(0) ?? '—'}';
        f2Val = '${setLog.distanceKm?.toStringAsFixed(2) ?? '—'}';
        break;
      case CardioType.rowing:
        f1Val = '${setLog.distanceKm != null ? (setLog.distanceKm! * 1000).toStringAsFixed(0) : '—'}';
        f2Val = '';
        break;
      case CardioType.stairClimber:
        f1Val = '${setLog.speed?.toStringAsFixed(0) ?? '—'}';
        f2Val = '';
        break;
      default:
        f1Val = '${setLog.distanceKm?.toStringAsFixed(2) ?? '—'}';
        f2Val = '';
    }

    bool hasF2 = f2Val.isNotEmpty;

    return AnimatedContainer(
      key: ValueKey('set_${setLog.id}'),
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: setLog.isCompleted
            ? const Color(0xFF3498DB).withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: setLog.isCompleted
            ? Border.all(color: const Color(0xFF3498DB).withValues(alpha: 0.2))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${setLog.setNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: setLog.isCompleted ? const Color(0xFF3498DB) : const Color(0xFF888899),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
            // Duration
            Expanded(
              child: GestureDetector(
                onTap: isReadOnly ? null : () => _editDuration(exLog, setLog),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    durStr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF3498DB),
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
              ),
            ),
            // Field 1
            Expanded(
              child: isReadOnly
                  ? _ReadOnlyValue(f1Val, color: const Color(0xFF3498DB))
                  : _CardioStepper(
                      value: _cardioF1Value(setLog, ct),
                      step: ct == CardioType.treadmill ? 0.5 : 1.0,
                      onChanged: (v) => _updateSet(exLog, _setCardioF1(setLog, ct, v)),
                      onTap: () => _editValue(
                        _cardioF1Label(ct),
                        _cardioF1Value(setLog, ct),
                        ct != CardioType.treadmill,
                        (v) => _updateSet(exLog, _setCardioF1(setLog, ct, v)),
                      ),
                    ),
            ),
            // Field 2 (optional)
            if (hasF2)
              Expanded(
                child: isReadOnly
                    ? _ReadOnlyValue(f2Val, color: const Color(0xFF3498DB))
                    : _CardioStepper(
                        value: _cardioF2Value(setLog, ct),
                        step: 0.5,
                        onChanged: (v) => _updateSet(exLog, _setCardioF2(setLog, ct, v)),
                        onTap: () => _editValue(
                          _cardioF2Label(ct),
                          _cardioF2Value(setLog, ct),
                          false,
                          (v) => _updateSet(exLog, _setCardioF2(setLog, ct, v)),
                        ),
                      ),
              ),
            GestureDetector(
              onTap: isReadOnly ? null : () => _toggleCheck(exLog, setLog),
              child: SizedBox(
                width: 36,
                child: Icon(
                  setLog.isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: setLog.isCompleted
                      ? const Color(0xFF3498DB)
                      : const Color(0xFF333355),
                  size: 22,
                ),
              ),
            ),
            if (!isReadOnly)
              GestureDetector(
                onTap: () => _deleteSet(exLog, setLog),
                child: const SizedBox(
                  width: 32,
                  child: Icon(Icons.delete_outline,
                      color: Color(0xFF555566), size: 18),
                ),
              )
            else
              const SizedBox(width: 32),
          ],
        ),
    );
  }

  double _cardioF1Value(SetLog s, CardioType ct) {
    switch (ct) {
      case CardioType.treadmill:
        return s.speed ?? 0;
      case CardioType.crossTrainer:
      case CardioType.cycling:
        return s.resistance ?? 0;
      case CardioType.rowing:
        return (s.distanceKm ?? 0) * 1000;
      case CardioType.stairClimber:
        return s.speed ?? 0;
      default:
        return s.distanceKm ?? 0;
    }
  }

  SetLog _setCardioF1(SetLog s, CardioType ct, double v) {
    switch (ct) {
      case CardioType.treadmill:
        return s.copyWith(speed: v.clamp(0, 30));
      case CardioType.crossTrainer:
      case CardioType.cycling:
        return s.copyWith(resistance: v.clamp(0, 30));
      case CardioType.rowing:
        return s.copyWith(distanceKm: (v / 1000).clamp(0, 100));
      case CardioType.stairClimber:
        return s.copyWith(speed: v.clamp(0, 300));
      default:
        return s.copyWith(distanceKm: v.clamp(0, 100));
    }
  }

  double _cardioF2Value(SetLog s, CardioType ct) {
    switch (ct) {
      case CardioType.treadmill:
        return s.incline ?? 0;
      default:
        return s.distanceKm ?? 0;
    }
  }

  SetLog _setCardioF2(SetLog s, CardioType ct, double v) {
    switch (ct) {
      case CardioType.treadmill:
        return s.copyWith(incline: v.clamp(0, 15));
      default:
        return s.copyWith(distanceKm: v.clamp(0, 100));
    }
  }

  String _cardioF1Label(CardioType ct) {
    switch (ct) {
      case CardioType.treadmill:
        return 'Speed (km/h)';
      case CardioType.crossTrainer:
      case CardioType.cycling:
        return 'Resistance';
      case CardioType.rowing:
        return 'Distance (m)';
      case CardioType.stairClimber:
        return 'Speed (spm)';
      default:
        return 'Distance (km)';
    }
  }

  String _cardioF2Label(CardioType ct) {
    if (ct == CardioType.treadmill) return 'Incline (%)';
    return 'Distance (km)';
  }

  // ─── Add Set button ───────────────────────────────────────────────────────────

  Widget _buildAddSetBtn(ExerciseLog exLog) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: GestureDetector(
        onTap: () => _addSet(exLog),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.25)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: Color(0xFFFFD700), size: 14),
              SizedBox(width: 5),
              Text('+ Add Set',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center_outlined, color: Color(0xFF333355), size: 48),
          const SizedBox(height: 12),
          const Text('No exercises yet', style: TextStyle(color: Color(0xFF888899), fontSize: 14)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _addExerciseToLog,
            icon: const Icon(Icons.add, color: Color(0xFFFFD700)),
            label: const Text('Add Exercise', style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

  // ─── Bottom bar ───────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: _log.completed
          ? GestureDetector(
              onTap: _undoComplete,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF2ECC71), size: 20),
                    SizedBox(width: 8),
                    Text('Workout Completed',
                        style: TextStyle(
                            color: Color(0xFF2ECC71),
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ],
                ),
              ),
            )
          : GestureDetector(
              onTap: _completeWorkout,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.done_all_rounded, color: Colors.black),
                    SizedBox(width: 8),
                    Text('Finish Workout',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── Rest timer ───────────────────────────────────────────────────────────────

  Widget _buildRestTimer() {
    final progress = _restTotal > 0 ? _restRemaining / _restTotal : 0.0;
    final mins = _restRemaining ~/ 60;
    final secs = _restRemaining % 60;
    final timeStr =
        mins > 0 ? '$mins:${secs.toString().padLeft(2, '0')}' : '${secs}s';

    return GestureDetector(
      onTap:
          _restDone ? null : () => setState(() => _restExpanded = !_restExpanded),
      onLongPress: _restDone ? null : _showRestDurationPicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: _restDone
              ? const Color(0xFFFFD700).withValues(alpha: 0.12)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _restDone
                ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                : const Color(0xFF2A2A45),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('💤', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                const Text('Rest',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Text(
                  _restDone ? 'Done!' : timeStr,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 10),
                if (!_restDone)
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: const Color(0xFF2A2A45),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress > 0.35
                              ? const Color(0xFFFFD700).withValues(alpha: 0.7)
                              : const Color(0xFFE74C3C),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _cancelRest,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: _restDone
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF555577),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_restExpanded && !_restDone) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RestNudgeBtn(
                    label: '−15s',
                    onTap: () => setState(() {
                      _restRemaining = (_restRemaining - 15).clamp(5, 9999);
                    }),
                  ),
                  const SizedBox(width: 16),
                  _RestNudgeBtn(
                    label: '+15s',
                    onTap: () => setState(() {
                      _restRemaining += 15;
                      _restTotal += 15;
                    }),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Stepper (strength) ───────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final double value;
  final double step;
  final bool isInt;
  final ValueChanged<double> onChanged;
  final VoidCallback onTapValue; // manual entry

  const _Stepper({
    required this.value,
    required this.step,
    required this.onChanged,
    required this.onTapValue,
    this.isInt = false,
  });

  String get _display {
    if (isInt) return value.toInt().toString();
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => onChanged(value - step),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.remove, color: Colors.white54, size: 14),
          ),
        ),
        GestureDetector(
          onTap: onTapValue,
          child: SizedBox(
            width: 44,
            child: Text(
              _display,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(value + step),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.add, color: Colors.white54, size: 14),
          ),
        ),
      ],
    );
  }
}

// ─── Cardio value stepper ─────────────────────────────────────────────────────

class _CardioStepper extends StatelessWidget {
  final double value;
  final double step;
  final ValueChanged<double> onChanged;
  final VoidCallback onTap;

  const _CardioStepper({
    required this.value,
    required this.step,
    required this.onChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => onChanged(value - step),
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.remove, color: Colors.white54, size: 12),
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 36,
            child: Text(display,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF3498DB), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(value + step),
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.add, color: Colors.white54, size: 12),
          ),
        ),
      ],
    );
  }
}

// ─── Read-only value display ──────────────────────────────────────────────────

class _ReadOnlyValue extends StatelessWidget {
  final String text;
  final Color color;
  const _ReadOnlyValue(this.text, {this.color = Colors.white});

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
      );
}

// ─── Rest nudge button ────────────────────────────────────────────────────────

class _RestNudgeBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _RestNudgeBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2A2A45)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFFCCCCDD),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      );
}

// ─── Inline exercise picker ───────────────────────────────────────────────────

class _InlineExercisePicker extends StatefulWidget {
  const _InlineExercisePicker();

  @override
  State<_InlineExercisePicker> createState() => _InlineExercisePickerState();
}

class _InlineExercisePickerState extends State<_InlineExercisePicker> {
  final _db = WorkoutDatabase.instance;
  final _search = TextEditingController();
  List<Exercise> _all = [];
  List<Exercise> _filtered = [];
  String? _group;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await _db.getAllExercises();
    if (mounted) {
      setState(() {
        _all = all;
        _filter();
      });
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = _all.where((e) {
        final matchQ = e.name.toLowerCase().contains(q);
        final matchG = _group == null || e.muscleGroup == _group;
        return matchQ && matchG;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('Add Exercise',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search exercises…',
                hintStyle: const TextStyle(color: Color(0xFF444466)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF888899)),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          MuscleGroupFilter(
            selected: _group,
            onChanged: (g) => setState(() {
              _group = g;
              _filter();
            }),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => ExerciseTile(
                exercise: _filtered[i],
                onTap: () => Navigator.pop(context, _filtered[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PR Celebration Overlay ────────────────────────────────────────────────────

class _PRCelebrationDialog extends StatefulWidget {
  final String exerciseName;
  final double orm;

  const _PRCelebrationDialog({required this.exerciseName, required this.orm});

  @override
  State<_PRCelebrationDialog> createState() => _PRCelebrationDialogState();
}

class _PRCelebrationDialogState extends State<_PRCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: _scale,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 48),
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: const Color(0xFFFFD700), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⭐', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 12),
                const Text(
                  'New PR!',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.exerciseName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.orm.toStringAsFixed(1)} kg estimated 1RM',
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

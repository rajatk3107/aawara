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

  // Exercises that have already shown the overload nudge this session
  final Set<String> _nudgedExercises = {};

  // Set IDs that achieved a PR this session (drives ⭐ badge)
  final Map<String, bool> _setPRs = {};

  // Rest timer
  Timer? _restTimer;
  int _restRemaining = 0;
  int _restTotal = 90;

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _restTimer?.cancel();
    _saveTimerState();
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
    for (final exLog in _log.exercises) {
      final ex = await _db.getExerciseById(exLog.exerciseId);
      if (ex != null) _exercises[exLog.id] = ex;

      // Build hint from last session
      final prev = await _db.getLastSetsForExercise(exLog.exerciseId);
      if (prev.isNotEmpty) {
        final s = prev.first;
        if (ex != null && !ex.isCardio && s.weight != null && s.reps != null) {
          _hints[exLog.id] = '${_fmtW(s.weight!)} × ${s.reps}';
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _durationStr {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtW(double w) =>
      w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

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

  void _startRest(int seconds) {
    _restTimer?.cancel();
    setState(() {
      _restRemaining = seconds;
      _restTotal = seconds;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_restRemaining > 0) {
          _restRemaining--;
          if (_restRemaining == 0) HapticFeedback.mediumImpact();
        } else {
          t.cancel();
        }
      });
    });
  }

  void _cancelRest() {
    _restTimer?.cancel();
    setState(() => _restRemaining = 0);
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
      _startRest(90);
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
    final prev = await _db.getLastSetsForExercise(picked.id);
    if (prev.isNotEmpty && !picked.isCardio) {
      final s = prev.first;
      if (s.weight != null && s.reps != null) {
        _hints[exLog.id] = '${_fmtW(s.weight!)} × ${s.reps}';
      }
    }
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
    }
  }

  Future<void> _undoComplete() async {
    final updated = _log.copyWith(completed: false);
    await _db.updateWorkoutLog(updated);
    setState(() {
      _log = updated;
      _elapsedSeconds = updated.durationSeconds ?? 0;
    });
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              Navigator.pop(ctx, v);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              final m = int.tryParse(mmCtrl.text) ?? 0;
              final s = int.tryParse(ssCtrl.text) ?? 0;
              Navigator.pop(ctx, m * 60 + s);
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
            if (_restRemaining > 0) _buildRestTimer(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
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
                  Text(
                    _durationStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            if (!_log.completed)
              IconButton(
                icon: Icon(
                  _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white60,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    if (_paused) {
                      // Resuming: shift start time forward by the paused duration
                      final pausedDuration = DateTime.now()
                          .difference(_workoutStartTime!)
                          .inSeconds - _elapsedAtPause;
                      _workoutStartTime = _workoutStartTime!
                          .add(Duration(seconds: pausedDuration));
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
                },
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
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
                        Text(
                          ex?.name ?? 'Unknown Exercise',
                          style: TextStyle(
                            color: isExpanded ? Colors.white : const Color(0xFFCCCCDD),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${ex?.muscleGroup ?? ''} · ${exLog.sets.length} set${exLog.sets.length == 1 ? '' : 's'}${isCardio ? ' · Cardio' : ''}',
                          style: const TextStyle(color: Color(0xFF555577), fontSize: 11),
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

            const SizedBox(height: 4),
          ],
        ],
      ),
    );
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
    final timeStr = mins > 0 ? '$mins:${secs.toString().padLeft(2, '0')}' : '${secs}s';
    final done = _restRemaining == 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
              : const Color(0xFF3498DB).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle_outline : Icons.timer_outlined,
                color: done ? const Color(0xFF2ECC71) : const Color(0xFF3498DB),
                size: 15,
              ),
              const SizedBox(width: 7),
              Text(
                done ? 'Rest done — go!' : 'Rest',
                style: TextStyle(
                  color: done ? const Color(0xFF2ECC71) : Colors.white54,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (!done) ...[
                Text(timeStr,
                    style: const TextStyle(
                        color: Color(0xFF3498DB),
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _startRest(_restRemaining + 30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3498DB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('+30s',
                        style: TextStyle(
                            color: Color(0xFF3498DB),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              GestureDetector(
                onTap: _cancelRest,
                child: const Icon(Icons.close, color: Colors.white24, size: 15),
              ),
            ],
          ),
          if (!done) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF0D0D1A),
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.5
                    ? const Color(0xFF3498DB)
                    : const Color(0xFFF39C12),
              ),
              borderRadius: BorderRadius.circular(4),
              minHeight: 2,
            ),
          ],
        ],
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

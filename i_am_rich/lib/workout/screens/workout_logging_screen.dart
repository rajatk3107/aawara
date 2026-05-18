import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_log.dart';
import '../widgets/exercise_tile.dart';
import '../widgets/muscle_group_filter.dart';
import 'workout_complete_screen.dart';

class WorkoutLoggingScreen extends StatefulWidget {
  final WorkoutLog workoutLog;
  const WorkoutLoggingScreen({super.key, required this.workoutLog});

  @override
  State<WorkoutLoggingScreen> createState() => _WorkoutLoggingScreenState();
}

class _WorkoutLoggingScreenState extends State<WorkoutLoggingScreen> {
  final _db = WorkoutDatabase.instance;
  late WorkoutLog _log;

  final Map<String, Exercise> _exercises = {};
  final Map<String, List<String?>> _hints = {};
  bool _loading = true;

  int _elapsedSeconds = 0;
  Timer? _durationTimer;
  bool _paused = false;

  int _currentExerciseIndex = 0;
  final Set<String> _checkedSets = {};

  Timer? _restTimer;
  int _restRemaining = 0;
  int _restTotal = 90;

  @override
  void initState() {
    super.initState();
    _log = widget.workoutLog;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_paused) setState(() => _elapsedSeconds++);
    });
    _loadDetails();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);
    for (final exLog in _log.exercises) {
      final ex = await _db.getExerciseById(exLog.exerciseId);
      if (ex != null) _exercises[exLog.id] = ex;
      final prev = await _db.getLastSetsForExercise(exLog.exerciseId);
      if (prev.isNotEmpty) {
        _hints[exLog.id] = prev
            .take(10)
            .map((s) => s.weight != null && s.reps != null
                ? '${_fmtW(s.weight!)} × ${s.reps}'
                : null)
            .toList();
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
    final hint = _hints[exLogId]?.firstWhere((h) => h != null, orElse: () => null);
    if (hint == null) return null;
    final parts = hint.split(' × ');
    if (parts.length != 2) return 'Last: $hint';
    final w = double.tryParse(parts[0]);
    final r = int.tryParse(parts[1]);
    final orm = (w != null && r != null && r > 0)
        ? '   1RM ~ ${(w * (1 + r / 30)).toStringAsFixed(0)} kg'
        : '';
    return 'Last: $hint$orm';
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    setState(() {
      _restRemaining = seconds;
      _restTotal = seconds;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
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

  void _toggleCheck(String setId) {
    setState(() {
      if (_checkedSets.contains(setId)) {
        _checkedSets.remove(setId);
      } else {
        _checkedSets.add(setId);
        _startRest(90);
      }
    });
  }

  Future<void> _addSet(ExerciseLog exLog) async {
    const uuid = Uuid();
    double? w;
    int? r;
    if (exLog.sets.isNotEmpty) {
      w = exLog.sets.last.weight;
      r = exLog.sets.last.reps;
    } else {
      final hint = _hints[exLog.id]?.firstWhere((h) => h != null, orElse: () => null);
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
      weight: w,
      reps: r,
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
    _checkedSets.remove(setLog.id);
    setState(() {
      exLog.sets.removeWhere((s) => s.id == setLog.id);
      for (int i = 0; i < exLog.sets.length; i++) {
        exLog.sets[i] = exLog.sets[i].copyWith(setNumber: i + 1);
      }
    });
  }

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
        if (_currentExerciseIndex >= _log.exercises.length && _currentExerciseIndex > 0) {
          _currentExerciseIndex = _log.exercises.length - 1;
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
    _hints[exLog.id] = prev
        .take(10)
        .map((s) => s.weight != null && s.reps != null
            ? '${_fmtW(s.weight!)} × ${s.reps}'
            : null)
        .toList();
    setState(() => _log.exercises.add(exLog));
  }

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
    final updated = _log.copyWith(completed: true);
    await _db.updateWorkoutLog(updated);
    setState(() => _log = updated);
    if (!mounted) return;
    _durationTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutCompleteScreen(
          log: _log,
          exercises: _exercises,
          elapsedSeconds: _elapsedSeconds,
        ),
      ),
    );
  }

  Future<void> _undoComplete() async {
    final updated = _log.copyWith(completed: false);
    await _db.updateWorkoutLog(updated);
    setState(() => _log = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D1A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
      );
    }

    final totalSets = _log.exercises.fold(0, (s, e) => s + e.sets.length);
    final checkedCount = _checkedSets.length;
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
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildCurrentExercise()),
                      if (_log.exercises.length > 1)
                        SliverToBoxAdapter(child: _buildUpNext()),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: TextButton.icon(
                            onPressed: _addExerciseToLog,
                            icon: const Icon(Icons.add, color: Color(0xFF888899), size: 16),
                            label: const Text('Add Exercise',
                                style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
            IconButton(
              icon: Icon(
                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: Colors.white60,
                size: 22,
              ),
              onPressed: () => setState(() => _paused = !_paused),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(
      int checked, int total, int exDone, double vol, double progress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
            minHeight: 2,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildCurrentExercise() {
    final idx = _currentExerciseIndex.clamp(0, _log.exercises.length - 1);
    final exLog = _log.exercises[idx];
    final ex = _exercises[exLog.id];
    final hint = _hintLine(exLog.id);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFFFD700).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    ex != null
                        ? 'NOW · ${ex.muscleGroup.toUpperCase()}'
                        : 'NOW',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white38, size: 18),
                  color: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
                        Text('Add Exercise',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            color: Color(0xFFE74C3C), size: 16),
                        SizedBox(width: 8),
                        Text('Remove',
                            style: TextStyle(
                                color: Color(0xFFE74C3C), fontSize: 13)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Name
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
            child: Text(
              ex?.name ?? 'Unknown Exercise',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Last / 1RM
          if (hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: Text(
                hint,
                style: const TextStyle(color: Color(0xFF888899), fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
          // Column headers
          if (exLog.sets.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text('SET',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF444466),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ),
                  Expanded(
                    child: Text('WEIGHT (KG)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF444466),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ),
                  Expanded(
                    child: Text('REPS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF444466),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ),
                  SizedBox(
                    width: 40,
                    child: Icon(Icons.check, color: Color(0xFF444466), size: 12),
                  ),
                ],
              ),
            ),
          // Set rows
          ...exLog.sets.map((s) => _buildSetRow(exLog, s)),
          // Add Set
          _buildAddSetBtn(exLog),
        ],
      ),
    );
  }

  Widget _buildSetRow(ExerciseLog exLog, SetLog setLog) {
    final checked = _checkedSets.contains(setLog.id);
    return GestureDetector(
      onLongPress: () => _deleteSet(exLog, setLog),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        decoration: BoxDecoration(
          color: checked
              ? const Color(0xFFFFD700).withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: checked
              ? Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.18))
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
                  color: checked
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF888899),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              child: _Stepper(
                value: setLog.weight ?? 0,
                step: 2.5,
                onChanged: (v) => _updateSet(
                    exLog, setLog.copyWith(weight: v.clamp(0, 999))),
              ),
            ),
            Expanded(
              child: _Stepper(
                value: (setLog.reps ?? 0).toDouble(),
                step: 1,
                isInt: true,
                onChanged: (v) => _updateSet(
                    exLog, setLog.copyWith(reps: v.clamp(0, 999).toInt())),
              ),
            ),
            GestureDetector(
              onTap: () => _toggleCheck(setLog.id),
              child: SizedBox(
                width: 40,
                child: Icon(
                  checked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: checked
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF333355),
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddSetBtn(ExerciseLog exLog) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: GestureDetector(
        onTap: () => _addSet(exLog),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.25)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: Color(0xFFFFD700), size: 15),
              SizedBox(width: 6),
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

  Widget _buildUpNext() {
    final others = <(int, ExerciseLog)>[];
    for (int i = 0; i < _log.exercises.length; i++) {
      if (i != _currentExerciseIndex) others.add((i, _log.exercises[i]));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UP NEXT',
            style: TextStyle(
              color: Color(0xFF888899),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          ...others.map(((int, ExerciseLog) item) {
            final (origIdx, exLog) = item;
            final ex = _exercises[exLog.id];
            final hasSets = exLog.sets.isNotEmpty;
            return GestureDetector(
              onTap: () => setState(() => _currentExerciseIndex = origIdx),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hasSets
                            ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                            : const Color(0xFF1A1A2E),
                        shape: BoxShape.circle,
                      ),
                      child: hasSets
                          ? const Icon(Icons.check,
                              color: Color(0xFF2ECC71), size: 14)
                          : Text(
                              '${origIdx + 1}',
                              style: const TextStyle(
                                color: Color(0xFF888899),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ex?.name ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${exLog.sets.length} sets · ${ex?.muscleGroup ?? ''}',
                            style: const TextStyle(
                                color: Color(0xFF888899), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF444466), size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center_outlined,
              color: Color(0xFF333355), size: 48),
          const SizedBox(height: 12),
          const Text('No exercises yet',
              style: TextStyle(color: Color(0xFF888899), fontSize: 14)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _addExerciseToLog,
            icon: const Icon(Icons.add, color: Color(0xFFFFD700)),
            label: const Text('Add Exercise',
                style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

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
                  border: Border.all(
                      color: const Color(0xFF2ECC71).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Color(0xFF2ECC71), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Workout Completed',
                      style: TextStyle(
                          color: Color(0xFF2ECC71),
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
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
                    Text(
                      'Finish Workout',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRestTimer() {
    final progress = _restTotal > 0 ? _restRemaining / _restTotal : 0.0;
    final mins = _restRemaining ~/ 60;
    final secs = _restRemaining % 60;
    final timeStr =
        mins > 0 ? '$mins:${secs.toString().padLeft(2, '0')}' : '${secs}s';
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
                color:
                    done ? const Color(0xFF2ECC71) : const Color(0xFF3498DB),
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
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Color(0xFF3498DB),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _startRest(_restRemaining + 30),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF3498DB).withValues(alpha: 0.1),
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
                child:
                    const Icon(Icons.close, color: Colors.white24, size: 15),
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

// ─── Stepper Widget ───────────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final double value;
  final double step;
  final bool isInt;
  final ValueChanged<double> onChanged;

  const _Stepper({
    required this.value,
    required this.step,
    required this.onChanged,
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
        SizedBox(
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

// ─── Inline Exercise Picker ───────────────────────────────────────────────────

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

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_log.dart';
import '../widgets/exercise_tile.dart';
import '../widgets/muscle_group_filter.dart';
import '../widgets/set_log_tile.dart';

class WorkoutLoggingScreen extends StatefulWidget {
  final WorkoutLog workoutLog;

  const WorkoutLoggingScreen({super.key, required this.workoutLog});

  @override
  State<WorkoutLoggingScreen> createState() => _WorkoutLoggingScreenState();
}

class _WorkoutLoggingScreenState extends State<WorkoutLoggingScreen> {
  final _db = WorkoutDatabase.instance;
  late WorkoutLog _log;

  // exercise_log_id -> Exercise
  final Map<String, Exercise> _exercises = {};
  // exercise_log_id -> last performance hint per set index
  final Map<String, List<String?>> _hints = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _log = widget.workoutLog;
    _loadDetails();
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

  String _fmtW(double w) =>
      w == w.truncate() ? w.toInt().toString() : w.toString();

  Future<void> _addSet(ExerciseLog exLog) async {
    const uuid = Uuid();
    final newSet = SetLog(
      id: uuid.v4(),
      exerciseLogId: exLog.id,
      setNumber: exLog.sets.length + 1,
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
        final s = exLog.sets[i];
        exLog.sets[i] = s.copyWith(setNumber: i + 1);
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
      setState(() => _log.exercises.removeWhere((e) => e.id == exLog.id));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log at least one set before completing.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFE74C3C),
        ),
      );
      return;
    }
    final updated = _log.copyWith(completed: true);
    await _db.updateWorkoutLog(updated);
    setState(() => _log = updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Workout completed! Great job! 💪'),
        backgroundColor: Color(0xFF2ECC71),
        behavior: SnackBarBehavior.floating,
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
    final totalSets = _log.exercises.fold(0, (s, e) => s + e.sets.length);
    final totalVol = _log.exercises.fold(0.0, (s, e) => s + e.totalVolume);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExerciseToLog,
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: const Color(0xFFFFD700),
        mini: true,
        elevation: 2,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _log.workoutName,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              _log.date,
              style: const TextStyle(color: Color(0xFF888899), fontSize: 12),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_log.completed)
            TextButton(
              onPressed: _undoComplete,
              child: const Text('Undo',
                  style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : Column(
              children: [
                // Stats bar
                Container(
                  color: const Color(0xFF12121F),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _QuickStat(
                          label: 'Exercises',
                          value: '${_log.exercises.length}'),
                      _VSep(),
                      _QuickStat(label: 'Sets', value: '$totalSets'),
                      _VSep(),
                      _QuickStat(
                          label: 'Volume',
                          value: totalVol > 0
                              ? '${totalVol.toStringAsFixed(0)} kg'
                              : '—'),
                      if (_log.completed) ...[
                        _VSep(),
                        const _QuickStat(
                            label: 'Status',
                            value: '✓ Done',
                            valueColor: Color(0xFF2ECC71)),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _log.exercises.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.fitness_center_outlined,
                                  color: Color(0xFF333355), size: 48),
                              const SizedBox(height: 12),
                              const Text('No exercises yet',
                                  style: TextStyle(
                                      color: Color(0xFF888899), fontSize: 14)),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _addExerciseToLog,
                                icon: const Icon(Icons.add,
                                    color: Color(0xFFFFD700)),
                                label: const Text('Add Exercise',
                                    style:
                                        TextStyle(color: Color(0xFFFFD700))),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                          itemCount: _log.exercises.length,
                          itemBuilder: (_, i) => _ExerciseCard(
                            key: ValueKey(_log.exercises[i].id),
                            exLog: _log.exercises[i],
                            exercise: _exercises[_log.exercises[i].id],
                            prevHints: _hints[_log.exercises[i].id] ?? [],
                            onAddSet: () => _addSet(_log.exercises[i]),
                            onSetChanged: (s) =>
                                _updateSet(_log.exercises[i], s),
                            onSetDeleted: (s) =>
                                _deleteSet(_log.exercises[i], s),
                            onRemove: () => _removeExercise(_log.exercises[i]),
                          ),
                        ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _log.completed
              ? Container(
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
                          fontSize: 15,
                        ),
                      ),
                    ],
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
                          'Complete Workout',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Exercise Card ────────────────────────────────────────────────────────────

class _ExerciseCard extends StatefulWidget {
  final ExerciseLog exLog;
  final Exercise? exercise;
  final List<String?> prevHints;
  final VoidCallback onAddSet;
  final ValueChanged<SetLog> onSetChanged;
  final ValueChanged<SetLog> onSetDeleted;
  final VoidCallback onRemove;

  const _ExerciseCard({
    super.key,
    required this.exLog,
    required this.exercise,
    required this.prevHints,
    required this.onAddSet,
    required this.onSetChanged,
    required this.onSetDeleted,
    required this.onRemove,
  });

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  if (ex != null)
                    ExerciseTile(exercise: ex, compact: true)
                  else
                    const Text('Unknown Exercise',
                        style: TextStyle(color: Colors.white)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white24, size: 18),
                    onPressed: widget.onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF444466),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(color: Color(0xFF1E1E35), height: 1),
            if (widget.prevHints.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded,
                        color: Color(0xFF444466), size: 13),
                    const SizedBox(width: 6),
                    Text(
                      'Last: ${widget.prevHints.first ?? '—'}',
                      style: const TextStyle(
                          color: Color(0xFF555577), fontSize: 12),
                    ),
                  ],
                ),
              ),
            if (widget.exLog.sets.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    SizedBox(
                        width: 28,
                        child: Text('SET',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF444466),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1))),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('WEIGHT',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF444466),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1))),
                    SizedBox(width: 8),
                    SizedBox(width: 12),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('REPS',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF444466),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1))),
                    SizedBox(width: 28),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                children: widget.exLog.sets
                    .asMap()
                    .entries
                    .map((entry) => SetLogTile(
                          key: ValueKey(entry.value.id),
                          setLog: entry.value,
                          setIndex: entry.key,
                          previousHint: widget.prevHints.isNotEmpty &&
                                  entry.key < widget.prevHints.length
                              ? widget.prevHints[entry.key]
                              : null,
                          onChanged: widget.onSetChanged,
                          onDelete: () => widget.onSetDeleted(entry.value),
                        ))
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: GestureDetector(
                onTap: widget.onAddSet,
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: Color(0xFFFFD700), size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Add Set',
                        style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.w600,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _QuickStat({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: valueColor ?? const Color(0xFFFFD700),
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Text(label,
              style: const TextStyle(color: Color(0xFF555577), fontSize: 11)),
        ],
      );
}

class _VSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 24,
        color: const Color(0xFF1E1E35),
      );
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
                prefixIcon:
                    const Icon(Icons.search, color: Color(0xFF888899)),
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
                  })),
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

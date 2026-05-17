import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_log.dart';
import '../widgets/exercise_tile.dart';
import '../widgets/muscle_group_filter.dart';
import 'workout_logging_screen.dart';

// PPL preset exercise name lists — matched to seeded DB names
const _kPplPresets = <String, List<String>>{
  'Push A': [
    'Bench Press',
    'Incline Dumbbell Press',
    'Dumbbell Shoulder Press',
    'Lateral Raises',
    'Tricep Pushdown',
    'Skull Crushers',
  ],
  'Push B': [
    'Incline Bench Press',
    'Cable Crossover',
    'Overhead Press',
    'Arnold Press',
    'Overhead Tricep Extension',
    'Diamond Push-ups',
  ],
  'Pull A': [
    'Pull-ups',
    'Barbell Row',
    'Seated Cable Row',
    'Barbell Curl',
    'Hammer Curl',
    'Face Pulls',
  ],
  'Pull B': [
    'Lat Pulldown',
    'Single Arm DB Row',
    'Chest Supported Row',
    'EZ Bar Curl',
    'Incline DB Curl',
    'Dumbbell Curl',
  ],
  'Legs A': [
    'Squat',
    'Leg Press',
    'Romanian Deadlift',
    'Leg Extension',
    'Leg Curl',
    'Standing Calf Raise',
  ],
  'Legs B': [
    'Deadlift',
    'Hip Thrust',
    'Walking Lunges',
    'Goblet Squat',
    'Leg Curl',
    'Calf Raises',
  ],
};

const _kMuscleGroups = <String, List<String>>{
  'Chest': ['Chest'],
  'Back': ['Back'],
  'Shoulders': ['Shoulders'],
  'Arms': ['Arms'],
  'Legs': ['Legs'],
  'Core': ['Core'],
  'Full Body': ['Chest', 'Back', 'Shoulders', 'Legs'],
};

class QuickStartScreen extends StatefulWidget {
  final String targetDate;
  // When provided, skip step 1 and go straight to the exercise editor
  final String? preloadedName;
  final List<Exercise>? preloadedExercises;

  const QuickStartScreen({
    super.key,
    required this.targetDate,
    this.preloadedName,
    this.preloadedExercises,
  });

  @override
  State<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends State<QuickStartScreen> {
  final _db = WorkoutDatabase.instance;

  late int _step;
  late String _workoutName;
  late List<Exercise> _exercises;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedExercises != null) {
      _step = 2;
      _workoutName = widget.preloadedName ?? 'Workout';
      _exercises = List.from(widget.preloadedExercises!);
    } else {
      _step = 1;
      _workoutName = '';
      _exercises = [];
    }
  }

  Future<void> _pickPreset(String name, List<String> exerciseNames) async {
    setState(() => _loading = true);
    final found = await _db.getExercisesByNames(exerciseNames);
    setState(() {
      _workoutName = name;
      _exercises = found;
      _step = 2;
      _loading = false;
    });
  }

  Future<void> _pickMuscleGroup(String label, List<String> groups) async {
    setState(() => _loading = true);
    final found = await _db.getExercisesByMuscleGroups(groups, limit: 6);
    setState(() {
      _workoutName = label;
      _exercises = found;
      _step = 2;
      _loading = false;
    });
  }

  Future<void> _startWorkout() async {
    if (_exercises.isEmpty) return;
    setState(() => _loading = true);
    const uuid = Uuid();
    final log = WorkoutLog(
      id: uuid.v4(),
      date: widget.targetDate,
      workoutName: _workoutName,
    );
    final created = await _db.createOrGetWorkoutLog(log);
    for (int i = 0; i < _exercises.length; i++) {
      await _db.createExerciseLog(ExerciseLog(
        id: uuid.v4(),
        workoutLogId: created.id,
        exerciseId: _exercises[i].id,
        orderIndex: i,
      ));
    }
    final fullLog = await _db.getWorkoutLogForDate(widget.targetDate);
    setState(() => _loading = false);
    if (fullLog != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutLoggingScreen(workoutLog: fullLog),
        ),
      );
    }
  }

  Future<void> _addExercise() async {
    final result = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExercisePickerSheet(),
    );
    if (result != null && mounted) {
      setState(() {
        if (!_exercises.any((e) => e.id == result.id)) {
          _exercises.add(result);
        }
      });
    }
  }

  void _removeExercise(int index) => setState(() => _exercises.removeAt(index));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        leading: _step == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // If started at step 2 (preloaded), back = pop screen
                  if (widget.preloadedExercises != null) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _step = 1;
                      _exercises = [];
                    });
                  }
                },
              )
            : null,
        title: Text(
          _step == 1 ? 'Quick Start' : _workoutName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            )
          : _step == 1
              ? _buildStep1()
              : _buildStep2(),
    );
  }

  // ─── Step 1: pick workout type ─────────────────────────────────────────────

  Widget _buildStep1() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader('PPL Training Split', 'Push / Pull / Legs periodized program'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: _kPplPresets.entries
              .map((e) => _PplCard(
                    label: e.key,
                    count: e.value.length,
                    color: _pplColor(e.key),
                    icon: _pplIcon(e.key),
                    onTap: () => _pickPreset(e.key, e.value),
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
        _sectionHeader('Muscle Group', 'Focus on a specific muscle group'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: _kMuscleGroups.entries
              .map((e) => _MgCard(
                    label: e.key,
                    onTap: () => _pickMuscleGroup(e.key, e.value),
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            )),
        const SizedBox(height: 2),
        Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }

  Color _pplColor(String preset) {
    if (preset.startsWith('Push')) return const Color(0xFFEF9A9A);
    if (preset.startsWith('Pull')) return const Color(0xFF90CAF9);
    return const Color(0xFFA5D6A7);
  }

  IconData _pplIcon(String preset) {
    if (preset.startsWith('Push')) return Icons.fitness_center;
    if (preset.startsWith('Pull')) return Icons.south;
    return Icons.directions_run;
  }

  // ─── Step 2: review & edit exercises ──────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              const Text(
                'Drag to reorder · swipe left to remove',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: _exercises.isEmpty
              ? const Center(
                  child: Text('No exercises. Tap Add to add some.',
                      style: TextStyle(color: Colors.white38)),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  onReorder: (old, nw) {
                    setState(() {
                      final ex = _exercises.removeAt(old);
                      _exercises.insert(nw > old ? nw - 1 : nw, ex);
                    });
                  },
                  itemCount: _exercises.length,
                  itemBuilder: (_, i) {
                    final ex = _exercises[i];
                    return Dismissible(
                      key: ValueKey('${ex.id}_$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                      onDismissed: (_) => _removeExercise(i),
                      child: Card(
                        key: ValueKey('card_${ex.id}_$i'),
                        color: const Color(0xFF1A1A2E),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFFFFD700).withValues(alpha: 0.15),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            ex.name,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            '${ex.muscleGroup} · ${ex.equipment}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white38, size: 18),
                                onPressed: () => _removeExercise(i),
                              ),
                              const Icon(Icons.drag_handle,
                                  color: Colors.white24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _addExercise,
            icon: const Icon(Icons.add, color: Color(0xFFFFD700), size: 18),
            label: const Text('Add',
                style: TextStyle(color: Color(0xFFFFD700))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFFD700)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _exercises.isEmpty ? null : _startWorkout,
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: const Text(
                'Start Workout',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                disabledBackgroundColor: Colors.white12,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PPL preset card ──────────────────────────────────────────────────────────

class _PplCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _PplCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const Spacer(),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Text('$count exercises',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Muscle group card ────────────────────────────────────────────────────────

class _MgCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MgCard({required this.label, required this.onTap});

  static const _icons = <String, IconData>{
    'Chest': Icons.fitness_center,
    'Back': Icons.accessibility_new,
    'Shoulders': Icons.sports_handball,
    'Arms': Icons.sports_martial_arts,
    'Legs': Icons.directions_run,
    'Core': Icons.circle_outlined,
    'Full Body': Icons.person,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _icons[label] ?? Icons.fitness_center,
                color: const Color(0xFFFFD700),
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Exercise picker bottom sheet ─────────────────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet();

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _db = WorkoutDatabase.instance;
  final _ctrl = TextEditingController();
  List<Exercise> _all = [];
  List<Exercise> _filtered = [];
  String? _group;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await _db.getAllExercises();
    setState(() {
      _all = all;
      _filtered = all;
    });
  }

  void _filter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = _all
          .where((e) =>
              (_group == null || e.muscleGroup == _group) &&
              (q.isEmpty || e.name.toLowerCase().contains(q)))
          .toList();
    });
  }

  void _onGroup(String? g) {
    setState(() => _group = g);
    _filter(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Add Exercise',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                onChanged: _filter,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search exercises...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            MuscleGroupFilter(selected: _group, onChanged: _onGroup),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => ExerciseTile(
                  exercise: _filtered[i],
                  compact: true,
                  onTap: () => Navigator.pop(context, _filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_plan_day.dart';
import '../widgets/exercise_tile.dart';
import '../widgets/muscle_group_filter.dart';
import 'exercise_library_screen.dart';

class WorkoutPlanScreen extends StatefulWidget {
  const WorkoutPlanScreen({super.key});

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen> {
  final _db = WorkoutDatabase.instance;
  // day_of_week (1-7) -> WorkoutPlanDay
  final Map<int, WorkoutPlanDay> _plan = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final days = await _db.getWorkoutPlan();
    final map = <int, WorkoutPlanDay>{};
    for (final d in days) {
      map[d.dayOfWeek] = d;
    }
    // Ensure all 7 days exist with defaults
    const uuid = Uuid();
    for (int i = 1; i <= 7; i++) {
      map.putIfAbsent(
        i,
        () => WorkoutPlanDay(
          id: uuid.v4(),
          dayOfWeek: i,
          workoutName: i == 7 ? 'Rest' : 'Workout ${kDayAbbreviations[i - 1]}',
          isRestDay: i == 7,
        ),
      );
    }
    if (mounted) setState(() { _plan.addAll(map); _loading = false; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    for (final day in _plan.values) {
      await _db.savePlanDay(day);
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Weekly plan saved!'),
          backgroundColor: Color(0xFF2ECC71),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _loadPplPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Load PPL Plan',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This replaces your current weekly plan with the 6-day Push / Pull / Legs schedule from your training plan.\n\nMon: Push A  ·  Tue: Pull A  ·  Wed: Legs A\nThu: Push B  ·  Fri: Pull B  ·  Sat: Legs B  ·  Sun: Rest',
          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9B59B6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Load Plan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    await _db.loadPplWeeklyPlan();
    await _load();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PPL plan loaded!'),
          backgroundColor: Color(0xFF9B59B6),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _editDay(int dayOfWeek) {
    final day = _plan[dayOfWeek]!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DayEditorSheet(
        day: day,
        onSave: (updated) {
          setState(() => _plan[dayOfWeek] = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('Weekly Plan',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Color(0xFFFFD700), strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined,
                  color: Color(0xFF9B59B6), size: 20),
              tooltip: 'Load PPL Plan',
              onPressed: _loadPplPlan,
            ),
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 7,
              itemBuilder: (_, i) {
                final day = _plan[i + 1]!;
                return _DayCard(
                  day: day,
                  onTap: () => _editDay(i + 1),
                );
              },
            ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final WorkoutPlanDay day;
  final VoidCallback onTap;

  const _DayCard({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = day.isRestDay
        ? const Color(0xFF3498DB)
        : const Color(0xFFFFD700);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  kDayAbbreviations[day.dayOfWeek - 1],
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kDayNames[day.dayOfWeek - 1],
                    style: const TextStyle(
                        color: Color(0xFF888899), fontSize: 12),
                  ),
                  Text(
                    day.workoutName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  if (!day.isRestDay)
                    Text(
                      '${day.exerciseIds.length} exercises',
                      style: const TextStyle(
                          color: Color(0xFF888899), fontSize: 12),
                    ),
                ],
              ),
            ),
            Icon(
              day.isRestDay ? Icons.self_improvement : Icons.fitness_center,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                color: Color(0xFF555566), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── DAY EDITOR BOTTOM SHEET ─────────────────────────────────────────────────

class _DayEditorSheet extends StatefulWidget {
  final WorkoutPlanDay day;
  final ValueChanged<WorkoutPlanDay> onSave;

  const _DayEditorSheet({required this.day, required this.onSave});

  @override
  State<_DayEditorSheet> createState() => _DayEditorSheetState();
}

class _DayEditorSheetState extends State<_DayEditorSheet> {
  late TextEditingController _nameCtrl;
  late bool _isRest;
  late List<String> _exerciseIds;
  List<Exercise> _exercises = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.day.workoutName);
    _isRest = widget.day.isRestDay;
    _exerciseIds = List.from(widget.day.exerciseIds);
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    final all = await WorkoutDatabase.instance.getAllExercises();
    if (mounted) setState(() { _exercises = all; _loading = false; });
  }

  void _save() {
    widget.onSave(
      widget.day.copyWith(
        workoutName: _nameCtrl.text.trim().isEmpty
            ? kDayNames[widget.day.dayOfWeek - 1]
            : _nameCtrl.text.trim(),
        isRestDay: _isRest,
        exerciseIds: _isRest ? [] : _exerciseIds,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _pickExercise() async {
    final picked = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(builder: (_) => const _ExercisePickerScreen()),
    );
    if (picked != null && !_exerciseIds.contains(picked.id)) {
      setState(() => _exerciseIds.add(picked.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayName = kDayNames[widget.day.dayOfWeek - 1];
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333355),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text(
                  dayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _save,
                  child: const Text('Done',
                      style: TextStyle(
                          color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF333355)),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFD700)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // Rest Day Toggle
                      _SectionLabel('Day Type'),
                      Row(
                        children: [
                          _TypeChip(
                            label: 'Workout',
                            icon: Icons.fitness_center,
                            selected: !_isRest,
                            color: const Color(0xFFFFD700),
                            onTap: () => setState(() => _isRest = false),
                          ),
                          const SizedBox(width: 10),
                          _TypeChip(
                            label: 'Rest Day',
                            icon: Icons.self_improvement,
                            selected: _isRest,
                            color: const Color(0xFF3498DB),
                            onTap: () => setState(() => _isRest = true),
                          ),
                        ],
                      ),
                      if (!_isRest) ...[
                        const SizedBox(height: 20),
                        _SectionLabel('Workout Name'),
                        TextField(
                          controller: _nameCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDec('e.g. Push Day, Pull Day…'),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _SectionLabel('Exercises'),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _pickExercise,
                              icon: const Icon(Icons.add,
                                  color: Color(0xFFFFD700), size: 16),
                              label: const Text('Add',
                                  style: TextStyle(color: Color(0xFFFFD700))),
                            ),
                          ],
                        ),
                        if (_exerciseIds.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No exercises yet. Tap Add to choose.',
                              style: TextStyle(
                                  color: Color(0xFF888899), fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _exerciseIds.length,
                            onReorder: (o, n) {
                              setState(() {
                                if (n > o) n--;
                                final item = _exerciseIds.removeAt(o);
                                _exerciseIds.insert(n, item);
                              });
                            },
                            itemBuilder: (_, i) {
                              final id = _exerciseIds[i];
                              final ex = _exercises.firstWhere(
                                (e) => e.id == id,
                                orElse: () => Exercise(
                                  id: id,
                                  name: 'Unknown',
                                  muscleGroup: 'Other',
                                  equipment: 'Other',
                                ),
                              );
                              return Padding(
                                key: ValueKey(id),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ExerciseTile(
                                  exercise: ex,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Color(0xFF888899), size: 18),
                                    onPressed: () =>
                                        setState(() => _exerciseIds.remove(id)),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555566)),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF333355)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF333355)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFD700)),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF888899),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : const Color(0xFF333355),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? color : const Color(0xFF888899), size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: selected ? color : const Color(0xFF888899),
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      );
}

// ─── EXERCISE PICKER ─────────────────────────────────────────────────────────

class _ExercisePickerScreen extends StatefulWidget {
  const _ExercisePickerScreen();

  @override
  State<_ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<_ExercisePickerScreen> {
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
    if (mounted) setState(() { _all = all; _filtered = all; });
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

  void _setGroup(String? g) {
    _group = g;
    _filter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('Pick Exercise',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search exercises…',
                hintStyle: const TextStyle(color: Color(0xFF555566)),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCustom,
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('New Exercise',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          MuscleGroupFilter(selected: _group, onChanged: _setGroup),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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

  Future<void> _createCustom() async {
    final result = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExerciseFormSheet(),
    );
    if (result != null && mounted) {
      await _db.createExercise(result);
      await _load();
      // Auto-select the newly created exercise and pop
      Navigator.pop(context, result);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../widgets/exercise_tile.dart';
import '../widgets/muscle_group_filter.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
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
    if (mounted) setState(() { _all = all; _filter(); });
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
    setState(() => _group = g);
    _filter();
  }

  Future<void> _addOrEdit([Exercise? existing]) async {
    final result = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExerciseFormSheet(existing: existing),
    );
    if (result != null) {
      if (existing == null) {
        await _db.createExercise(result);
      } else {
        await _db.updateExercise(result);
      }
      _load();
    }
  }

  Future<void> _delete(Exercise ex) async {
    if (!ex.isCustom) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default exercises cannot be deleted.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF333355),
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Exercise',
            style: TextStyle(color: Colors.white)),
        content: Text('Remove "${ex.name}"?',
            style: const TextStyle(color: Color(0xFFCCCCDD))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888899))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteExercise(ex.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('Exercise Library',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
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
        onPressed: () => _addOrEdit(),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Custom',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          MuscleGroupFilter(selected: _group, onChanged: _setGroup),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_filtered.length} exercises',
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final ex = _filtered[i];
                return Dismissible(
                  key: ValueKey(ex.id),
                  direction: ex.isCustom
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE74C3C).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete,
                        color: Color(0xFFE74C3C)),
                  ),
                  confirmDismiss: (_) async {
                    await _delete(ex);
                    return false;
                  },
                  child: ExerciseTile(
                    exercise: ex,
                    onTap: ex.isCustom ? () => _addOrEdit(ex) : null,
                    trailing: ex.isCustom
                        ? const Icon(Icons.edit_outlined,
                            color: Color(0xFF888899), size: 18)
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── EXERCISE FORM SHEET ─────────────────────────────────────────────────────

class ExerciseFormSheet extends StatefulWidget {
  final Exercise? existing;
  const ExerciseFormSheet({super.key, this.existing});

  @override
  State<ExerciseFormSheet> createState() => _ExerciseFormSheetState();
}

class _ExerciseFormSheetState extends State<ExerciseFormSheet> {
  late TextEditingController _nameCtrl;
  late String _group;
  late String _equipment;
  late String _exerciseType; // 'strength' or 'cardio'

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _exerciseType = widget.existing?.exerciseType ?? 'strength';
    if (_exerciseType == 'cardio') {
      _group = 'Cardio';
      _equipment = _validCardioEquipment(widget.existing?.equipment);
    } else {
      _group = widget.existing?.muscleGroup ?? kMuscleGroups.first;
      _equipment = _validStrengthEquipment(widget.existing?.equipment);
    }
  }

  String _validCardioEquipment(String? v) =>
      kCardioMachineTypes.contains(v) ? v! : kCardioMachineTypes.first;

  String _validStrengthEquipment(String? v) =>
      kEquipmentTypes.contains(v) ? v! : kEquipmentTypes.first;

  void _switchType(String type) {
    setState(() {
      _exerciseType = type;
      if (type == 'cardio') {
        _group = 'Cardio';
        _equipment = kCardioMachineTypes.first;
      } else {
        _group = kMuscleGroups.first;
        _equipment = kEquipmentTypes.first;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) return;
    const uuid = Uuid();
    final ex = Exercise(
      id: widget.existing?.id ?? uuid.v4(),
      name: _nameCtrl.text.trim(),
      muscleGroup: _group,
      equipment: _equipment,
      isCustom: true,
      exerciseType: _exerciseType,
    );
    Navigator.pop(context, ex);
  }

  @override
  Widget build(BuildContext context) {
    final isCardio = _exerciseType == 'cardio';
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF333355),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.existing == null ? 'New Exercise' : 'Edit Exercise',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Strength / Cardio toggle
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _TypeTab(
                    label: 'Strength',
                    icon: Icons.fitness_center,
                    selected: !isCardio,
                    onTap: () => _switchType('strength'),
                  ),
                  _TypeTab(
                    label: 'Cardio',
                    icon: Icons.directions_run,
                    selected: isCardio,
                    onTap: () => _switchType('cardio'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _Label('Exercise Name'),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(isCardio
                  ? 'e.g. Morning Cardio'
                  : 'e.g. Incline Dumbbell Press'),
            ),
            const SizedBox(height: 16),
            if (!isCardio) ...[
              const _Label('Muscle Group'),
              _DropdownField(
                value: _group,
                items: kMuscleGroups,
                onChanged: (v) => setState(() => _group = v!),
              ),
              const SizedBox(height: 16),
              const _Label('Equipment'),
              _DropdownField(
                value: _equipment,
                items: kEquipmentTypes,
                onChanged: (v) => setState(() => _equipment = v!),
              ),
            ] else ...[
              const _Label('Machine Type'),
              _DropdownField(
                value: _equipment,
                items: kCardioMachineTypes,
                onChanged: (v) => setState(() => _equipment = v!),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  widget.existing == null ? 'Add Exercise' : 'Save Changes',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF888899),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      );
}

class _TypeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFD700) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16,
                  color: selected ? Colors.black : const Color(0xFF888899)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : const Color(0xFF888899),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333355)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A2E),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: Color(0xFF888899)),
          items: items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
